import 'package:flutter/material.dart';

class GPASummaryCard extends StatelessWidget {
  final double gpa;

  const GPASummaryCard({Key? key, required this.gpa}) : super(key: key);

  String _getGradeDescription(double gpa) {
    if (gpa >= 4.0) return 'Excellent';
    if (gpa >= 3.5) return 'Very Good';
    if (gpa >= 3.0) return 'Good';
    if (gpa >= 2.0) return 'Satisfactory';
    return 'Needs Improvement';
  }

  Color _getGradeColor(double gpa) {
    if (gpa >= 4.0) return Colors.green.shade800;
    if (gpa >= 3.5) return Colors.green;
    if (gpa >= 3.0) return Colors.blue;
    if (gpa >= 2.0) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            const Text(
              'Cumulative GPA',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              gpa.toStringAsFixed(2),
              style: TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.bold,
                color: _getGradeColor(gpa),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _getGradeDescription(gpa),
              style: TextStyle(
                fontSize: 16,
                color: _getGradeColor(gpa),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}