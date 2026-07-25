import 'package:flutter/material.dart';
import 'features/library/library_view.dart';

class InkflowApp extends StatelessWidget {
  const InkflowApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: '墨讀',
    theme: ThemeData.dark(
      useMaterial3: true,
    ).copyWith(
      colorScheme: const ColorScheme.dark(
        primary: Color(0xffd8c3aa),
        secondary: Color(0xff9ab7a7),
        surface: Color(0xff121212),
      ),
      scaffoldBackgroundColor: const Color(0xff000000),
      canvasColor: const Color(0xff000000),
    ),
    home: const LibraryView(),
  );
}
