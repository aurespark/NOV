import 'package:flutter/material.dart';
import 'features/library/library_view.dart';

class InkflowApp extends StatelessWidget {
  const InkflowApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: '墨讀',
    theme: ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      colorScheme: const ColorScheme.dark(
        primary: Color(0xff9bb6a5),
        secondary: Color(0xffc4aa87),
        surface: Color(0xff151716),
        onSurface: Color(0xfff1f0eb),
        onSurfaceVariant: Color(0xff9a9d98),
      ),
      scaffoldBackgroundColor: const Color(0xff0b0c0c),
      canvasColor: const Color(0xff0b0c0c),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xff0b0c0c),
        surfaceTintColor: Colors.transparent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xff151716),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    ),
    home: const LibraryView(),
  );
}
