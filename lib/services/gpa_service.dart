import '../models/course.dart';
import '../models/semester.dart';

class GPAService {
  // Get sample semesters with courses
  static List<Semester> getSampleSemesters() {
    return [
      Semester(
        name: 'Freshmen Fall (1st)',
        isCompleted: true, // Completed semester
        courses: [
          Course(name: 'OOP 1', credits: 3, grade: 'A', required: true),
          Course(name: 'Calculus 1', credits: 3, grade: 'A', required: true),
          Course(name: 'Physics 1', credits: 3, grade: 'A', required: true),
          Course(name: 'Intro To IT', credits: 3, grade: 'A'),
          Course(name: 'Academic English 1', credits: 2, grade: 'A', required: true),
          Course(name: 'Academic Reading', credits: 2, grade: 'A', required: true),
          Course(name: 'Physics Experiment 1', credits: 1, grade: 'A', required: true),
        ],
      ),
      Semester(
        name: 'Freshmen Spring (2nd)',
        isCompleted: true, // Completed semester
        courses: [
          Course(name: 'OOP 2', credits: 3, grade: 'A', required: true),
          Course(name: 'Calculus 2', credits: 3, grade: 'A', required: true),
          Course(name: 'Creative Engineering', credits: 3, grade: 'A'),
          Course(name: 'Physics 2', credits: 3, grade: 'A', required: true),
          Course(name: 'Academic English 2', credits: 2, grade: 'A', required: true),
          Course(name: 'Academic Writing', credits: 2, grade: 'A', required: true),
          Course(name: 'Physics Experiment 2', credits: 1, grade: 'A', required: true),
        ],
      ),
      Semester(
        name: 'Sophomore Fall (1st)',
        isCompleted: true, // Completed semester
        courses: [
          Course(name: 'Linear Algebra', credits: 3, grade: 'A', required: true),
          Course(name: 'Engineering Mathematics', credits: 3, grade: 'A', required: true),
          Course(name: 'Application Programing in Java', credits: 3, grade: 'A', required: true),
          Course(name: 'Circuit and Lab', credits: 3, grade: 'A'),
          Course(name: 'Data Structure', credits: 3, grade: 'A'),
          Course(name: 'Academic English 3', credits: 2, grade: 'A'),
          Course(name: 'Basic korean 1', credits: 2, grade: 'A'),
        ],
      ),
      Semester(
        name: 'Sophomore Spring (2nd)',
        isCompleted: true, // Completed semester
        courses: [
          Course(name: 'Digital Logic and Circuit', credits: 3, grade: 'A'),
          Course(name: 'Discrete Mathematics', credits: 3, grade: 'A', required: true),
          Course(name: 'History of Uzbekistan 1', credits: 1, grade: 'A', required: true),
          Course(name: 'System Programming', credits: 3, grade: 'A'),
          Course(name: 'Computer Architecture', credits: 3, grade: 'A'),
          Course(name: 'Academic English 4', credits: 2, grade: 'A'),
          Course(name: 'Basic Korean 2', credits: 2, grade: 'A'),
        ],
      ),
      Semester(
        name: 'Junior Fall (1st)',
        isCompleted: true, // Completed semester
        courses: [
          Course(name: 'System Analysis', credits: 3, grade: 'A'),
          Course(name: 'Introduction to Economics', credits: 3, grade: 'A', required: true),
          Course(name: 'Operating System', credits: 3, grade: 'A'),
          Course(name: 'Database', credits: 3, grade: 'A'),
          Course(name: 'Computer Algorithm', credits: 3, grade: 'A'),
          Course(name: 'History of Uzbekistan 2', credits: 1, grade: 'A', required: true),
          Course(name: 'Engineering Communications', credits: 3, grade: 'A'),
        ],
      ),
      Semester(
        name: 'Junior Spring (2nd)',
        isCompleted: true, // Completed semester
        courses: [
          Course(name: 'Signals and Systems', credits: 3, grade: 'A', required: true),
          Course(name: 'Unix Programming', credits: 3, grade: 'A'),
          Course(name: 'Introduction to Business Administration', credits: 3, grade: 'A', required: true),
          Course(name: 'Computer Networks', credits: 3, grade: 'A'),
          Course(name: 'Database Application and Design', credits: 3, grade: 'A'),
          Course(name: 'Probability and Statistics', credits: 3, grade: 'A'),
        ],
      ),
      Semester(
        name: 'Senior Fall (1st)',
        isCompleted: true, // Completed semester
        courses: [
          Course(name: 'Software Engineering', credits: 3, grade: 'A'),
          Course(name: 'Embedded Software & Design', credits: 3, grade: 'A'),
          Course(name: 'Artificial Intelligence', credits: 3, grade: 'A'),
          Course(name: 'Multimedia Computing', credits: 3, grade: 'A'),
          Course(name: 'Big Data analytics', credits: 3, grade: 'A'),
          Course(name: 'Distinguished Lecture in Social Science and Art', credits: 2, grade: 'A'),
        ],
      ),
      Semester(
        name: 'Senior Spring (2nd)',
        isCompleted: false, // Example of a future semester not yet completed
        courses: [
          Course(name: 'Capstone Design', credits: 3, grade: 'A', required: true),
          Course(name: 'Computer Security', credits: 3, grade: 'A'),
          Course(name: 'Multimedia Application', credits: 3, grade: 'A'),
          Course(name: 'Mobile Programming', credits: 3, grade: 'A'),
          Course(name: 'Internet of Things', credits: 3, grade: 'A'),
          Course(name: 'Engineering Ethics', credits: 2, grade: 'A'),
        ],
      ),
    ];
  }

  // Save semesters (placeholder for future implementation)
  static Future<bool> saveSemesters(List<Semester> semesters) async {
    // This would save to local storage or a backend in a real app
    return Future.value(true);
  }

  // Load semesters (placeholder for future implementation)
  static Future<List<Semester>> loadSemesters() async {
    // This would load from local storage or a backend in a real app
    return Future.value(getSampleSemesters());
  }
}