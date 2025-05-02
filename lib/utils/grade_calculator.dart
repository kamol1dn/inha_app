import '../models/course.dart';

class GradeCalculator {
  // Convert letter grade to grade points
  static double getGradePoints(String grade) {
    switch (grade) {
      case 'A+': return 4.3;
      case 'A': return 4.0;
      case 'A-': return 3.7;
      case 'B+': return 3.3;
      case 'B': return 3.0;
      case 'B-': return 2.7;
      case 'C+': return 2.3;
      case 'C': return 2.0;
      case 'C-': return 1.7;
      case 'D+': return 1.3;
      case 'D': return 1.0;
      case 'D-': return 0.7;
      case 'F': return 0.0;
      default: return 0.0;
    }
  }

  // Calculate GPA based on a list of courses
  static double calculateGPA(List<Course> courses) {
    if (courses.isEmpty) return 0.0;

    double totalPoints = 0.0;
    int totalCredits = 0;

    for (var course in courses) {
      totalPoints += course.credits * getGradePoints(course.grade);
      totalCredits += course.credits;
    }

    return totalCredits > 0 ? totalPoints / totalCredits : 0.0;
  }

  // Get all available grade options
  static List<String> getGradeOptions() {
    return const [
      'A+', 'A', 'A-',
      'B+', 'B', 'B-',
      'C+', 'C', 'C-',
      'D+', 'D', 'D-',
      'F'
    ];
  }

  // Get available credit options (usually 1-6)
  static List<int> getCreditOptions() {
    return List.generate(6, (i) => i + 1);
  }
}