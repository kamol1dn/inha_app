import 'dart:async';
import '../models/class_session.dart';

class TimetableService {
  static final TimetableService _instance = TimetableService._internal();

  factory TimetableService() => _instance;

  TimetableService._internal();

  // Demo data
  final Map<String, List<ClassSession>> _demoTimetable = {
    'Monday': [
      ClassSession(time: '09:30 - 11:00', course: 'Computer Architecture', location: 'B block, room 202'),
      ClassSession(time: '11:00 - 12:30', course: 'Digital Logic Circuit', location: 'B block, room 202'),
      ClassSession(time: '12:30 - 14:00', course: 'Lunch Break', location: 'anywhere lol'),
      ClassSession(time: '14:00 - 15:30', course: 'Discrete Math', location: 'A block, Room 202'),
    ],
    'Tuesday': [
      ClassSession(time: '09:00 - 11:00', course: 'System Programming', location: 'A block, Room 202'),
      ClassSession(time: '11:00 - 12:30', course: 'Discrete Math', location: 'B block, Room 209'),
    ],
    'Wednesday': [
      ClassSession(time: '11:00 - 12:30', course: 'System Programming', location: 'A block, Room 202'),
      ClassSession(time: '12:30 - 14:00', course: 'Lunch Break', location: 'anywhere lol'),
      ClassSession(time: '14:00 - 15:30', course: 'Academic English 4', location: 'A block, Room 606'),
    ],
    'Thursday': [
      ClassSession(time: '09:30 - 11:00', course: 'History 1', location: 'B block, Room 210'),
      ClassSession(time: '11:00 - 12:30', course: 'Lunch Break', location: 'anywhere lol'),
      ClassSession(time: '12:30 - 14:00', course: 'Academic English 4', location: 'A block, Room 614'),
    ],
    'Friday': [
      ClassSession(time: '09:30 - 11:00', course: 'Digital Logic Circuit', location: 'B block, Room 209'),
      ClassSession(time: '11:00 - 12:30', course: 'Computer Architecture', location: 'B block, Room 210'),
    ],
  };

  List<String> getDays() {
    return ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'];
  }

  // For demo mode
  Map<String, List<ClassSession>> getDemoTimetable() {
    return _demoTimetable;
  }

  // For fetching from the internet
  Future<Map<String, List<ClassSession>>> fetchTimetable() async {
    // Simulate network delay
    await Future.delayed(const Duration(seconds: 2));

    try {
      // TODO: Replace this with your actual API call
      // Example:
      // final response = await http.get(Uri.parse('your_api_endpoint'));
      // if (response.statusCode == 200) {
      //   final data = jsonDecode(response.body);
      //   // Parse the data and return
      // } else {
      //   throw Exception('Failed to load timetable');
      // }

      // For now, we'll just return the demo data after a delay
      // to simulate a network request
      return _demoTimetable;
    } catch (e) {
      // If there's an error, you might want to return an empty timetable
      // or rethrow the exception to be handled by the UI
      throw Exception('Failed to fetch timetable: $e');
    }
  }
}