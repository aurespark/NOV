import 'package:flutter/material.dart';
import 'book.dart';
import 'web_novel_models.dart';

class WebChapterListView extends StatelessWidget {
  const WebChapterListView({
    super.key,
    required this.book,
    required this.chapters,
  });

  final Book book;
  final List<WebChapter> chapters;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(book.title)),
      body: chapters.isEmpty
          ? const Center(child: Text('此書沒有找到任何章節'))
          : ListView.builder(
              itemCount: chapters.length,
              itemBuilder: (context, index) {
                final chapter = chapters[index];
                return ListTile(
                  title: Text(chapter.title),
                  onTap: () {
                    // TODO: Implement chapter content fetching and display
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('TODO: 開啟章節: ${chapter.title}')),
                    );
                  },
                );
              },
            ),
    );
  }
}
