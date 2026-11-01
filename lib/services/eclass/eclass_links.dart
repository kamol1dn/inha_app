import '../../models/models.dart';

/// Pages on eClass the app opens in the browser. The browser has its own
/// eClass sign-in; the app's session cookie is never handed over.
final Uri eclassBase = Uri.parse('https://eclass.inha.ac.kr');

/// A course's main page.
Uri eclassCourseUrl(int courseId) => eclassBase.replace(path: '/course/view.php', query: 'id=$courseId');

/// A course's grades page.
Uri eclassGradesUrl(int courseId) => eclassBase.replace(path: '/grade/report/user/index.php', query: 'id=$courseId');

/// A VOD, by [VodProgress.moduleId].
Uri eclassVodUrl(int moduleId) => eclassBase.replace(path: '/mod/vod/view.php', query: 'id=$moduleId');

/// A marked item's activity, or null for one that isn't an activity.
Uri? eclassGradeItemUrl(GradeItem i) {
  final (id, type) = (i.moduleId, i.moduleType);
  if (id == null || type == null || type.isEmpty) return null;
  return eclassBase.replace(path: '/mod/$type/view.php', query: 'id=$id');
}

/// The activity behind a calendar event (`/mod/<type>/view.php?id=<moduleId>`),
/// or null for a course-level event that has none. Cached events from before
/// the module type was stored fall back on their kind.
Uri? eclassItemUrl(Deadline d) {
  final id = d.moduleId;
  if (id == null) return null;
  final type = d.moduleType ??
      switch (d.kind) {
        DeadlineKind.assignment => 'assign',
        DeadlineKind.quiz => 'quiz',
        DeadlineKind.vod => 'vod',
        _ => null,
      };
  if (type == null) return null;
  return eclassBase.replace(path: '/mod/$type/view.php', query: 'id=$id');
}
