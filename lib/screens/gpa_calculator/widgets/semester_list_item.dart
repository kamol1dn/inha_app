import 'package:flutter/material.dart';
import '../../../models/semester.dart';
import '../../../utils/grade_calculator.dart';
import 'course_list_item.dart';
import '../../../models/course.dart';

class SemesterListItem extends StatelessWidget {
  final Semester semester;
  final Function(Semester) onUpdate;
  final Function(int) onAddCourse;
  final Function(int, int) onRemoveCourse;
  final int semesterIndex;

  const SemesterListItem({
    Key? key,
    required this.semester,
    required this.onUpdate,
    required this.onAddCourse,
    required this.onRemoveCourse,
    required this.semesterIndex,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Semester header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  semester.name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade100,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'GPA: ${semester.gpa?.toStringAsFixed(2) ?? '0.00'}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Course list header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
              child: Row(
                children: const [
                  Expanded(
                    flex: 3,
                    child: Text('Course', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  Expanded(
                    flex: 1,
                    child: Text('Credits', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  Expanded(
                    flex: 1,
                    child: Text('Grade', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  SizedBox(width: 48), // Space for delete button
                ],
              ),
            ),

            // List of courses
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: semester.courses.length,
              itemBuilder: (context, index) {
                return CourseListItem(
                  course: semester.courses[index],
                  onUpdate: (updatedCourse) {
                    final updatedSemester = Semester.copy(semester);
                    updatedSemester.courses[index] = updatedCourse;
                    updatedSemester.gpa = GradeCalculator.calculateGPA(updatedSemester.courses);
                    onUpdate(updatedSemester);
                  },
                  onDelete: () => onRemoveCourse(semesterIndex, index),
                );
              },
            ),

            const SizedBox(height: 8),

            // Add course button
            TextButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Add Course'),
              onPressed: () => onAddCourse(semesterIndex),
            ),
          ],
        ),
      ),
    );
  }
}