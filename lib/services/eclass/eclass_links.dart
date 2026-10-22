import '../../models/models.dart';

/// Pages on eClass the app opens in the browser. The browser has its own
/// eClass sign-in; the app's session cookie is never handed over.
final Uri eclassBase = Uri.parse('https://eclass.inha.ac.kr');

/// A course's main page.
Uri eclassCourseUrl(int courseId) => eclassBase.replace(path: '/course/view.php', query: 'id=$courseId');

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
