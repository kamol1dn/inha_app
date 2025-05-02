import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../constants/urls.dart';
import '../services/webview_service.dart';
import 'gpa_calculator/gpa_calculator_screen.dart';
import 'timetable/timetable_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  final List<String> _titles = ['E-Class', 'GPA Calculator', 'Timetable', 'Email', 'INS'];

  // WebView controllers
  late final WebViewController _eclassController;
  late final WebViewController _emailController;
  late final WebViewController _insController;

  @override
  void initState() {
    super.initState();

    // Initialize WebView controllers
    _eclassController = WebViewService.createController(AppUrls.eclass);
    _emailController = WebViewService.createController(AppUrls.email);
    _insController = WebViewService.createController(AppUrls.ins);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_selectedIndex]),
        centerTitle: true,
      ),
      body: _getBody(),
      bottomNavigationBar: _buildBottomNavigationBar(),
    );
  }

  Widget _buildBottomNavigationBar() {
    return BottomNavigationBar(
      type: BottomNavigationBarType.fixed,
      currentIndex: _selectedIndex,
      onTap: (index) {
        setState(() {
          _selectedIndex = index;
        });
      },
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.school),
          label: 'E-Class',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.calculate),
          label: 'GPA',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.calendar_today),
          label: 'Timetable',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.email),
          label: 'Email',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.public),
          label: 'INS',
        ),
      ],
    );
  }

  Widget _getBody() {
    switch (_selectedIndex) {
      case 0: // E-Class
        return WebViewWidget(controller: _eclassController);

      case 1: // GPA Calculator
        return const GPACalculatorScreen();

      case 2: // Timetable
        return const TimetableScreen();

      case 3: // Email
        return WebViewWidget(controller: _emailController);

      case 4: // INS
        return WebViewWidget(controller: _insController);

      default:
        return const Center(child: Text('Page not found'));
    }
  }
}