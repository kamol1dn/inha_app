import '../models/models.dart';
import 'eclass/eclass_api.dart';
import 'ins/ins_api.dart';
import 'mail/mail_api.dart';

/// Stand-ins for services that aren't wired up yet, so the app runs while
/// they're being built. Delete each one as its real client lands.
class NotConnectedYet implements Exception {
  final Service service;
  NotConnectedYet(this.service);
  @override
  String toString() => '${service.label} is not connected yet';
}

class PendingEclass implements EclassApi {
  @override
  Future<void> ensureLoggedIn() => throw NotConnectedYet(Service.eclass);
  @override
  Future<List<Course>> courses() => throw NotConnectedYet(Service.eclass);
  @override
  Future<List<Deadline>> upcoming() => throw NotConnectedYet(Service.eclass);
  @override
  Future<CourseAttendance> attendance(Course course) => throw NotConnectedYet(Service.eclass);
}

class PendingIns implements InsApi {
  @override
  Future<void> ensureLoggedIn() => throw NotConnectedYet(Service.ins);
  @override
  Future<GradeReport> grades() => throw NotConnectedYet(Service.ins);
}

class PendingMail implements MailApi {
  @override
  Future<List<MailHeader>> inbox({int limit = 30, int offset = 0}) =>
      throw NotConnectedYet(Service.mail);
  @override
  Future<String> body(String id) => throw NotConnectedYet(Service.mail);
  @override
  Future<int> unreadCount() => throw NotConnectedYet(Service.mail);
}
