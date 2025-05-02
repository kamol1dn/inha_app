class Course {
  String name;
  int credits;
  String grade;
  bool required;

  Course({
    required this.name,
    required this.credits,
    required this.grade,
    this.required = false,
  });

  // Create a copy of the course with updated values
  static Course copy(Course course) {
    return Course(
      name: course.name,
      credits: course.credits,
      grade: course.grade,
      required: course.required,
    );
  }
}