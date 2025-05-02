import 'package:flutter/material.dart';
import '../../../models/class_session.dart';

class ClassSessionCard extends StatelessWidget {
  final ClassSession session;

  const ClassSessionCard({
    Key? key,
    required this.session,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.access_time, size: 16, color: Colors.blue),
                const SizedBox(width: 8),
                Text(
                  session.time,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              session.course,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.location_on, size: 16, color: Colors.red),
                const SizedBox(width: 8),
                Text(session.location),
              ],
            ),
          ],
        ),
      ),
    );
  }
}