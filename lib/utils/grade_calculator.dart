import '../models/course.dart';
import '../models/semester.dart';

class GradeCalculator {
  // Define grade options with point values (similar to marksList in JavaScript)
  static List<GradeOption> getGradeOptions() {
    return [
      GradeOption(name: 'A+', value: 4.5),
      GradeOption(name: 'A', value: 4.0),
      GradeOption(name: 'A-', value: 3.7),
      GradeOption(name: 'B+', value: 3.5),
      GradeOption(name: 'B', value: 3.0),
      GradeOption(name: 'B-', value: 2.7),
      GradeOption(name: 'C+', value: 2.5),
      GradeOption(name: 'C', value: 2.0),
      GradeOption(name: 'C-', value: 1.7),
      GradeOption(name: 'D+', value: 1.5),
      GradeOption(name: 'D', value: 1.0),
      GradeOption(name: 'F', value: 0.0),
    ];
  }

  // Get credit hour options
  static List<int> getCreditOptions() {
    return [1, 2, 3, 4, 5, 6];
  }

  // Get numeric value for a letter grade
  static double getGradeValue(String grade) {
    final gradeOption = getGradeOptions().firstWhere(
          (option) => option.name == grade,
      orElse: () => GradeOption(name: 'F', value: 0.0),
    );
    return gradeOption.value;
  }

  // Calculate GPA for a list of courses
  static double calculateGPA(List<Course> courses) {
    if (courses.isEmpty) return 0.0;

    double totalPoints = 0.0;
    int totalCredits = 0;

    for (var course in courses) {
      double gradeValue = getGradeValue(course.grade);
      totalPoints += course.credits * gradeValue;
      totalCredits += course.credits;
    }

    return totalCredits > 0 ? totalPoints / totalCredits : 0.0;
  }

  // Calculate GPA for all semesters
  static double calculateOverallGPA(List<Semester> semesters) {
    if (semesters.isEmpty) return 0.0;

    double totalPoints = 0.0;
    int totalCredits = 0;

    for (var semester in semesters) {
      for (var course in semester.courses) {
        double gradeValue = getGradeValue(course.grade);
        totalPoints += course.credits * gradeValue;
        totalCredits += course.credits;
      }
    }

    return totalCredits > 0 ? totalPoints / totalCredits : 0.0;
  }
}

class GradeOption {
  final String name;
  final double value;

  GradeOption({required this.name, required this.value});
}