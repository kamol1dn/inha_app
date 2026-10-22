import '../../models/models.dart';

/// The public EduPage timetable at iut.edupage.org. No login.
abstract class TimetableApi {
  /// All weekly lessons for [classGroup] (e.g. "ICE23-1"), minus subjects
  /// whose name contains any of [excludeSubjects] (dropped courses).
  Future<List<Lesson>> lessons(String classGroup, {Set<String> excludeSubjects = const {}});

  /// Class groups EduPage knows, for the picker in Settings.
  Future<List<String>> classGroups();
}
