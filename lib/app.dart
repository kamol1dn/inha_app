import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'constants/app_styles.dart';

class UniversityApp extends StatelessWidget {
  const UniversityApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Inha Tools',
      theme: ThemeData(
        primarySwatch: AppStyles.primaryColor,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const HomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}