import 'package:flutter/material.dart';

import '../../models/course.dart';
import '../../models/semester.dart';
import '../../services/gpa_service.dart';
import '../../utils/grade_calculator.dart';
import '../../constants/app_styles.dart';
import 'widgets/gpa_summary_card.dart';
import 'widgets/semester_list_item.dart';

class GPACalculatorScreen extends StatefulWidget {
  const GPACalculatorScreen({Key? key}) : super(key: key);

  @override
  _GPACalculatorScreenState createState() => _GPACalculatorScreenState();
}

class _GPACalculatorScreenState extends State<GPACalculatorScreen> {
  List<Semester> semesters = [];
  bool _isLoading = true;
  double overallGPA = 0.0;
  int completedSemesters = 0;

  // Scroll controller to detect scroll position
  final ScrollController _scrollController = ScrollController();
  // State variable to track if GPA should be shown in header
  bool _showGpaInHeader = false;

  @override
  void initState() {
    super.initState();
    _loadSemesters();

    // Add scroll listener to detect when GPASummaryCard goes out of view
    _scrollController.addListener(_updateHeaderGpaVisibility);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_updateHeaderGpaVisibility);
    _scrollController.dispose();
    super.dispose();
  }

  // Update header GPA visibility based on scroll position
  void _updateHeaderGpaVisibility() {
    // We consider that the summary card is hidden when scrolled past a certain threshold
    // Typically this would be the height of the card plus some padding
    final threshold = 100.0; // Adjust based on your GPASummaryCard height

    if (_scrollController.hasClients) {
      setState(() {
        _showGpaInHeader = _scrollController.offset > threshold;
      });
    }
  }

  // Count completed semesters
  void _updateCompletedSemestersCount() {
    setState(() {
      completedSemesters = semesters.where((semester) => semester.isCompleted).length;
    });
  }

  Future<void> _loadSemesters() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final loadedSemesters = await GPAService.loadSemesters();

      // Calculate GPA for each semester
      for (var semester in loadedSemesters) {
        semester.gpa = GradeCalculator.calculateGPA(semester.courses);
      }

      setState(() {
        semesters = loadedSemesters;
        overallGPA = GradeCalculator.calculateOverallGPA(semesters);
        _updateCompletedSemestersCount();
      });
    } catch (e) {
      debugPrint('Error loading semesters: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _saveSemesters() async {
    try {
      await GPAService.saveSemesters(semesters);
    } catch (e) {
      debugPrint('Error saving semesters: $e');
    }
  }

  void _addSemester() {
    setState(() {
      semesters.add(
        Semester(
          name: 'New Semester ${semesters.length + 1}',
          courses: [],
          gpa: 0.0,
          isCompleted: false, // Default new semesters to not completed
        ),
      );
    });
    _saveSemesters();
  }

  void _updateSemester(int index, Semester updatedSemester) {
    setState(() {
      semesters[index] = updatedSemester;
      overallGPA = GradeCalculator.calculateOverallGPA(semesters);
      _updateCompletedSemestersCount();
    });
    _saveSemesters();
  }

  void _addCourse(int semesterIndex) {
    setState(() {
      final updatedSemester = Semester.copy(semesters[semesterIndex]);
      updatedSemester.courses.add(Course(name: '', credits: 3, grade: 'A'));
      updatedSemester.gpa = GradeCalculator.calculateGPA(updatedSemester.courses);
      semesters[semesterIndex] = updatedSemester;
      overallGPA = GradeCalculator.calculateOverallGPA(semesters);
    });
    _saveSemesters();
  }

  void _removeCourse(int semesterIndex, int courseIndex) {
    setState(() {
      final updatedSemester = Semester.copy(semesters[semesterIndex]);
      updatedSemester.courses.removeAt(courseIndex);
      updatedSemester.gpa = GradeCalculator.calculateGPA(updatedSemester.courses);
      semesters[semesterIndex] = updatedSemester;
      overallGPA = GradeCalculator.calculateOverallGPA(semesters);
    });
    _saveSemesters();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      appBar: AppBar(
        scrolledUnderElevation: 0,
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('GPA Calculator'),
            // Show CGPA in header when scrolled past summary card
            if (_showGpaInHeader)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  'CGPA: ${overallGPA.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
          ],
        ),
      ),
      body: Padding(
        padding: AppStyles.contentPadding,
        child: ListView(
          controller: _scrollController,
          children: [
            GPASummaryCard(gpa: overallGPA),
            const SizedBox(height: 8),

            // Completed semesters counter
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Text(
                'Including $completedSemesters of ${semesters.length} semesters in GPA calculation',
                style: const TextStyle(
                  color: Colors.grey,
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
              ),
            ),

            const SizedBox(height: 16),

            if (semesters.isEmpty)
              const Center(child: Text('No semesters added yet'))
            else
              ...semesters.asMap().entries.map((entry) {
                int index = entry.key;
                Semester semester = entry.value;
                return SemesterListItem(
                  semester: semester,
                  semesterIndex: index,
                  onUpdate: (updatedSemester) => _updateSemester(index, updatedSemester),
                  onAddCourse: _addCourse,
                  onRemoveCourse: _removeCourse,
                );
              }).toList(),

            const SizedBox(height: 16),

            ElevatedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Add Semester'),
              onPressed: _addSemester,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
            ),
          ],
        ),
      ),
    );
  }
}