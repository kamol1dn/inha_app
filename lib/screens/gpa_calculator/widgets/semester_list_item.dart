import 'package:flutter/material.dart';
import '../../../models/semester.dart';
import '../../../utils/grade_calculator.dart';
import 'course_list_item.dart';
import '../../../models/course.dart';

class SemesterListItem extends StatefulWidget {
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
  State<SemesterListItem> createState() => _SemesterListItemState();
}

class _SemesterListItemState extends State<SemesterListItem> {
  // Add expansion state to optimize rendering
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Semester header with completion toggle
            Row(
              children: [
                // Expand/collapse icon
                IconButton(
                  icon: Icon(_isExpanded ? Icons.expand_less : Icons.expand_more),
                  onPressed: () {
                    setState(() {
                      _isExpanded = !_isExpanded;
                    });
                  },
                ),

                // Semester name
                Expanded(
                  child: Text(
                    widget.semester.name,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

                // Completion toggle (Switch)
                Row(
                  children: [
                    Text(
                      'Completed',
                      style: TextStyle(
                        color: widget.semester.isCompleted
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Switch(
                      value: widget.semester.isCompleted,
                      onChanged: (value) {
                        final updatedSemester = Semester.copy(widget.semester);
                        updatedSemester.isCompleted = value;
                        widget.onUpdate(updatedSemester);
                      },
                    ),
                  ],
                ),
              ],
            ),

            // Course count and GPA row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Course count
                Text(
                  '${widget.semester.courses.length} courses',
                  style: const TextStyle(color: Colors.grey),
                ),

                // GPA display
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: widget.semester.isCompleted
                        ? Colors.blue.shade100
                        : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'GPA: ${widget.semester.gpa?.toStringAsFixed(2) ?? '0.00'}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: widget.semester.isCompleted ? Colors.black87 : Colors.grey,
                    ),
                  ),
                ),
              ],
            ),

            // Only show course details if expanded
            if (_isExpanded) ...[
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

              // List of courses - using ListView.builder for optimization
              // We'll limit the render cost with explicit height
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: widget.semester.courses.length * 70.0, // Approximate height per course
                ),
                child: ListView.builder(
                  // Key performance improvements:
                  // 1. Remove shrinkWrap: true
                  // 2. Use primary: false instead of NeverScrollableScrollPhysics
                  primary: false,
                  itemCount: widget.semester.courses.length,
                  itemBuilder: (context, index) {
                    return CourseListItem(
                      course: widget.semester.courses[index],
                      onUpdate: (updatedCourse) {
                        final updatedSemester = Semester.copy(widget.semester);
                        updatedSemester.courses[index] = updatedCourse;
                        updatedSemester.gpa = GradeCalculator.calculateGPA(updatedSemester.courses);
                        widget.onUpdate(updatedSemester);
                      },
                      onDelete: () => widget.onRemoveCourse(widget.semesterIndex, index),
                    );
                  },
                ),
              ),

              const SizedBox(height: 8),

              // Add course button
              TextButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Add Course'),
                onPressed: () => widget.onAddCourse(widget.semesterIndex),
              ),
            ],
          ],
        ),
      ),
    );
  }
}