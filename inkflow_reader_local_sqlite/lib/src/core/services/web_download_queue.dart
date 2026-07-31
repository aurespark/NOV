import 'dart:async';
import 'package:flutter/services.dart';

import '../../features/library/web_novel_models.dart';
import 'library_database.dart';
import 'web_chapter_downloader.dart';

class WebDownloadQueue {
  WebDownloadQueue({required this.database, required this.downloader, this.requestInterval = const Duration(milliseconds: 800)});

  final LibraryDatabase database;
  final WebChapterDownloader downloader;
  final Duration requestInterval;
  bool _running = false;
  bool _pauseRequested = false;
  static const _service = MethodChannel('inkflow/download_service');

  Future<void> enqueueBook(String bookId, {WebDownloadJobMode mode = WebDownloadJobMode.fullBook}) async {
    final jobs = await database.loadWebDownloadJobs();
    final existing = jobs.where((job) => job.bookId == bookId).firstOrNull;
    if (existing == null) {
      await database.saveWebDownloadJob(WebDownloadJob(bookId: bookId, mode: mode, status: WebDownloadJobStatus.pending, queuePosition: jobs.length));
    }
  }

  Future<void> run() async {
    if (_running) return;
    _running = true;
    _pauseRequested = false;
    try {
      try { await _service.invokeMethod<void>('start', {'title': '線上小說下載', 'progress': '準備下載'}); } on MissingPluginException {}
      for (final job in await database.loadWebDownloadJobs()) {
        if (_pauseRequested) break;
        if (job.status == WebDownloadJobStatus.cancelled || job.status == WebDownloadJobStatus.complete) continue;
        await database.saveWebDownloadJob(job.copyWith(status: WebDownloadJobStatus.running));
        for (final chapter in await database.loadWebChapters(job.bookId)) {
          if (_pauseRequested) break;
          if (chapter.status == WebChapterStatus.complete || chapter.isSourceRemoved) continue;
          await downloader.download(chapter);
          await Future<void>.delayed(requestInterval);
        }
        final summary = await database.webBookSummary(job.bookId);
        await database.saveWebDownloadJob(job.copyWith(
          status: _pauseRequested ? WebDownloadJobStatus.paused : WebDownloadJobStatus.complete,
          completedCount: summary.complete,
          partialCount: summary.partial,
          failedCount: summary.failed,
          blockedCount: summary.blocked,
        ));
      }
    } finally {
      _running = false;
      try { await _service.invokeMethod<void>('stop'); } on MissingPluginException {}
    }
  }

  void pause() => _pauseRequested = true;

  Future<void> cancel(String bookId) async {
    _pauseRequested = true;
    await database.deleteWebDownloadJob(bookId);
  }
}
