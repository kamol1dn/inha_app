class ClassSession {
  final String time;
  final String course;
  final String location;
  final String? teacher;
  final String? roomCode;
  final String? classGroup;

  ClassSession({
    required this.time,
    required this.course,
    required this.location,
    this.teacher,
    this.roomCode,
    this.classGroup,
  });

  factory ClassSession.fromEdupageData(Map<String, dynamic> data) {
    // This will need to be implemented based on the actual structure of your Edupage API response
    // For now, this is a placeholder
    return ClassSession(
      time: data['time'] ?? '',
      course: data['subject'] ?? '',
      location: data['room'] ?? '',
      teacher: data['teacher'],
      roomCode: data['roomCode'],
      classGroup: data['classGroup'],
    );
  }
}