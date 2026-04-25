import 'package:flutter/material.dart';
import 'home_screen.dart';

void main() {
  runApp(const StratoApp());
}

class StratoApp extends StatelessWidget {
  const StratoApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Strato',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0B0419),
        primaryColor: const Color(0xFFDFC424),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFDFC424),
          secondary: Color(0xFFDFC424),
          surface: Color(0xFF1E1332),
          background: Color(0xFF0B0419),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0B0419),
          elevation: 0,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFDFC424),
            foregroundColor: const Color(0xFF0B0419),
            textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF1E1332),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFDFC424)),
          ),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
