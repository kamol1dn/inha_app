class ClassSession {
  final String time;
  final String course;
  final String location;

  const ClassSession({
    required this.time,
    required this.course,
    required this.location,
  });

  // Add toMap and fromMap for possible future serialization
  Map<String, dynamic> toMap() {
    return {
      'time': time,
      'course': course,
      'location': location,
    };
  }

  factory ClassSession.fromMap(Map<String, dynamic> map) {
    return ClassSession(
      time: map['time'] as String,
      course: map['course'] as String,
      location: map['location'] as String,
    );
  }
}