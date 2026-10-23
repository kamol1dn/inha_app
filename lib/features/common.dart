import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/cache.dart';
import '../core/session.dart';
import '../data/app_data.dart';
import '../data/services.dart';
import '../ui/format/format.dart';
import '../ui/theme/status_colors.dart';
import 'settings_screen.dart';

const statusIcons = {
  Status.ok: Icons.check_circle_outline,
  Status.warning: Icons.warning_amber_rounded,
  Status.danger: Icons.error_outline,
  Status.info: Icons.info_outline,
};

StatusColors statusColors(BuildContext c) => Theme.of(c).extension<StatusColors>()!;

/// The text gutter (DESIGN.md 5).
const gutter = 20.0;

/// A 16dp status icon, a 6dp gap and text, both in the status color (DESIGN.md 3).
class StatusLine extends StatelessWidget {
  final Status status;
  final String text;
  final EdgeInsetsGeometry padding;
  final int? maxLines;
  const StatusLine(this.status, this.text,
      {super.key, this.padding = const EdgeInsets.symmetric(horizontal: gutter, vertical: 4), this.maxLines});

  @override
  Widget build(BuildContext context) {
    final fg = statusColors(context).of(status).fg;
    final style = Theme.of(context).textTheme.bodyMedium!.copyWith(color: fg);
    final scaler = MediaQuery.textScalerOf(context);
    return Padding(
      padding: padding,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Centred on the first line of text, whatever the text scale.
        SizedBox(
          height: scaler.scale(style.fontSize!) * style.height!,
          child: Icon(statusIcons[status], size: 16, color: fg),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text,
              style: style, maxLines: maxLines, overflow: maxLines == null ? null : TextOverflow.ellipsis),
        ),
      ]),
    );
  }
}

/// A thin rule between rows or above a section, inset by the gutter.
class Rule extends StatelessWidget {
  final double inset;
  const Rule({super.key, this.inset = gutter});
  @override
  Widget build(BuildContext context) => Divider(height: 1, indent: inset, endIndent: inset);
}

/// Whether the source's data is old or its last refresh failed.
bool isStale(Snapshot<Object?> source, Duration staleAfter, {DateTime? now}) {
  final at = source.data?.fetchedAt;
  return at != null && (source.error != null || (now ?? DateTime.now()).difference(at) > staleAfter);
}

/// A ruled section with a sentence-case Fraunces header and, when the data
/// behind it is stale or its refresh failed, an "as of" marker (DESIGN.md 7).
class SectionHeader extends StatelessWidget {
  final String text;
  final Snapshot<Object?>? source;
  final Duration staleAfter;
  final bool first;
  final Status? status; // only Overdue's danger header
  const SectionHeader(this.text,
      {super.key, this.source, this.staleAfter = const Duration(hours: 3), this.first = false, this.status});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final s = source;
    final stale = s != null && isStale(s, staleAfter);
    final fg = status == null ? null : statusColors(context).of(status!).fg;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (!first) ...[const SizedBox(height: 16), const Rule()],
      Padding(
        padding: const EdgeInsets.fromLTRB(gutter, 16, gutter, 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
          if (status != null) ...[
            Icon(statusIcons[status], size: 18, color: fg),
            const SizedBox(width: 6),
          ],
          Expanded(child: Text(text, style: t.textTheme.titleMedium?.copyWith(color: fg))),
          if (stale) StaleMarker(s.data!.fetchedAt),
        ]),
      ),
    ]);
  }
}

/// `sync_problem` plus "as of Tue 18:04", in warning colour.
class StaleMarker extends StatelessWidget {
  final DateTime at;
  final String? what;
  const StaleMarker(this.at, {super.key, this.what});

  @override
  Widget build(BuildContext context) {
    final warn = statusColors(context).warning.fg;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.sync_problem, size: 14, color: warn),
      const SizedBox(width: 4),
      Text('${what == null ? 'as of' : '$what as of'} ${updatedAt(at)}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: warn)),
    ]);
  }
}

/// The app counts as offline when EduPage and eClass, two different hosts,
/// both failed on the network on their last refresh (DESIGN.md 8, Offline).
bool isOffline(AppData d) => isNetworkError(d.lessons.error) && isNetworkError(d.deadlines.error);

/// The age of what is on screen while offline: the oldest of the main sources.
DateTime? oldestData(AppData d) =>
    ([d.lessons, d.deadlines, d.attendance].map((s) => s.data?.fetchedAt).whereType<DateTime>().toList()..sort())
        .firstOrNull;

/// One row at the top of a tab while offline. Renders nothing otherwise.
class OfflineRow extends StatelessWidget {
  const OfflineRow({super.key});

  @override
  Widget build(BuildContext context) {
    final data = context.watch<AppData>();
    if (!isOffline(data)) return const SizedBox.shrink();
    final t = Theme.of(context);
    final at = oldestData(data);
    return Container(
      color: t.colorScheme.surfaceContainerHigh,
      padding: const EdgeInsets.fromLTRB(gutter, 4, 8, 4),
      constraints: const BoxConstraints(minHeight: 48),
      child: Row(children: [
        Icon(Icons.cloud_off_outlined, size: 18, color: t.colorScheme.onSurfaceVariant),
        const SizedBox(width: 12),
        Expanded(
          child: Text(at == null ? 'Offline.' : 'Offline. Showing data from ${updatedAt(at)}.',
              style: t.textTheme.bodyMedium),
        ),
        TextButton(onPressed: data.refreshAll, child: const Text('Retry')),
      ]),
    );
  }
}

/// One row naming a failed service and what still works (DESIGN.md 8, Errors).
/// Renders nothing while the source is healthy, and nothing for a network
/// failure while the offline row already says so.
class SourceError extends StatelessWidget {
  final Snapshot<Object?> source;
  final String serviceName;
  final VoidCallback? onRetry;
  const SourceError(this.source, this.serviceName, {super.key, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final e = source.error;
    if (e == null) return const SizedBox.shrink();
    if (isNetworkError(e) && isOffline(context.watch<AppData>())) return const SizedBox.shrink();
    final at = source.data?.fetchedAt;
    final msg = describeError(e, serviceName);
    final needsLogin = e is LoginRequired;
    final text = at == null ? msg : '$msg Showing data from ${updatedAt(at)}.';
    return Padding(
      padding: const EdgeInsets.only(right: 8, top: 4, bottom: 4),
      child: Row(children: [
        Expanded(child: StatusLine(Status.danger, text)),
        if (needsLogin)
          TextButton(
            onPressed: () =>
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
            child: const Text('Sign in'),
          )
        else if (onRetry != null)
          TextButton(onPressed: onRetry, child: const Text('Retry')),
      ]),
    );
  }
}

/// A plain sentence for an empty or signed-out state, with at most one
/// action (DESIGN.md 8, Empty states).
class EmptyNote extends StatelessWidget {
  final String text;
  final String? action;
  final VoidCallback? onAction;
  const EmptyNote(this.text, {super.key, this.action, this.onAction});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(gutter, 16, gutter, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(text, style: Theme.of(context).textTheme.bodyLarge),
          if (action != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: TextButton(
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 0)),
                onPressed: onAction,
                child: Text(action!),
              ),
            ),
        ]),
      );
}

/// Opens Settings, where logins are typed.
void openSettings(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));

/// A static skeleton block (DESIGN.md 8, Loading): no shimmer.
class SkeletonBlock extends StatelessWidget {
  final double width;
  final double height;
  const SkeletonBlock(this.width, {super.key, this.height = 14});

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(4),
        ),
      );
}

/// First run with no cache: rows shaped like the real ones, a time column
/// on the left when [timeColumn] is set.
class SkeletonRows extends StatelessWidget {
  final int count;
  final bool timeColumn;
  const SkeletonRows({super.key, this.count = 4, this.timeColumn = true});

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Loading',
        child: Column(children: [
          for (var i = 0; i < count; i++)
            Padding(
              padding: const EdgeInsets.fromLTRB(gutter, 14, gutter, 14),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (timeColumn) ...[const SkeletonBlock(40), const SizedBox(width: 32)],
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SkeletonBlock(i.isEven ? 180 : 140, height: 16),
                    const SizedBox(height: 8),
                    SkeletonBlock(i.isEven ? 120 : 160),
                  ]),
                ),
              ]),
            ),
        ]),
      );
}

/// Opens [uri] in the browser (or the mail app for `mailto:`). Says so in a
/// snack bar when nothing on the phone can open it.
Future<void> openUrl(BuildContext context, Uri uri) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  var opened = false;
  try {
    opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    opened = false;
  }
  if (!opened) {
    final what = uri.host.isNotEmpty ? uri.host : uri.path;
    messenger?.showSnackBar(SnackBar(content: Text("Couldn't open $what.")));
  }
}

/// Minutes since midnight for "09:30".
int minutesOf(String hhmm) {
  final p = hhmm.split(':');
  return int.parse(p[0]) * 60 + int.parse(p[1]);
}
