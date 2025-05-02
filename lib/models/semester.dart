import 'course.dart';

class Semester {
  String name;
  List<Course> courses;
  double? gpa;
 // bool isPassed = false;

  Semester({
    required this.name,
    required this.courses,
    this.gpa,
  //  this.isPassed,
  });

  // Create a copy of the semester with updated values
  static Semester copy(Semester semester) {
    return Semester(
      name: semester.name,
      courses: List.from(semester.courses.map((course) => Course.copy(course))),
      gpa: semester.gpa,
   //   isPassed: semester.isPassed,
    );
  }
}