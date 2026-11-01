import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../core/credentials.dart';
import '../core/session.dart';
import '../data/app_data.dart';
import '../models/models.dart';
import '../notifications/notifier.dart';
import '../notifications/rules.dart';
import '../ui/format/format.dart';
import '../ui/theme/status_colors.dart';
import 'absence_widgets.dart';
import 'common.dart';
import 'update_prompt.dart';

/// What each notification switch covers, in the student's words (DESIGN.md 11).
const _channelText = {
  NotifyChannel.deadlines: ('Deadlines', 'Assignments and quizzes, 24 h and 3 h before they are due'),
  NotifyChannel.vod: ('VOD windows', 'Lecture videos not fully watched, 48 h and 6 h before the window closes'),
  NotifyChannel.exams: ('Exams', 'The evening before and 1 h before each exam, with the room'),
  NotifyChannel.attendance: ('Attendance', 'When eClass records a new absence'),
  NotifyChannel.grades: ('Grades', 'When eClass shows a new or changed mark'),
  NotifyChannel.announcements: ('eClass notifications', "New items in eClass's notification menu"),
  NotifyChannel.classes: ('Classes', 'The room, 15 min before each class'),
};

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final Map<Service, String?> _users = {};
  NotifySettings? _notify;
  bool _notifyAllowed = true;
  String? _version;

  @override
  void initState() {
    super.initState();
    _load();
    _loadNotify();
    _loadVersion();
  }

  /// "1.3.0 (4)". The next exam sheet comes with an app update and there is no
  /// store to compare with, so the student can tell here which one they run.
  Future<void> _loadVersion() async {
    try {
      final p = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _version = '${p.version} (${p.buildNumber})');
    } catch (_) {
      // No version to show, and nothing else depends on it.
    }
  }

  Future<void> _load() async {
    final store = context.read<CredentialStore>();
    for (final s in Service.values.where((s) => s.needsLogin)) {
      _users[s] = (await store.read(s))?.username;
    }
    if (mounted) setState(() {});
  }

  Future<void> _loadNotify() async {
    final notifier = context.read<Notifier>();
    final settings = await notifier.settings();
    final allowed = await notifier.enabled();
    if (mounted) {
      setState(() {
        _notify = settings;
        _notifyAllowed = allowed;
      });
    }
  }

  /// Saves the switches and re-plans the reminders at once, so a channel
  /// turned off loses its scheduled reminders now, not at the next refresh.
  Future<void> _setNotify(NotifySettings s) async {
    setState(() => _notify = s);
    await context.read<Notifier>().saveSettings(s);
    if (mounted) await context.read<AppData>().onReminderDataChanged?.call();
  }

  /// While notifications were off nothing was planned, so a yes plans them now.
  Future<void> _allowNotifications() async {
    final data = context.read<AppData>();
    final granted = await context.read<Notifier>().requestPermission();
    await _loadNotify();
    if (granted) await data.onReminderDataChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final data = context.watch<AppData>();
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(children: [
        const SyncStrip(),
        const SectionHeader('Accounts', first: true),
        for (final s in Service.values.where((s) => s.needsLogin))
          ListTile(
            minTileHeight: 72,
            title: Text(_accountTitle(s)),
            subtitle: _accountStatus(s, data.prefs.accountCheck(s)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _editLogin(s),
          ),
        const SectionHeader('Notifications'),
        if (!_notifyAllowed)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(children: [
              const Expanded(child: StatusLine(Status.warning, 'Android is not letting this app post notifications.')),
              TextButton(onPressed: _allowNotifications, child: const Text('Allow')),
            ]),
          ),
        if (_notify case final n?) ...[
          for (final c in NotifyChannel.values)
            SwitchListTile(
              title: Text(_channelText[c]!.$1),
              subtitle: Text(_channelText[c]!.$2),
              value: n.channels.contains(c),
              onChanged: (on) =>
                  _setNotify(n.copyWith(channels: on ? {...n.channels, c} : ({...n.channels}..remove(c)))),
            ),
          SwitchListTile(
            title: const Text('Quiet hours'),
            subtitle: const Text('23:00–07:30. Reminders wait until 07:30, or come at 22:00 when that would be '
                'too late.'),
            value: n.quietHours,
            onChanged: (on) => _setNotify(n.copyWith(quietHours: on)),
          ),
        ],
        const SectionHeader('Courses'),
        ListTile(
          title: const Text('Absence limits'),
          subtitle: Text(_limitsSummary(data)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const AbsenceLimitsScreen(fromSettings: true))),
        ),
        const SectionHeader('Timetable'),
        ListTile(
          title: const Text('Class group'),
          subtitle: Text(data.prefs.classGroup.isEmpty ? 'Not chosen' : data.prefs.classGroup),
          onTap: _editGroup,
        ),
        ListTile(
          title: const Text('Hidden subjects'),
          subtitle: Text(data.prefs.excludedSubjects.isEmpty ? 'None' : data.prefs.excludedSubjects.join(', ')),
          onTap: _editHidden,
        ),
        const SectionHeader('Appearance'),
        ListTile(
          title: const Text('Theme'),
          subtitle: Text(_themeNames[data.prefs.themeMode]!),
          onTap: _editTheme,
        ),
        const SectionHeader('About'),
        if (_version case final v?) ListTile(title: Text('Version $v')),
        ListTile(
          title: const Text('Check for updates'),
          subtitle: const Text('New versions are on the GitHub releases page'),
          onTap: () => checkForUpdateNow(context),
        ),
        ListTile(
          title: const Text('Open-source licences'),
          subtitle: const Text('Including the Fraunces and Public Sans fonts'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => showLicensePage(context: context, applicationName: 'IUT', applicationVersion: _version),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(gutter, 8, gutter, 24),
          child: Text(
            "Passwords are kept in Android's encrypted storage on this phone and are "
            'only sent to the service they belong to. The app talks to no one else.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
      ]),
    );
  }

  static const _themeNames = {ThemeMode.system: 'System', ThemeMode.light: 'Light', ThemeMode.dark: 'Dark'};

  Future<void> _editTheme() async {
    final data = context.read<AppData>();
    final picked = await showDialog<ThemeMode>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Theme'),
        contentPadding: const EdgeInsets.only(top: 16, bottom: 8),
        content: RadioGroup<ThemeMode>(
          groupValue: data.prefs.themeMode,
          onChanged: (m) => Navigator.pop(ctx, m),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final e in _themeNames.entries)
              RadioListTile<ThemeMode>(
                value: e.key,
                title: Text(e.value),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              ),
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel'))],
      ),
    );
    if (picked != null) data.setThemeMode(picked);
  }

  static String _limitsSummary(AppData data) {
    final tracked = [...?data.attendance.data?.value.where((c) => c.classes.isNotEmpty)];
    final set = tracked.where((c) => data.prefs.absenceLimits.containsKey(c.course.id)).length;
    if (tracked.isEmpty) return 'For courses with attendance in eClass';
    return set == 0 ? 'Not set' : '$set of ${tracked.length} courses set';
  }

  String _accountTitle(Service s) => switch (s) {
        Service.eclass => 'eClass',
        Service.ins => 'INS (grades)',
        Service.mail => 'University mail',
        Service.edupage => 'Timetable',
      };

  /// "Signed in as U… · checked 08:41", "Sign-in rejected · 08:41" or
  /// "Not set up" (DESIGN.md 8, Settings).
  Widget _accountStatus(Service s, AccountCheck? check) {
    final user = _users[s];
    if (user == null) return const Text('Not set up');
    if (check == null) return Text('$user · not checked yet');
    if (check.ok) return Text('Signed in as $user · checked ${updatedAt(check.at)}');
    return StatusLine(Status.danger, 'Sign-in rejected · checked ${updatedAt(check.at)}', padding: EdgeInsets.zero);
  }

  Future<void> _editLogin(Service s) async {
    final existing = await context.read<CredentialStore>().read(s);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _LoginSheet(service: s, title: _accountTitle(s), existing: existing),
    );
    await _load();
  }

  /// Subjects EduPage lists for the group that the student doesn't take
  /// (dropped, or another track's). Offered: what the timetable shows now,
  /// plus what is already hidden.
  Future<void> _editHidden() async {
    final data = context.read<AppData>();
    final hidden = {...data.prefs.excludedSubjects};
    final subjects = {
      for (final l in data.lessons.data?.value ?? const <Lesson>[]) l.subject,
      ...hidden,
    }.toList()
      ..sort();
    final saved = await showDialog<Set<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => AlertDialog(
          title: const Text('Hidden subjects'),
          contentPadding: const EdgeInsets.only(top: 16),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(shrinkWrap: true, children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Text('Checked subjects are left out of Today and Schedule.'),
              ),
              for (final s in subjects)
                CheckboxListTile(
                  value: hidden.contains(s),
                  title: Text(s),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                  onChanged: (on) => setInner(() => on == true ? hidden.add(s) : hidden.remove(s)),
                ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, hidden), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (saved == null) return;
    data.prefs.excludedSubjects = saved;
    setState(() {});
    data.refreshTimetable();
  }

  Future<void> _editGroup() async {
    final data = context.read<AppData>();
    final v = await showDialog<String>(
      context: context,
      builder: (_) => _GroupDialog(current: data.prefs.classGroup, groups: data.classGroups()),
    );
    if (v != null && v.isNotEmpty) {
      data.prefs.classGroup = v;
      setState(() {});
      data.refreshTimetable();
    }
  }
}

/// The class group: EduPage's groups to tap, narrowed as the student types. If
/// EduPage can't list them, the name can still be typed. Owns its text
/// controller, which must outlive the closing animation.
class _GroupDialog extends StatefulWidget {
  final String current;
  final Future<List<String>> groups;
  const _GroupDialog({required this.current, required this.groups});

  @override
  State<_GroupDialog> createState() => _GroupDialogState();
}

class _GroupDialogState extends State<_GroupDialog> {
  late final _field = TextEditingController(text: widget.current);

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return AlertDialog(
      title: const Text('Class group'),
      contentPadding: const EdgeInsets.only(top: 16),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: TextField(
              controller: _field,
              autocorrect: false,
              decoration: const InputDecoration(hintText: 'ICE23-1'),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Flexible(
            child: FutureBuilder<List<String>>(
              future: widget.groups,
              builder: (context, s) {
                if (s.hasError) {
                  return const StatusLine(Status.warning, "Couldn't load the groups from EduPage. Type yours as the timetable names it.",
                      padding: EdgeInsets.fromLTRB(24, 12, 24, 0));
                }
                if (!s.hasData) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                    child: Text('Loading the groups from EduPage…',
                        style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                  );
                }
                final typed = _field.text.trim().toLowerCase();
                final matching = [for (final g in s.data!) if (g.toLowerCase().contains(typed) || g == widget.current) g];
                return ListView(shrinkWrap: true, padding: const EdgeInsets.only(top: 8), children: [
                  for (final g in matching)
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                      title: Text(g),
                      trailing: g == widget.current ? const Icon(Icons.check) : null,
                      onTap: () => Navigator.pop(context, g),
                    ),
                ]);
              },
            ),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, _field.text.trim()), child: const Text('Save')),
      ],
    );
  }
}

/// Username, password and "Save and test": the login is saved, then tried
/// at once, and the answer is shown here (DESIGN.md 8, Settings).
class _LoginSheet extends StatefulWidget {
  final Service service;
  final String title;
  final Credentials? existing;
  const _LoginSheet({required this.service, required this.title, required this.existing});

  @override
  State<_LoginSheet> createState() => _LoginSheetState();
}

class _LoginSheetState extends State<_LoginSheet> {
  late final _user = TextEditingController(text: widget.existing?.username);

  /// The login saved now: what the sheet opened with, until it saves another.
  late Credentials? _saved = widget.existing;
  final _pass = TextEditingController();
  bool _showPassword = false;
  bool _busy = false;
  bool _tested = false;
  Object? _error;
  String? _missing;

  /// What the fields held when the result on show was reached. A controller also
  /// notifies for the cursor, so this tells an edit from a tap.
  String _resultFor = '';

  String get _typed => '${_user.text}\u0000${_pass.text}';

  /// An edit after a test isn't saved: the button goes back to "Save and test",
  /// so "Done" can't close the sheet and lose it.
  void _edited() {
    if (_typed == _resultFor || (!_tested && _missing == null)) return;
    setState(() {
      _tested = false;
      _error = null;
      _missing = null;
    });
  }

  @override
  void initState() {
    super.initState();
    _user.addListener(_edited);
    _pass.addListener(_edited);
  }

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _saveAndTest() async {
    final user = _user.text.trim();
    // The saved password only ever goes with its own ID.
    final previous = _saved;
    final another = previous != null && previous.username.trim() != user;
    final password = _pass.text.isEmpty && !another ? previous?.password : _pass.text;
    if (user.isEmpty || password == null || password.isEmpty) {
      _resultFor = _typed;
      setState(() => _missing = user.isEmpty ? 'Enter the student ID.' : 'Enter the password.');
      return;
    }
    final store = context.read<CredentialStore>();
    final sessions = context.read<Sessions>();
    final data = context.read<AppData>();
    final typed = _typed;
    setState(() {
      _busy = true;
      _missing = null;
      _tested = false;
    });
    final login = Credentials(user, password);
    await store.write(widget.service, login);
    _saved = login;
    await sessions.reset(widget.service); // so the test really logs in
    // Another account now: nothing of the last one's stays, or its marks and
    // courses would be compared with this one's and announced as news.
    if (another) await data.forget(widget.service);
    final error = await data.testLogin(widget.service);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _tested = true;
      _resultFor = typed;
      _error = error;
    });
    _edited(); // typed on while the test ran
  }

  Future<void> _signOut() async {
    final label = widget.service.label;
    final store = context.read<CredentialStore>();
    final sessions = context.read<Sessions>();
    final data = context.read<AppData>();
    final notifier = context.read<Notifier>();
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Sign out of $label?'),
        content: Text('The saved login and the $label data are removed from this phone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    await store.clear(widget.service);
    await sessions.reset(widget.service);
    await data.forget(widget.service);
    // Deadline and VOD reminders come from eClass data that is gone now.
    if (widget.service == Service.eclass) {
      await notifier.deliver(const [], cancelMissing: {vodKeyPrefix, dueKeyPrefix});
    }
    await _refreshSignedOut(data);
    if (mounted) Navigator.pop(context);
  }

  /// With the login gone this fails at once, so the tabs say "Sign in" rather
  /// than wait on a loading skeleton for a refresh that isn't coming. That
  /// refusal was no login's, so it isn't kept as the account's status.
  Future<void> _refreshSignedOut(AppData data) async {
    await switch (widget.service) {
      Service.eclass => data.refreshEclass(),
      Service.ins => data.refreshGrades(),
      // Whichever folder the Mail tab is left on.
      Service.mail => Future.wait([
          data.refreshMail(),
          for (final f in MailFolder.values)
            if (f != MailFolder.inbox) data.refreshMailFolder(f),
        ]),
      Service.edupage => Future<void>.value(),
    };
    data.prefs.setAccountCheck(widget.service, null);
  }

  Widget? _result() {
    final label = widget.service.label;
    if (_missing case final m?) return StatusLine(Status.danger, m, padding: EdgeInsets.zero);
    if (!_tested) return null;
    final e = _error;
    if (e == null) return const StatusLine(Status.ok, 'Signed in', padding: EdgeInsets.zero);
    if (e is LoginRequired) {
      return StatusLine(Status.danger, '$label rejected this username or password.', padding: EdgeInsets.zero);
    }
    return StatusLine(Status.warning, '${describeError(e, label)} The login is saved and is tried again on the '
        'next refresh.', padding: EdgeInsets.zero);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final result = _result();
    final done = _tested && _error == null;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(gutter, 0, gutter, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(widget.title, style: t.textTheme.headlineSmall),
            const SizedBox(height: 16),
            TextField(
              controller: _user,
              // All three services log in with the student ID, mail included.
              decoration: const InputDecoration(labelText: 'Student ID'),
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pass,
              obscureText: !_showPassword,
              autocorrect: false,
              enableSuggestions: false,
              onSubmitted: (_) => _busy ? null : _saveAndTest(),
              decoration: InputDecoration(
                labelText: 'Password',
                helperText: widget.existing != null ? 'Leave empty to keep the saved one' : null,
                suffixIcon: IconButton(
                  tooltip: _showPassword ? 'Hide password' : 'Show password',
                  icon: Icon(_showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                  onPressed: () => setState(() => _showPassword = !_showPassword),
                ),
              ),
            ),
            if (result != null) ...[const SizedBox(height: 16), result],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : (done ? () => Navigator.pop(context) : _saveAndTest),
              child: _busy
                  ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(done ? 'Done' : 'Save and test'),
            ),
            if (widget.existing != null) ...[
              const SizedBox(height: 8),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: t.colorScheme.error),
                onPressed: _busy ? null : _signOut,
                child: const Text('Sign out'),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}
