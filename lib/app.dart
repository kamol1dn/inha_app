import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/app_data.dart';
import 'notifications/notifier.dart';
import 'notifications/routes.dart';
import 'features/compose_screen.dart';
import 'features/details.dart';
import 'features/courses_screen.dart';
import 'features/deadlines_screen.dart';
import 'features/exams_screen.dart';
import 'features/grades_screen.dart';
import 'features/mail_screen.dart';
import 'features/settings_screen.dart';
import 'features/timetable_screen.dart';
import 'features/today_screen.dart';
import 'models/models.dart';
import 'ui/format/format.dart';
import 'ui/theme/app_colors.dart';
import 'ui/theme/app_text.dart';
import 'ui/theme/status_colors.dart';

/// The key of the last tapped notification, until HomeShell has opened it.
class NotificationTaps extends ValueNotifier<String?> {
  NotificationTaps() : super(null);
}

class InhaApp extends StatelessWidget {
  const InhaApp({super.key});

  static final light = _theme(lightScheme, StatusColors.light);
  static final dark = _theme(darkScheme, StatusColors.dark);

  // DESIGN.md sections 3-6: explicit schemes, paper and rules, elevation 0,
  // radius by role, the bundled faces on every component.
  static ThemeData _theme(ColorScheme scheme, StatusColors status) {
    final text = appTextTheme.apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);
    final r8 = RoundedRectangleBorder(borderRadius: BorderRadius.circular(8));
    final rule = BorderSide(color: scheme.outlineVariant);
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      textTheme: text,
      scaffoldBackgroundColor: scheme.surface,
      extensions: [status],
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.headlineSmall,
        shape: Border(bottom: rule),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        elevation: 0,
        height: 72,
        indicatorColor: const Color(0x00000000),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
            size: 24, color: s.contains(WidgetState.selected) ? scheme.primary : scheme.onSurfaceVariant)),
        labelTextStyle: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected)
            ? text.labelMedium!.copyWith(color: scheme.primary, fontWeight: FontWeight.w600)
            : text.labelMedium!.copyWith(color: scheme.onSurfaceVariant)),
      ),
      tabBarTheme: TabBarThemeData(
        indicator: UnderlineTabIndicator(borderSide: BorderSide(width: 2, color: scheme.onSurface)),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: scheme.outlineVariant,
        labelColor: scheme.onSurface,
        unselectedLabelColor: scheme.onSurfaceVariant,
      ),
      filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(shape: r8, textStyle: text.labelLarge, minimumSize: const Size(64, 48))),
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(shape: r8, textStyle: text.labelLarge)),
      chipTheme: ChipThemeData(
        shape: r8,
        side: BorderSide(color: scheme.outline),
        labelStyle: text.bodyMedium!.copyWith(fontWeight: FontWeight.w500),
        backgroundColor: scheme.surface,
        selectedColor: scheme.secondaryContainer,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceBright,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titleTextStyle: text.headlineSmall,
        contentTextStyle: text.bodyMedium!.copyWith(color: scheme.onSurfaceVariant),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceBright,
        modalBackgroundColor: scheme.surfaceBright,
        elevation: 0,
        modalElevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      ),
      // The mail folders: paper with a rule on its open edge, no shadow.
      drawerTheme: DrawerThemeData(
        backgroundColor: scheme.surface,
        scrimColor: scheme.scrim.withValues(alpha: 0.32),
        elevation: 0,
        shape: Border(right: rule),
      ),
      // The one floating button, New on the Mail tab, is ink like the badge.
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.inverseSurface,
        foregroundColor: scheme.onInverseSurface,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        extendedTextStyle: text.labelLarge,
        shape: r8,
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1, thickness: 1),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        titleTextStyle: text.bodyLarge,
        subtitleTextStyle: text.bodyMedium!.copyWith(color: scheme.onSurfaceVariant),
        iconColor: scheme.onSurfaceVariant,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: scheme.outline)),
        enabledBorder:
            OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: scheme.outline)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: scheme.primary, width: 2)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: r8,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: text.bodyMedium!.copyWith(color: scheme.onInverseSurface),
      ),
      // The unread count is neutral: ink on paper, not an alarm.
      badgeTheme: BadgeThemeData(
        backgroundColor: scheme.inverseSurface,
        textColor: scheme.onInverseSurface,
        textStyle: text.labelSmall,
      ),
      // The refresh bar under the app bar has no track; VOD bars set their own.
      progressIndicatorTheme: ProgressIndicatorThemeData(
          linearMinHeight: 2, color: scheme.primary, linearTrackColor: const Color(0x00000000)),
    );
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'IUT',
        theme: light,
        darkTheme: dark,
        themeMode: context.select<AppData, ThemeMode>((d) => d.prefs.themeMode),
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
  MailFolder _folder = MailFolder.inbox;
  final _timetable = GlobalKey<TimetableScreenState>();
  DateTime _lastRefresh = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _askForNotificationsOnce();
      _taps = context.read<NotificationTaps>()..addListener(_openTapped);
      _openTapped();
    });
  }

  NotificationTaps? _taps;

  /// Opens the item behind a tapped notification on top of its tab.
  void _openTapped() {
    final key = _taps?.value;
    if (key == null || !mounted) return;
    _taps!.value = null;
    final data = context.read<AppData>();
    Navigator.of(context).popUntil((r) => r.isFirst);
    switch (notificationTarget(key,
        deadlines: data.deadlines.data?.value ?? const [], attendance: data.attendance.data?.value ?? const [])) {
      case DeadlineTarget(:final deadline):
        setState(() => _tab = 2);
        showDeadlineSheet(context, deadline);
      case CourseTarget(:final course):
        setState(() => _tab = 3);
        openCourse(context, course);
      case ScheduleTarget(:final weekday):
        setState(() => _tab = 1);
        _timetable.currentState?.showWeekday(weekday);
      case TabTarget(:final tab):
        setState(() => _tab = tab);
      case null:
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _taps?.removeListener(_openTapped);
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
      3 => 'Courses',
      _ => _folder.label,
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
            if (_tab == 0)
              IconButton(
                tooltip: 'Settings',
                icon: const Icon(Icons.settings_outlined),
                onPressed: () => _push(const SettingsScreen()),
              ),
            if (_tab == 1 && data.exams(DateTime.now()) != null)
              TextButton(onPressed: () => _push(const ExamsScreen()), child: const Text('Exams')),
            if (_tab == 3)
              TextButton(onPressed: () => _push(const GradesScreen()), child: const Text('Grades')),
          ],
          bottom: _anyLoading(data) || (_tab == 4 && data.mailbox(_folder).list.loading)
              ? const PreferredSize(
                  preferredSize: Size.fromHeight(2),
                  child: LinearProgressIndicator())
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
            MailScreen(folder: _folder),
          ],
        ),
        // The Mail tab's folders, behind the menu button where Back would be.
        drawer: _tab == 4
            ? MailDrawer(
                selected: _folder,
                onSelect: (f) {
                  Navigator.of(context).pop();
                  setState(() => _folder = f);
                },
              )
            : null,
        floatingActionButton: _tab == 4
            ? FloatingActionButton.extended(
                tooltip: 'New message',
                onPressed: () => openCompose(context),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('New'),
              )
            : null,
        // The one strong line in the app: ink above the tabs (DESIGN.md 5).
        bottomNavigationBar: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(border: Border(top: BorderSide(color: Theme.of(context).colorScheme.onSurface))),
          child: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: [
            const NavigationDestination(
                icon: Icon(Icons.today_outlined), selectedIcon: Icon(Icons.today), label: 'Today'),
            const NavigationDestination(
                icon: Icon(Icons.calendar_view_day_outlined),
                selectedIcon: Icon(Icons.calendar_view_day),
                label: 'Schedule'),
            const NavigationDestination(
                icon: Icon(Icons.assignment_outlined),
                selectedIcon: Icon(Icons.assignment),
                label: 'Deadlines'),
            const NavigationDestination(
                icon: Icon(Icons.school_outlined), selectedIcon: Icon(Icons.school), label: 'Courses'),
            NavigationDestination(
                icon: Badge(isLabelVisible: unread > 0, label: Text('$unread'), child: const Icon(Icons.mail_outline)),
                selectedIcon:
                    Badge(isLabelVisible: unread > 0, label: Text('$unread'), child: const Icon(Icons.mail)),
                label: 'Mail'),
          ],
          ),
        ),
      ),
    );
  }

  static bool _anyLoading(AppData d) =>
      d.lessons.loading || d.deadlines.loading || d.attendance.loading || d.inbox.loading ||
      d.mailUnread.loading;
}
