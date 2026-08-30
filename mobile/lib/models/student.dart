class Student {
  final String studentId;
  final String name;
  final String major;
  final int year;
  final double? gpa;
  final List<String> courses;

  Student({
    required this.studentId,
    required this.name,
    required this.major,
    required this.year,
    required this.gpa,
    required this.courses,
  });

  factory Student.fromJson(Map<String, dynamic> json) {
    return Student(
      studentId: json['student_id'] as String,
      name: json['name'] as String,
      major: json['major'] as String,
      year: (json['year'] as num).toInt(),
      gpa: (json['gpa'] as num?)?.toDouble(),
      courses: List<String>.from(json['courses'] as List? ?? const []),
    );
  }
}
