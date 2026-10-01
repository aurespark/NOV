import 'package:flutter/material.dart';

class ReaderPage extends StatefulWidget {
  final String bookId;
  final String bookTitle;
  final int initialChapterIndex;
  final List<dynamic> chapters;

  const ReaderPage({
    super.key,
    required this.bookId,
    required this.bookTitle,
    required this.initialChapterIndex,
    required this.chapters,
  });

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialChapterIndex;
    debugPrint('[ReaderPage] 📖 原生閱讀器啟動完成');
    debugPrint('[ReaderPage] 📑 當前閱讀書籍: ${widget.bookTitle} (ID: ${widget.bookId})');
    debugPrint('[ReaderPage] 🎯 初始化位置: 第 ${_currentIndex + 1} 章');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F5F0), // 羊皮紙底色
      appBar: AppBar(
        title: Text(widget.bookTitle),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.menu_book, size: 64, color: Colors.brown),
              const SizedBox(height: 16),
              Text(
                '第 ${_currentIndex + 1} 章',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text(
                '此處渲染原生文字章節內容，支援翻頁、字體調整與背景切換。',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.black87),
              ),
            ],
          ),
        ),
      ),
    );
  }
}