import 'package:flutter/material.dart';
import '../../../models/course.dart';
import '../../../utils/grade_calculator.dart';
import '../../../constants/app_styles.dart';

class CourseListItem extends StatelessWidget {
  final Course course;
  final void Function(Course) onUpdate;
  final VoidCallback onDelete;

  const CourseListItem({
    Key? key,
    required this.course,
    required this.onUpdate,
    required this.onDelete,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 0),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Row(
          children: [
            // Course Name Field
            Expanded(
              flex: 3,
              child: TextFormField(
                initialValue: course.name,
                decoration: AppStyles.textFieldDecoration(hintText: 'Course name'),
                onChanged: (value) {
                  final updatedCourse = Course.copy(course);
                  updatedCourse.name = value;
                  onUpdate(updatedCourse);
                },
              ),
            ),
            const SizedBox(width: 8),

            // Credits Dropdown
            Expanded(
              flex: 1,
              child: DropdownButtonFormField<int>(
                value: course.credits,
                decoration: AppStyles.textFieldDecoration(),
                items: GradeCalculator.getCreditOptions()
                    .map((credit) => DropdownMenuItem(
                  value: credit,
                  child: Text('$credit'),
                ))
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    final updatedCourse = Course.copy(course);
                    updatedCourse.credits = value;
                    onUpdate(updatedCourse);
                  }
                },
              ),
            ),
            const SizedBox(width: 8),

            // Grade Dropdown
            Expanded(
              flex: 1,
              child: DropdownButtonFormField<String>(
                isExpanded: true,
                value: course.grade,
                decoration: AppStyles.textFieldDecoration(),
                items: GradeCalculator.getGradeOptions()
                    .map((grade) => DropdownMenuItem(
                  value: grade.name,
                  child: Text(grade.name),
                ))//
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    final updatedCourse = Course.copy(course);
                    updatedCourse.grade = value;
                    onUpdate(updatedCourse);
                  }
                },
              ),
            ),

            // Delete Button
            IconButton(
              icon: const Icon(Icons.delete, color: AppStyles.errorColor),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}