import 'package:flutter/foundation.dart';

/// One thing a refresh is waiting on.
class SyncStep {
  final String service;
  final String what;
  const SyncStep(this.service, this.what);
}

/// What the refreshes are doing right now, for the strip under the app bar.
/// Apart from [AppData] so that a step going by rebuilds the strip, not every
/// screen.
class SyncProgress extends ChangeNotifier {
  final _running = <SyncStep>[];
  int _open = 0;
  int _done = 0;
  int _total = 0;

  bool get active => _open > 0;
  int get done => _done;
  int get total => _total;

  /// "eClass: marks for Artificial Intelligence": what has been waited on the
  /// longest. Null in the moment between two steps.
  String? get current => _running.isEmpty ? null : '${_running.first.service}: ${_running.first.what}';

  /// The other services still going, for when several refresh at once.
  List<String> get others => [
        for (final s in {for (final r in _running) r.service})
          if (s != _running.first.service) s,
      ];

  /// Keeps one sync going across [work]'s steps, so the count doesn't start
  /// over in the moment between them.
  Future<T> span<T>(Future<T> Function() work) async {
    _open++;
    try {
      return await work();
    } finally {
      _close();
    }
  }

  /// Shows "[service]: [what]" until [work] ends, however it ends.
  Future<T> step<T>(String service, String what, Future<T> Function() work) async {
    final step = SyncStep(service, what);
    _open++;
    _total++;
    _running.add(step);
    notifyListeners();
    try {
      return await work();
    } finally {
      _running.remove(step);
      _done++;
      _close();
    }
  }

  void _close() {
    if (--_open == 0) _done = _total = 0;
    notifyListeners();
  }
}
