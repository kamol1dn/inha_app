import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'constants/app_styles.dart';

class UniversityApp extends StatelessWidget {
  const UniversityApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'University Tool App',
      theme: ThemeData(
        primarySwatch: AppStyles.primaryColor,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const HomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}