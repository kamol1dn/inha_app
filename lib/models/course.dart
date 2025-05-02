class Course {
  String name;
  int credits;
  String grade;

  Course({required this.name, required this.credits, required this.grade});

  // Add a copy constructor for easy cloning/deep copying
  Course.copy(Course course)
      : name = course.name,
        credits = course.credits,
        grade = course.grade;

  // Add toMap and fromMap for possible future serialization
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'credits': credits,
      'grade': grade,
    };
  }

  factory Course.fromMap(Map<String, dynamic> map) {
    return Course(
      name: map['name'] as String,
      credits: map['credits'] as int,
      grade: map['grade'] as String,
    );
  }
}