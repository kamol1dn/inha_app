import '../models/course.dart';

class GPAService {
  // Sample data
  static List<Course> getSampleCourses() {
    return [
      Course(name: 'Calculus I', credits: 3, grade: 'A'),
      Course(name: 'Introduction to Computer Science', credits: 4, grade: 'A-'),
      Course(name: 'Physics 101', credits: 4, grade: 'B+'),
      Course(name: 'Academic English', credits: 3, grade: 'B'),
      Course(name: 'History of Art', credits: 2, grade: 'A'),
    ];
  }

  // In a real app, these functions would interact with storage or a backend

  // Save courses (placeholder for future implementation)
  static Future<bool> saveCourses(List<Course> courses) async {
    // This would save to local storage or a backend in a real app
    return Future.value(true);
  }

  // Load courses (placeholder for future implementation)
  static Future<List<Course>> loadCourses() async {
    // This would load from local storage or a backend in a real app
    return Future.value(getSampleCourses());
  }
}