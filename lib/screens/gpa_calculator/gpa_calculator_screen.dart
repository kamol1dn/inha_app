import 'package:flutter/material.dart';

import '../../models/course.dart';
import '../../services/gpa_service.dart';
import '../../utils/grade_calculator.dart';
import '../../constants/app_styles.dart';
import 'widgets/gpa_summary_card.dart';
import 'widgets/course_list_item.dart';

class GPACalculatorScreen extends StatefulWidget {
  const GPACalculatorScreen({Key? key}) : super(key: key);

  @override
  _GPACalculatorScreenState createState() => _GPACalculatorScreenState();
}

class _GPACalculatorScreenState extends State<GPACalculatorScreen> {
  List<Course> courses = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCourses();
  }

  Future<void> _loadCourses() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final loadedCourses = await GPAService.loadCourses();
      setState(() {
        courses = loadedCourses;
      });
    } catch (e) {
      debugPrint('Error loading courses: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _saveCourses() async {
    try {
      await GPAService.saveCourses(courses);
    } catch (e) {
      debugPrint('Error saving courses: $e');
    }
  }

  void _addCourse() {
    setState(() {
      courses.add(Course(name: '', credits: 3, grade: 'A'));
    });
    _saveCourses();
  }

  void _removeCourse(int index) {
    setState(() {
      courses.removeAt(index);
    });
    _saveCourses();
  }

  void _updateCourse(int index, Course updatedCourse) {
    setState(() {
      courses[index] = updatedCourse;
    });
    _saveCourses();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Padding(
      padding: AppStyles.contentPadding,
      child: Column(
        children: [
          GPASummaryCard(gpa: GradeCalculator.calculateGPA(courses)),
          const SizedBox(height: 16),

          // Fixed header row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              children: [
                const Expanded(
                  flex: 3,
                  child: Text('Course', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                const Expanded(
                  flex: 1,
                  child: Text('Credits', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                const Expanded(
                  flex: 1,
                  child: Text('Grade', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                Expanded(
                  flex: 0, // Important fix: Use flex 0 to prevent overflow
                  child: Container(width: 48), // Space for delete button
                ),
              ],
            ),
          ),

          Expanded(
            child: courses.isEmpty
                ? const Center(child: Text('No courses added yet'))
                : ListView.builder(
              itemCount: courses.length,
              itemBuilder: (context, index) {
                return CourseListItem(
                  course: courses[index],
                  onUpdate: (course) => _updateCourse(index, course),
                  onDelete: () => _removeCourse(index),
                );
              },
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: ElevatedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Add Course'),
              onPressed: _addCourse,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
            ),
          ),
        ],
      ),
    );
  }
}