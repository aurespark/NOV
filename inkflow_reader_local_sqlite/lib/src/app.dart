import 'package:flutter/material.dart';
import 'features/library/library_view.dart';

class InkflowApp extends StatelessWidget {
  const InkflowApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: '墨讀',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xff755842),
        surface: const Color(0xfff7f2e8),
      ),
      fontFamily: 'serif',
      useMaterial3: true,
    ),
    home: const LibraryView(),
  );
}
