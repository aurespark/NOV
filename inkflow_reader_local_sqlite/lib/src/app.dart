import 'package:flutter/material.dart';

// 使用標準的 package 路徑引入
import 'package:inkflow_reader/src/features/library/library_view.dart';

class InkflowApp extends StatelessWidget {
  const InkflowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '墨讀',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
      ),
      home: const LibraryView(),
    );
  }
}