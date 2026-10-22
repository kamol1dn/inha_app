import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/app_data.dart';
import 'notifications/notifier.dart';
import 'features/courses_screen.dart';
import 'features/deadlines_screen.dart';
import 'features/grades_screen.dart';
import 'features/mail_screen.dart';
import 'features/settings_screen.dart';
import 'features/timetable_screen.dart';
import 'features/today_screen.dart';
import 'ui/format/format.dart';
import 'ui/theme/app_colors.dart';
import 'ui/theme/app_text.dart';
import 'ui/theme/status_colors.dart';

class InhaApp extends StatelessWidget {
  const InhaApp({super.key});

  // DESIGN.md sections 3-5: explicit schemes, no seed, elevation 0, radius by role.
  static ThemeData _theme(ColorScheme scheme, StatusColors status) {
    final r8 = RoundedRectangleBorder(borderRadius: BorderRadius.circular(8));
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      textTheme: appTextTheme,
      scaffoldBackgroundColor: scheme.surface,
      extensions: [status],
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainer,
        elevation: 0,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(shape: r8)),
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(shape: r8)),
      chipTheme: ChipThemeData(shape: r8),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1, thickness: 1),
      listTileTheme: const ListTileThemeData(contentPadding: EdgeInsets.symmetric(horizontal: 16)),
      progressIndicatorTheme: ProgressIndicatorThemeData(linearMinHeight: 2, color: scheme.primary),
    );
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'IUT',
        theme: _theme(lightScheme, StatusColors.light),
        darkTheme: _theme(darkScheme, StatusColors.dark),
        home: const HomeShell(),
      );
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _tab = 0;
  final _timetable = GlobalKey<TimetableScreenState>();
  DateTime _lastRefresh = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _askForNotificationsOnce());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Android 13+ needs the user's OK to post notifications. Asked once, on
  /// the first launch; after that it lives in the system settings.
  Future<void> _askForNotificationsOnce() async {
    final data = context.read<AppData>();
    if (data.prefs.notificationsAsked) return;
    data.prefs.notificationsAsked = true;
    await context.read<Notifier>().requestPermission();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final data = context.read<AppData>();
    // Show what the background refresh fetched, then refresh if it's been a while.
    data.reloadFromCache().then((_) {
      if (DateTime.now().difference(_lastRefresh) > const Duration(minutes: 15)) {
        _lastRefresh = DateTime.now();
        data.refreshAll();
      }
    });
  }

  void _push(Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    final data = context.watch<AppData>();
    final unread = data.mailUnread.data?.value ??
        (data.inbox.data?.value ?? const []).where((m) => m.unread).length;
    final title = switch (_tab) {
      0 => dayDate(DateTime.now()),
      1 => 'Schedule',
      2 => 'Deadlines',
      _ => 'Courses',
    };
    return PopScope(
      canPop: _tab == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _tab = 0);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
          actions: [
            if (_tab == 0) ...[
              IconButton(
                tooltip: 'Mail',
                icon: Badge(
                  isLabelVisible: unread > 0,
                  label: Text('$unread'),
                  child: const Icon(Icons.mail_outline),
                ),
                onPressed: () => _push(const MailScreen()),
              ),
              IconButton(
                tooltip: 'Settings',
                icon: const Icon(Icons.settings_outlined),
                onPressed: () => _push(const SettingsScreen()),
              ),
            ],
            if (_tab == 3)
              TextButton(onPressed: () => _push(const GradesScreen()), child: const Text('Grades')),
          ],
          bottom: _anyLoading(data)
              ? const PreferredSize(
                  preferredSize: Size.fromHeight(2), child: LinearProgressIndicator())
              : null,
        ),
        body: IndexedStack(
          index: _tab,
          children: [
            TodayScreen(
              onOpenTab: (i) => setState(() => _tab = i),
              onOpenSchedule: (weekday) {
                setState(() => _tab = 1);
                _timetable.currentState?.showWeekday(weekday);
              },
            ),
            TimetableScreen(key: _timetable),
            const DeadlinesScreen(),
            const CoursesScreen(),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.today_outlined), selectedIcon: Icon(Icons.today), label: 'Today'),
            NavigationDestination(
                icon: Icon(Icons.calendar_view_day_outlined),
                selectedIcon: Icon(Icons.calendar_view_day),
                label: 'Schedule'),
            NavigationDestination(
                icon: Icon(Icons.assignment_outlined),
                selectedIcon: Icon(Icons.assignment),
                label: 'Deadlines'),
            NavigationDestination(
                icon: Icon(Icons.school_outlined), selectedIcon: Icon(Icons.school), label: 'Courses'),
          ],
        ),
      ),
    );
  }

  static bool _anyLoading(AppData d) =>
      d.lessons.loading || d.deadlines.loading || d.attendance.loading || d.inbox.loading ||
      d.mailUnread.loading;
}
