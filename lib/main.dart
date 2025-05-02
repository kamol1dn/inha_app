import 'package:flutter/material.dart';
import 'app.dart';

void main() {
  runApp(const UniversityApp());
}


//
// import 'package:flutter/material.dart';
// import 'package:webview_flutter/webview_flutter.dart';
//
// void main() {
//   runApp(const MyApp());
// }
//
// class MyApp extends StatelessWidget {
//   const MyApp({Key? key}) : super(key: key);
//
//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp(
//       title: 'University Tool App',
//       theme: ThemeData(
//         primarySwatch: Colors.blue,
//         visualDensity: VisualDensity.adaptivePlatformDensity,
//       ),
//       home: const HomePage(),
//       debugShowCheckedModeBanner: false,
//     );
//   }
// }
//
// class HomePage extends StatefulWidget {
//   const HomePage({Key? key}) : super(key: key);
//
//   @override
//   _HomePageState createState() => _HomePageState();
// }
//
// class _HomePageState extends State<HomePage> {
//   int _selectedIndex = 0;
//   final List<String> _titles = ['E-Class', 'GPA Calculator', 'Timetable', 'Email', 'INS'];
//
//   // WebView controllers
//   WebViewController? _eclassController;
//   WebViewController? _emailController;
//   WebViewController? _insController;
//
//   @override
//   void initState() {
//     super.initState();
//
//     // Initialize WebView controllers
//     _eclassController = WebViewController()
//       ..setJavaScriptMode(JavaScriptMode.unrestricted)
//       ..loadRequest(Uri.parse('https://eclass.inha.ac.kr/'));
//
//     _emailController = WebViewController()
//       ..setJavaScriptMode(JavaScriptMode.unrestricted)
//       ..loadRequest(Uri.parse('https://mail.inha.uz/'));
//
//     _insController = WebViewController()
//       ..setJavaScriptMode(JavaScriptMode.unrestricted)
//       ..loadRequest(Uri.parse('https://ins.inha.uz/'));
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: Text(_titles[_selectedIndex]),
//         centerTitle: true,
//       ),
//       body: _getBody(),
//       bottomNavigationBar: BottomNavigationBar(
//         type: BottomNavigationBarType.fixed,
//         currentIndex: _selectedIndex,
//         onTap: (index) {
//           setState(() {
//             _selectedIndex = index;
//           });
//         },
//         items: const [
//           BottomNavigationBarItem(
//             icon: Icon(Icons.school),
//             label: 'E-Class',
//           ),
//           BottomNavigationBarItem(
//             icon: Icon(Icons.calculate),
//             label: 'GPA',
//           ),
//           BottomNavigationBarItem(
//             icon: Icon(Icons.calendar_today),
//             label: 'Timetable',
//           ),
//           BottomNavigationBarItem(
//             icon: Icon(Icons.email),
//             label: 'Email',
//           ),
//           BottomNavigationBarItem(
//             icon: Icon(Icons.public),
//             label: 'INS',
//           ),
//         ],
//       ),
//     );
//   }
//
//   Widget _getBody() {
//     switch (_selectedIndex) {
//       case 0: // E-Class
//         return _eclassController != null
//             ? WebViewWidget(controller: _eclassController!)
//             : const Center(child: CircularProgressIndicator());
//
//       case 1: // GPA Calculator
//         return const GPACalculatorScreen();
//
//       case 2: // Timetable
//         return const TimetableScreen();
//
//       case 3: // Email
//         return _emailController != null
//             ? WebViewWidget(controller: _emailController!)
//             : const Center(child: CircularProgressIndicator());
//
//       case 4: // INS
//         return _insController != null
//             ? WebViewWidget(controller: _insController!)
//             : const Center(child: CircularProgressIndicator());
//
//       default:
//         return const Center(child: Text('Page not found'));
//     }
//   }
// }
//
// // GPA Calculator Screen
// class GPACalculatorScreen extends StatefulWidget {
//   const GPACalculatorScreen({Key? key}) : super(key: key);
//
//   @override
//   _GPACalculatorScreenState createState() => _GPACalculatorScreenState();
// }
//
// class _GPACalculatorScreenState extends State<GPACalculatorScreen> {
//   List<Course> courses = [
//     Course(name: 'Calculus I', credits: 3, grade: 'A'),
//     Course(name: 'Introduction to Computer Science', credits: 4, grade: 'A-'),
//     Course(name: 'Physics 101', credits: 4, grade: 'B+'),
//     Course(name: 'Academic English', credits: 3, grade: 'B'),
//     Course(name: 'History of Art', credits: 2, grade: 'A'),
//   ];
//
//   double calculateGPA() {
//     if (courses.isEmpty) return 0.0;
//
//     double totalPoints = 0.0;
//     int totalCredits = 0;
//
//     for (var course in courses) {
//       totalPoints += course.credits * getGradePoints(course.grade);
//       totalCredits += course.credits;
//     }
//
//     return totalCredits > 0 ? totalPoints / totalCredits : 0.0;
//   }
//
//   double getGradePoints(String grade) {
//     switch (grade) {
//       case 'A+': return 4.3;
//       case 'A': return 4.0;
//       case 'A-': return 3.7;
//       case 'B+': return 3.3;
//       case 'B': return 3.0;
//       case 'B-': return 2.7;
//       case 'C+': return 2.3;
//       case 'C': return 2.0;
//       case 'C-': return 1.7;
//       case 'D+': return 1.3;
//       case 'D': return 1.0;
//       case 'D-': return 0.7;
//       case 'F': return 0.0;
//       default: return 0.0;
//     }
//   }
//
//   void addCourse() {
//     setState(() {
//       courses.add(Course(name: '', credits: 3, grade: 'A'));
//     });
//   }
//
//   void removeCourse(int index) {
//     setState(() {
//       courses.removeAt(index);
//     });
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return Padding(
//       padding: const EdgeInsets.all(16.0),
//       child: Column(
//         children: [
//           // GPA Summary
//           Card(
//             elevation: 4,
//             child: Padding(
//               padding: const EdgeInsets.all(16.0),
//               child: Row(
//                 mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                 children: [
//                   const Text(
//                     'Current GPA:',
//                     style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
//                   ),
//                   Text(
//                     calculateGPA().toStringAsFixed(2),
//                     style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue),
//                   ),
//                 ],
//               ),
//             ),
//           ),
//           const SizedBox(height: 16),
//
//           // Course List Header
//           const Padding(
//             padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
//             child: Row(
//               children: [
//                 Expanded(
//                   flex: 3,
//                   child: Text('Course', style: TextStyle(fontWeight: FontWeight.bold)),
//                 ),
//                 Expanded(
//                   flex: 1,
//                   child: Text('Credits', style: TextStyle(fontWeight: FontWeight.bold)),
//                 ),
//                 Expanded(
//                   flex: 1,
//                   child: Text('Grade', style: TextStyle(fontWeight: FontWeight.bold)),
//                 ),
//                 SizedBox(width: 48),
//               ],
//             ),
//           ),
//
//           // Course List
//           Expanded(
//             child: ListView.builder(
//               itemCount: courses.length,
//               itemBuilder: (context, index) {
//                 return Card(
//                   margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 0),
//                   child: Padding(
//                     padding: const EdgeInsets.all(8.0),
//                     child: Row(
//                       children: [
//                         Expanded(
//                           flex: 3,
//                           child: TextFormField(
//                             initialValue: courses[index].name,
//                             decoration: const InputDecoration(
//                               hintText: 'Course name',
//                               border: OutlineInputBorder(),
//                               contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
//                             ),
//                             onChanged: (value) {
//                               setState(() {
//                                 courses[index].name = value;
//                               });
//                             },
//                           ),
//                         ),
//                         const SizedBox(width: 8),
//                         Expanded(
//                           flex: 1,
//                           child: DropdownButtonFormField<int>(
//                             value: courses[index].credits,
//                             decoration: const InputDecoration(
//                               border: OutlineInputBorder(),
//                               contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
//                             ),
//                             items: List.generate(6, (i) => i + 1)
//                                 .map((credit) => DropdownMenuItem(
//                               value: credit,
//                               child: Text('$credit'),
//                             ))
//                                 .toList(),
//                             onChanged: (value) {
//                               setState(() {
//                                 courses[index].credits = value ?? 3;
//                               });
//                             },
//                           ),
//                         ),
//                         const SizedBox(width: 8),
//                         Expanded(
//                           flex: 1,
//                           child: DropdownButtonFormField<String>(
//                             value: courses[index].grade,
//                             decoration: const InputDecoration(
//                               border: OutlineInputBorder(),
//                               contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
//                             ),
//                             items: const [
//                               DropdownMenuItem(value: 'A+', child: Text('A+')),
//                               DropdownMenuItem(value: 'A', child: Text('A')),
//                               DropdownMenuItem(value: 'A-', child: Text('A-')),
//                               DropdownMenuItem(value: 'B+', child: Text('B+')),
//                               DropdownMenuItem(value: 'B', child: Text('B')),
//                               DropdownMenuItem(value: 'B-', child: Text('B-')),
//                               DropdownMenuItem(value: 'C+', child: Text('C+')),
//                               DropdownMenuItem(value: 'C', child: Text('C')),
//                               DropdownMenuItem(value: 'C-', child: Text('C-')),
//                               DropdownMenuItem(value: 'D+', child: Text('D+')),
//                               DropdownMenuItem(value: 'D', child: Text('D')),
//                               DropdownMenuItem(value: 'D-', child: Text('D-')),
//                               DropdownMenuItem(value: 'F', child: Text('F')),
//                             ],
//                             onChanged: (value) {
//                               setState(() {
//                                 courses[index].grade = value ?? 'A';
//                               });
//                             },
//                           ),
//                         ),
//                         IconButton(
//                           icon: const Icon(Icons.delete, color: Colors.red),
//                           onPressed: () => removeCourse(index),
//                         ),
//                       ],
//                     ),
//                   ),
//                 );
//               },
//             ),
//           ),
//
//           // Add Course Button
//           Padding(
//             padding: const EdgeInsets.symmetric(vertical: 8.0),
//             child: ElevatedButton.icon(
//               icon: const Icon(Icons.add),
//               label: const Text('Add Course'),
//               onPressed: addCourse,
//               style: ElevatedButton.styleFrom(
//                 minimumSize: const Size.fromHeight(50),
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }
//
// // Timetable Screen
// class TimetableScreen extends StatelessWidget {
//   const TimetableScreen({Key? key}) : super(key: key);
//
//   @override
//   Widget build(BuildContext context) {
//     // Sample timetable data
//     Map<String, List<ClassSession>> timetable = {
//       'Monday': [
//         ClassSession(time: '09:00 - 10:30', course: 'Calculus I', location: 'Building 5, Room 302'),
//         ClassSession(time: '11:00 - 12:30', course: 'Physics 101', location: 'Science Hall, Room 201'),
//         ClassSession(time: '14:00 - 15:30', course: 'History of Art', location: 'Arts Building, Room 105'),
//       ],
//       'Tuesday': [
//         ClassSession(time: '09:00 - 10:30', course: 'Introduction to Computer Science', location: 'IT Building, Room 405'),
//         ClassSession(time: '13:00 - 14:30', course: 'Academic English', location: 'Languages Center, Room 203'),
//       ],
//       'Wednesday': [
//         ClassSession(time: '10:00 - 11:30', course: 'Calculus I', location: 'Building 5, Room 302'),
//         ClassSession(time: '14:00 - 15:30', course: 'Physics 101 Lab', location: 'Science Hall, Lab 105'),
//       ],
//       'Thursday': [
//         ClassSession(time: '09:00 - 10:30', course: 'Introduction to Computer Science', location: 'IT Building, Room 405'),
//         ClassSession(time: '13:00 - 14:30', course: 'Academic English', location: 'Languages Center, Room 203'),
//       ],
//       'Friday': [
//         ClassSession(time: '11:00 - 12:30', course: 'History of Art', location: 'Arts Building, Room 105'),
//         ClassSession(time: '15:00 - 16:30', course: 'Physics 101', location: 'Science Hall, Room 201'),
//       ],
//     };
//
//     List<String> days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'];
//
//     return DefaultTabController(
//       length: days.length,
//       child: Column(
//         children: [
//           TabBar(
//             isScrollable: true,
//             labelColor: Colors.blue,
//             unselectedLabelColor: Colors.grey,
//             tabs: days.map((day) => Tab(text: day)).toList(),
//           ),
//           Expanded(
//             child: TabBarView(
//               children: days.map((day) {
//                 List<ClassSession> sessions = timetable[day] ?? [];
//
//                 return sessions.isEmpty
//                     ? const Center(child: Text('No classes scheduled'))
//                     : ListView.builder(
//                   itemCount: sessions.length,
//                   padding: const EdgeInsets.all(16),
//                   itemBuilder: (context, index) {
//                     ClassSession session = sessions[index];
//
//                     return Card(
//                       margin: const EdgeInsets.only(bottom: 16),
//                       elevation: 2,
//                       child: Padding(
//                         padding: const EdgeInsets.all(16.0),
//                         child: Column(
//                           crossAxisAlignment: CrossAxisAlignment.start,
//                           children: [
//                             Row(
//                               children: [
//                                 const Icon(Icons.access_time, size: 16, color: Colors.blue),
//                                 const SizedBox(width: 8),
//                                 Text(
//                                   session.time,
//                                   style: const TextStyle(fontWeight: FontWeight.bold),
//                                 ),
//                               ],
//                             ),
//                             const SizedBox(height: 8),
//                             Text(
//                               session.course,
//                               style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
//                             ),
//                             const SizedBox(height: 4),
//                             Row(
//                               children: [
//                                 const Icon(Icons.location_on, size: 16, color: Colors.red),
//                                 const SizedBox(width: 8),
//                                 Text(session.location),
//                               ],
//                             ),
//                           ],
//                         ),
//                       ),
//                     );
//                   },
//                 );
//               }).toList(),
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }
//
// // Models
// class Course {
//   String name;
//   int credits;
//   String grade;
//
//   Course({required this.name, required this.credits, required this.grade});
// }
//
// class ClassSession {
//   final String time;
//   final String course;
//   final String location;
//
//   ClassSession({required this.time, required this.course, required this.location});
// }