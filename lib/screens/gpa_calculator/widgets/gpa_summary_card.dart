import 'package:flutter/material.dart';
import '../../../constants/app_styles.dart';

class GPASummaryCard extends StatelessWidget {
  final double gpa;

  const GPASummaryCard({
    Key? key,
    required this.gpa,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: AppStyles.cardPadding,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Current GPA:',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text(
              gpa.toStringAsFixed(2),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppStyles.accentColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}