import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/credentials.dart';
import '../core/session.dart';
import '../data/app_data.dart';
import '../models/models.dart';
import '../notifications/notifier.dart';
import '../notifications/rules.dart';
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
            title: Text(_accountTitle(s)),
            subtitle: Text(_users[s] ?? 'Not signed in'),
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

  Future<void> _editLogin(Service s) async {
    final store = context.read<CredentialStore>();
    final sessions = context.read<Sessions>();
    final data = context.read<AppData>();
    final existing = await store.read(s);
    if (!mounted) return;
    final user = TextEditingController(text: existing?.username);
    final pass = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_accountTitle(s)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: user,
            // All three services log in with the student ID, mail included.
            decoration: const InputDecoration(labelText: 'Student ID'),
            autocorrect: false,
          ),
          TextField(
            controller: pass,
            decoration: InputDecoration(
                labelText: 'Password',
                helperText: existing != null ? 'Leave empty to keep the saved one' : null),
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
          ),
        ]),
        actions: [
          if (existing != null)
            TextButton(
              onPressed: () async {
                await store.clear(s);
                if (ctx.mounted) Navigator.pop(ctx, true);
              },
              child: const Text('Sign out'),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final p = pass.text.isEmpty ? existing?.password : pass.text;
              if (user.text.trim().isEmpty || p == null || p.isEmpty) return;
              await store.write(s, Credentials(user.text.trim(), p));
              if (ctx.mounted) Navigator.pop(ctx, true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved == true) {
      await sessions.reset(s);
      await _load();
      switch (s) {
        case Service.eclass:
          data.refreshEclass();
        case Service.ins:
          data.refreshGrades();
        case Service.mail:
          data.refreshMail();
        case Service.edupage:
          break;
      }
    }
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
