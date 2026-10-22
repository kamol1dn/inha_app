import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/credentials.dart';
import '../core/session.dart';
import '../data/app_data.dart';
import '../models/models.dart';
import '../notifications/notifier.dart';
import '../notifications/rules.dart';
import '../ui/format/format.dart';
import '../ui/theme/status_colors.dart';
import 'common.dart';

/// What each notification switch covers, in the student's words (DESIGN.md 11).
const _channelText = {
  NotifyChannel.deadlines: ('Deadlines', 'Assignments and quizzes, 24 h and 3 h before they are due'),
  NotifyChannel.vod: ('VOD windows', 'Lecture videos not fully watched, 48 h and 6 h before the window closes'),
  NotifyChannel.attendance: ('Attendance', 'When eClass records a new absence'),
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

  @override
  void initState() {
    super.initState();
    _load();
    _loadNotify();
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

  Future<void> _allowNotifications() async {
    await context.read<Notifier>().requestPermission();
    await _loadNotify();
  }

  @override
  Widget build(BuildContext context) {
    final data = context.watch<AppData>();
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(children: [
        const SectionHeader('Accounts'),
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
        const SectionHeader('Timetable'),
        ListTile(
          title: const Text('Class group'),
          subtitle: Text(data.prefs.classGroup),
          onTap: _editGroup,
        ),
        ListTile(
          title: const Text('Hidden subjects'),
          subtitle: Text(data.prefs.excludedSubjects.isEmpty ? 'None' : data.prefs.excludedSubjects.join(', ')),
          onTap: _editHidden,
        ),
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Passwords are kept in Android\'s encrypted storage on this phone and are '
            'only sent to the service they belong to.',
          ),
        ),
      ]),
    );
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
    final c = TextEditingController(text: data.prefs.classGroup);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Class group'),
        content: TextField(controller: c, decoration: const InputDecoration(hintText: 'ICE23-1')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (v != null && v.isNotEmpty) {
      data.prefs.classGroup = v;
      setState(() {});
      data.refreshTimetable();
    }
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
  final _pass = TextEditingController();
  bool _showPassword = false;
  bool _busy = false;
  bool _tested = false;
  Object? _error;
  String? _missing;

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _saveAndTest() async {
    final user = _user.text.trim();
    final password = _pass.text.isEmpty ? widget.existing?.password : _pass.text;
    if (user.isEmpty || password == null || password.isEmpty) {
      setState(() => _missing = user.isEmpty ? 'Enter the student ID.' : 'Enter the password.');
      return;
    }
    final store = context.read<CredentialStore>();
    final sessions = context.read<Sessions>();
    final data = context.read<AppData>();
    setState(() {
      _busy = true;
      _missing = null;
      _tested = false;
    });
    await store.write(widget.service, Credentials(user, password));
    await sessions.reset(widget.service); // so the test really logs in
    final error = await data.testLogin(widget.service);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _tested = true;
      _error = error;
    });
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
    if (mounted) Navigator.pop(context);
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
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(widget.title, style: t.textTheme.titleMedium),
            const SizedBox(height: 16),
            TextField(
              controller: _user,
              // All three services log in with the student ID, mail included.
              decoration: const InputDecoration(labelText: 'Student ID', border: OutlineInputBorder()),
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
                border: const OutlineInputBorder(),
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
