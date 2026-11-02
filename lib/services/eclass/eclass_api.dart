import '../../models/models.dart';

/// eClass (eclass.inha.ac.kr), an old Coursemos Moodle. Its AJAX web service
/// is mostly disabled, so implementations log in through the HTML form and
/// parse pages. See docs/ENDPOINTS.md.
abstract class EclassApi {
  /// Logs in with the saved credentials if the session cookie is missing or
  /// expired. Throws [LoginRequired] if eClass rejects them.
  Future<void> ensureLoggedIn();

  /// Courses on the dashboard for the current term.
  Future<List<Course>> courses();

  /// Upcoming events of all courses: assignment/quiz deadlines and VOD watch
  /// windows. The page stops at a fixed number of events (Moodle's default is
  /// 10), so [upcomingIn] fills in what it leaves out.
  Future<List<Deadline>> upcoming();

  /// The same page for one course, which has that many to itself.
  Future<List<Deadline>> upcomingIn(Course course);

  /// Class attendance and VOD progress for one course.
  Future<CourseAttendance> attendance(Course course);

  /// Whether an assignment was handed in or a quiz attempted, from the
  /// item's own page. Null for items that have no such page.
  Future<({bool done, DateTime? at})?> submission(Deadline d);

  /// The course's marks: its grades page, or its assignment and quiz lists
  /// where that page is closed.
  Future<CourseGrades> courseGrades(Course course);

  /// The newest items of the bell menu, newest first.
  Future<List<EclassNotification>> notifications();
}
