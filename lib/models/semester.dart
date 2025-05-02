import 'course.dart';

class Semester {
  String name;
  List<Course> courses;
  double? gpa;
  bool isCompleted; // New field to track if semester is completed

  Semester({
    required this.name,
    required this.courses,
    this.gpa,
    this.isCompleted = true, // Default to true for backward compatibility
  });

  // Create a copy of the semester with updated values
  static Semester copy(Semester semester) {
    return Semester(
      name: semester.name,
      courses: List.from(semester.courses.map((course) => Course.copy(course))),
      gpa: semester.gpa,
      isCompleted: semester.isCompleted,
    );
  }
}