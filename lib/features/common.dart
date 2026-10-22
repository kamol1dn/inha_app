import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/cache.dart';
import '../core/session.dart';
import '../data/app_data.dart';
import '../ui/format/format.dart';
import '../ui/theme/status_colors.dart';
import 'settings_screen.dart';

const _statusIcons = {
  Status.ok: Icons.check_circle_outline,
  Status.warning: Icons.warning_amber_rounded,
  Status.danger: Icons.error_outline,
  Status.info: Icons.info_outline,
};

StatusColors statusColors(BuildContext c) => Theme.of(c).extension<StatusColors>()!;

/// An 18dp status icon, 8dp gap and text in the status color (DESIGN.md 3).
class StatusLine extends StatelessWidget {
  final Status status;
  final String text;
  final EdgeInsetsGeometry padding;
  const StatusLine(this.status, this.text,
      {super.key, this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 4)});

  @override
  Widget build(BuildContext context) {
    final fg = statusColors(context).of(status).fg;
    return Padding(
      padding: padding,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(_statusIcons[status], size: 18, color: fg),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: fg))),
      ]),
    );
  }
}

/// A filled tag: "1 left", "At limit" (DESIGN.md 3).
class StatusTag extends StatelessWidget {
  final Status status;
  final String text;
  const StatusTag(this.status, this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final tone = statusColors(context).of(status);
    return Container(
      constraints: const BoxConstraints(minHeight: 20),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: tone.container, borderRadius: BorderRadius.circular(4)),
      child: Text(text, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: tone.onContainer)),
    );
  }
}

/// Sentence-case section header with an optional "as of" marker when the
/// data behind it is stale or its last refresh failed (DESIGN.md 7).
class SectionHeader extends StatelessWidget {
  final String text;
  final Snapshot<Object?>? source;
  final Duration staleAfter;
  final bool first;
  const SectionHeader(this.text,
      {super.key, this.source, this.staleAfter = const Duration(hours: 3), this.first = false});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final at = source?.data?.fetchedAt;
    final stale = source != null &&
        at != null &&
        (source!.error != null || DateTime.now().difference(at) > staleAfter);
    final warn = statusColors(context).warning.fg;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, first ? 16 : 24, 16, 8),
      child: Row(children: [
        Expanded(child: Text(text, style: t.textTheme.titleSmall)),
        if (stale) ...[
          Icon(Icons.sync_problem, size: 14, color: warn),
          const SizedBox(width: 4),
          Text('as of ${updatedAt(at)}', style: t.textTheme.bodySmall?.copyWith(color: warn)),
        ],
      ]),
    );
  }
}

/// One row naming a failed service and what still works (DESIGN.md 8, Errors).
/// Renders nothing while the source is healthy.
class SourceError extends StatelessWidget {
  final Snapshot<Object?> source;
  final String serviceName;
  final VoidCallback? onRetry;
  final VoidCallback? onSignIn;
  const SourceError(this.source, this.serviceName, {super.key, this.onRetry, this.onSignIn});

  @override
  Widget build(BuildContext context) {
    final e = source.error;
    if (e == null) return const SizedBox.shrink();
    final at = source.data?.fetchedAt;
    final msg = describeError(e, serviceName);
    final needsLogin = e is LoginRequired;
    final text = at == null ? msg : '$msg Showing data from ${updatedAt(at)}.';
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Row(children: [
        Expanded(child: StatusLine(Status.danger, text)),
        if (needsLogin)
          TextButton(
            onPressed: onSignIn ??
                () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
            child: const Text('Sign in'),
          )
        else if (onRetry != null)
          TextButton(onPressed: onRetry, child: const Text('Retry')),
      ]),
    );
  }
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
