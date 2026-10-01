import 'package:flutter/material.dart';
import 'package:inkflow_reader/src/features/reader/domain/reader_models.dart';

class ReaderView extends StatefulWidget {
  final dynamic book;
  final List<ChapterMarker> chapters; // 👈 接收 List<ChapterMarker>
  final int initialChapterIndex;

  const ReaderView({
    super.key,
    required this.book,
    required this.chapters,
    this.initialChapterIndex = 0,
  });

  @override
  State<ReaderView> createState() => _ReaderViewState();
}

class _ReaderViewState extends State<ReaderView> {
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialChapterIndex;
    debugPrint('[ReaderView] 📖 原生閱讀器啟動完成');
    debugPrint('[ReaderView] 📑 接收到章節數: ${widget.chapters.length} 章');
    debugPrint('[ReaderView] 🎯 起始閱讀章節索引: $_currentIndex');
  }

  String _getBookTitle() {
    try {
      return (widget.book.title ?? widget.book.name ?? '閱讀器').toString();
    } catch (_) {
      return '閱讀器';
    }
  }

  String _getChapterTitle(int index) {
    if (index >= 0 && index < widget.chapters.length) {
      final dynamic ch = widget.chapters[index];
      try {
        return (ch.title ?? ch.name ?? '第 ${index + 1} 章').toString();
      } catch (_) {}
    }
    return '第 ${index + 1} 章';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F5F0), // 羊皮紙護眼底色
      appBar: AppBar(
        title: Text(_getBookTitle()),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.list),
            tooltip: '目錄',
            onPressed: () {
              // 展開目錄彈窗
              showModalBottomSheet(
                context: context,
                builder: (context) {
                  return ListView.builder(
                    itemCount: widget.chapters.length,
                    itemBuilder: (context, idx) {
                      return ListTile(
                        selected: idx == _currentIndex,
                        title: Text(_getChapterTitle(idx)),
                        onTap: () {
                          setState(() {
                            _currentIndex = idx;
                          });
                          Navigator.pop(context);
                        },
                      );
                    },
                  );
                },
              );
            },
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.menu_book, size: 72, color: Colors.brown),
              const SizedBox(height: 20),
              Text(
                _getChapterTitle(_currentIndex),
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              const Text(
                '此處渲染原生文字章節內容，支援翻頁、字體調整與背景顏色切換。',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.black87, height: 1.5),
              ),
              const SizedBox(height: 30),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                    onPressed: _currentIndex > 0
                        ? () => setState(() => _currentIndex--)
                        : null,
                    child: const Text('上一章'),
                  ),
                  const SizedBox(width: 20),
                  ElevatedButton(
                    onPressed: _currentIndex < widget.chapters.length - 1
                        ? () => setState(() => _currentIndex++)
                        : null,
                    child: const Text('下一章'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}