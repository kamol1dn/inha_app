import 'package:flutter/material.dart';
import '../../../models/course.dart';
import '../../../utils/grade_calculator.dart';
import '../../../constants/app_styles.dart';

class CourseListItem extends StatelessWidget {
  final Course course;
  final void Function(Course) onUpdate;
  final VoidCallback onDelete;

  const CourseListItem({
    super.key,
    required this.course,
    required this.onUpdate,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    // Use a more lightweight approach
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 0),
      padding: const EdgeInsets.all(8.0),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          // Course Name Field - Use a simpler TextField for better performance
          Expanded(
            flex: 11,
            child: TextField(
              controller: TextEditingController(text: course.name)..selection = TextSelection.collapsed(offset: course.name.length),
              decoration: InputDecoration(
                hintText: 'Course name',
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                border: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
              ),
              onChanged: (value) {
                final updatedCourse = Course.copy(course);
                updatedCourse.name = value;
                onUpdate(updatedCourse);
              },
            ),
          ),
          const SizedBox(width: 8),

          // Credits Dropdown - Simplified
          Expanded(
            flex: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(4),
              ),
              child: DropdownButton<int>(
                value: course.credits,
                underline: Container(), // Remove underline
                isExpanded: true,
                icon: const Icon(Icons.arrow_drop_down, size: 18),
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
          ),
          const SizedBox(width: 8),

          // Grade Dropdown - Simplified
          Expanded(
            flex: 5,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(4),
              ),
              child: DropdownButton<String>(
                underline: Container(), // Remove underline
                isExpanded: true,
                value: course.grade,
                icon: const Icon(Icons.arrow_drop_down, size: 18),
                items: GradeCalculator.getGradeOptions()
                    .map((grade) => DropdownMenuItem(
                  value: grade.name,
                  child: Text(grade.name),
                ))
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
          ),

          // Delete Button - Simplified for better performance
          IconButton(
            constraints: const BoxConstraints(maxWidth: 32),
            padding: EdgeInsets.zero,
            icon: const Icon(Icons.delete, color: AppStyles.errorColor, size: 20),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}