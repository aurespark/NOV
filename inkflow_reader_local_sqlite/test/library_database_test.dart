import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inkflow_reader/src/core/services/library_database.dart';
import 'package:inkflow_reader/src/features/library/book.dart';
import 'package:inkflow_reader/src/features/library/web_novel_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory temporaryDirectory;

  setUpAll(() {
    sqfliteFfiInit();
  });

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp('inkflow_m1_');
  });

  tearDown(() async {
    if (temporaryDirectory.existsSync()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test(
    'v3 migration preserves books, progress, and web catalog data',
    () async {
      final path = '${temporaryDirectory.path}/migration.db';
      final v3 = await _createV3Database(path);
      await v3.insert('books', _bookMap('local-1', BookSourceType.local));
      await v3.insert('books', _bookMap('web-1', BookSourceType.web));
      await v3.insert('reading_states', {
        'bookId': 'local-1',
        'characterOffset': 42,
        'currentChapter': '第二章',
        'progressRatio': .25,
        'lastReadAt': '2026-07-30T02:00:00.000Z',
      });
      await v3.insert('web_chapters', {
        'bookId': 'web-1',
        'url': 'https://example.com/1',
        'title': '第一章',
        'position': 0,
        'isDownloaded': 1,
      });
      await v3.close();

      final repository = LibraryDatabase(
        databaseFactory: databaseFactoryFfi,
        databasePath: path,
      );
      final database = await repository.database;

      expect(await database.getVersion(), LibraryDatabase.schemaVersion);
      expect((await repository.loadBooks()).map((book) => book.id).toSet(), {
        'local-1',
        'web-1',
      });
      final local = (await repository.loadBooks()).singleWhere(
        (book) => book.id == 'local-1',
      );
      expect(local.characterOffset, 42);
      expect(local.currentChapter, '第二章');
      final chapters = await repository.loadWebChapters('web-1');
      expect(chapters, hasLength(1));
      expect(chapters.single.normalizedUrl, 'https://example.com/1');
      expect(chapters.single.status, WebChapterStatus.pending);
      expect(chapters.single.isDownloaded, isFalse);
      expect(
        await _tableNames(database),
        containsAll({
          'web_chapter_pages',
          'web_chapter_reading_states',
          'web_download_jobs',
        }),
      );
      await repository.close();
    },
  );

  test('failed v4 migration rolls every schema change back', () async {
    final path = '${temporaryDirectory.path}/rollback.db';
    final v3 = await _createV3Database(path);
    await v3.execute('CREATE TABLE web_chapter_pages(conflict INTEGER)');
    await v3.close();

    final repository = LibraryDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: path,
    );
    await expectLater(repository.database, throwsA(anything));

    final reopened = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(version: 3),
    );
    expect(await reopened.getVersion(), 3);
    final columns = await reopened.rawQuery('PRAGMA table_info(web_chapters)');
    expect(columns.map((column) => column['name']), isNot(contains('status')));
    expect(
      columns.map((column) => column['name']),
      isNot(contains('normalizedUrl')),
    );
    await reopened.close();
  });

  test(
    'repository keeps chapter, page, reading, and job writes consistent',
    () async {
      final path = '${temporaryDirectory.path}/repository.db';
      final repository = LibraryDatabase(
        databaseFactory: databaseFactoryFfi,
        databasePath: path,
      );
      final book = Book(
        id: 'web-1',
        title: '測試書',
        author: '測試作者',
        sourceType: BookSourceType.web,
        catalogUrl: 'https://example.com/catalog',
        characterOffset: 0,
        currentChapter: '',
        progressRatio: 0,
        createdAt: DateTime.utc(2026, 7, 30),
        isFinished: false,
      );
      await repository.insertBook(
        book,
        webChapters: [
          WebChapter(url: 'https://example.com/1', title: '第一章', position: 0),
        ],
      );
      final chapter = (await repository.loadWebChapters(book.id)).single;
      final chapterId = chapter.id!;

      await repository.updateWebChapterStatus(
        chapterId,
        WebChapterStatus.downloading,
        incrementRetryCount: true,
      );
      await repository.upsertWebChapterPage(
        WebChapterPage(
          chapterId: chapterId,
          pageIndex: 0,
          sourceUrl: chapter.url,
          content: '尚未更新',
          status: WebPageStatus.complete,
        ),
      );
      await repository.upsertWebChapterPage(
        WebChapterPage(
          chapterId: chapterId,
          pageIndex: 0,
          sourceUrl: chapter.url,
          content: '第一頁正文',
          status: WebPageStatus.complete,
        ),
      );
      await repository.finishWebChapterDownload(
        chapterId,
        WebDownloadResult(
          status: WebChapterStatus.complete,
          content: '第一頁正文',
          pages: [
            WebChapterPage(
              chapterId: chapterId,
              pageIndex: 0,
              sourceUrl: chapter.url,
              content: '第一頁正文',
              status: WebPageStatus.complete,
            ),
          ],
        ),
      );
      await repository.saveWebChapterReadingState(
        WebChapterReadingState(
          chapterId: chapterId,
          bookId: book.id,
          paragraphAnchor: '第一頁正文',
          progressRatio: .5,
          lastReadAt: DateTime.utc(2026, 7, 30, 3),
        ),
      );
      await repository.saveWebDownloadJob(
        const WebDownloadJob(
          bookId: 'web-1',
          mode: WebDownloadJobMode.fullBook,
          queuePosition: 0,
        ),
      );

      final completed = await repository.loadWebChapter(chapterId);
      expect(completed!.status, WebChapterStatus.complete);
      expect(completed.isDownloaded, isTrue);
      expect(completed.content, '第一頁正文');
      expect(completed.retryCount, 1);
      final pages = await repository.loadWebChapterPages(chapterId);
      expect(pages, hasLength(1));
      expect(pages.single.content, '第一頁正文');
      expect(
        (await repository.loadWebChapterReadingState(chapterId))!.progressRatio,
        .5,
      );
      expect(await repository.loadWebDownloadJobs(), hasLength(1));

      await repository.updateWebChapterStatus(
        chapterId,
        WebChapterStatus.downloading,
        incrementRetryCount: true,
      );
      await repository.finishWebChapterDownload(
        chapterId,
        WebDownloadResult(
          status: WebChapterStatus.failed,
          content: '',
          error: const WebDownloadError(
            type: WebDownloadErrorType.timeout,
            message: '逾時',
          ),
        ),
      );
      final failed = await repository.loadWebChapter(chapterId);
      expect(failed!.status, WebChapterStatus.failed);
      expect(failed.isDownloaded, isFalse);
      expect(failed.content, '第一頁正文');
      expect(failed.retryCount, 2);

      await expectLater(
        repository.updateWebChapterStatus(
          chapterId,
          WebChapterStatus.downloading,
          content: '尚未驗證的新正文',
        ),
        throwsArgumentError,
      );
      final unchanged = await repository.loadWebChapter(chapterId);
      expect(unchanged!.content, '第一頁正文');
      expect(unchanged.status, WebChapterStatus.failed);

      await repository.clearWebBookDownloads(book.id);

      final cleared = await repository.loadWebChapter(chapterId);
      expect(cleared!.status, WebChapterStatus.pending);
      expect(cleared.content, isNull);
      expect(await repository.loadWebChapterPages(chapterId), isEmpty);
      expect(await repository.loadWebChapterReadingState(chapterId), isNotNull);
      await repository.close();
    },
  );

  test('startup repair returns interrupted chapters to pending', () async {
    final path = '${temporaryDirectory.path}/repair.db';
    final repository = LibraryDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: path,
    );
    await repository.insertBook(
      Book(
        id: 'web-1',
        title: '測試書',
        author: '測試作者',
        sourceType: BookSourceType.web,
        catalogUrl: 'https://example.com/catalog',
        characterOffset: 0,
        currentChapter: '',
        progressRatio: 0,
        createdAt: DateTime.utc(2026, 7, 30),
        isFinished: false,
      ),
      webChapters: [
        WebChapter(url: 'https://example.com/1', title: '第一章', position: 0),
      ],
    );
    final chapter = (await repository.loadWebChapters('web-1')).single;
    await repository.updateWebChapterStatus(
      chapter.id!,
      WebChapterStatus.downloading,
    );
    await repository.close();

    final reopened = LibraryDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: path,
    );
    expect(
      (await reopened.loadWebChapter(chapter.id!))!.status,
      WebChapterStatus.pending,
    );
    expect(await reopened.loadWebDownloadJobs(), isEmpty);
    await reopened.close();
  });

  test(
    'catalog diff applies atomically and rolls back invalid changes',
    () async {
      final path = '${temporaryDirectory.path}/catalog-diff.db';
      final repository = LibraryDatabase(
        databaseFactory: databaseFactoryFfi,
        databasePath: path,
      );
      await repository.insertBook(
        Book(
          id: 'web-1',
          title: '測試書',
          author: '測試作者',
          sourceType: BookSourceType.web,
          catalogUrl: 'https://example.com/catalog',
          characterOffset: 0,
          currentChapter: '',
          progressRatio: 0,
          createdAt: DateTime.utc(2026, 7, 30),
          isFinished: false,
        ),
        webChapters: [
          WebChapter(url: 'https://example.com/1', title: '第一章', position: 0),
        ],
      );
      final original = (await repository.loadWebChapters('web-1')).single;

      await repository.applyWebCatalogDiff(
        'web-1',
        WebCatalogDiff(
          changes: [
            WebCatalogChange(
              type: WebCatalogChangeType.updated,
              existingChapterId: original.id,
              incoming: WebChapter(
                url: original.url,
                title: '第一章（修訂）',
                position: 0,
              ),
            ),
            WebCatalogChange(
              type: WebCatalogChangeType.added,
              incoming: WebChapter(
                url: 'https://example.com/2',
                title: '第二章',
                position: 1,
              ),
            ),
          ],
        ),
      );
      final applied = await repository.loadWebChapters('web-1');
      expect(applied.map((chapter) => chapter.title), ['第一章（修訂）', '第二章']);

      await expectLater(
        repository.applyWebCatalogDiff(
          'web-1',
          WebCatalogDiff(
            changes: [
              WebCatalogChange(
                type: WebCatalogChangeType.added,
                incoming: WebChapter(
                  url: 'https://example.com/3',
                  title: '第三章',
                  position: 2,
                ),
              ),
              const WebCatalogChange(type: WebCatalogChangeType.updated),
            ],
          ),
        ),
        throwsStateError,
      );
      expect(
        (await repository.loadWebChapters(
          'web-1',
        )).any((chapter) => chapter.url.endsWith('/3')),
        isFalse,
      );
      await repository.close();
    },
  );

  test(
    'deleting a book cascades chapter-owned data and removes its job',
    () async {
      final path = '${temporaryDirectory.path}/delete.db';
      final repository = LibraryDatabase(
        databaseFactory: databaseFactoryFfi,
        databasePath: path,
      );
      await repository.insertBook(
        Book(
          id: 'web-1',
          title: '測試書',
          author: '測試作者',
          sourceType: BookSourceType.web,
          catalogUrl: 'https://example.com/catalog',
          characterOffset: 0,
          currentChapter: '',
          progressRatio: 0,
          createdAt: DateTime.utc(2026, 7, 30),
          isFinished: false,
        ),
        webChapters: [
          WebChapter(url: 'https://example.com/1', title: '第一章', position: 0),
        ],
      );
      final chapter = (await repository.loadWebChapters('web-1')).single;
      await repository.upsertWebChapterPage(
        WebChapterPage(
          chapterId: chapter.id!,
          pageIndex: 0,
          sourceUrl: chapter.url,
          content: '內容',
          status: WebPageStatus.complete,
        ),
      );
      await repository.saveWebChapterReadingState(
        WebChapterReadingState(chapterId: chapter.id!, bookId: 'web-1'),
      );
      await repository.saveWebDownloadJob(
        const WebDownloadJob(
          bookId: 'web-1',
          mode: WebDownloadJobMode.fullBook,
          queuePosition: 0,
        ),
      );

      await repository.deleteBook('web-1');

      expect(await repository.loadWebChapters('web-1'), isEmpty);
      expect(await repository.loadWebChapterPages(chapter.id!), isEmpty);
      expect(await repository.loadWebChapterReadingState(chapter.id!), isNull);
      expect(await repository.loadWebDownloadJobs(), isEmpty);
      await repository.close();
    },
  );
}

Future<Database> _createV3Database(String path) =>
    databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 3,
        onConfigure: (database) => database.execute('PRAGMA foreign_keys = ON'),
        onCreate: (database, _) async {
          await database.execute('''
            CREATE TABLE books(
              id TEXT PRIMARY KEY,
              title TEXT NOT NULL,
              author TEXT NOT NULL,
              sourceType TEXT NOT NULL,
              localPath TEXT,
              textEncoding TEXT,
              fileSize INTEGER,
              catalogUrl TEXT,
              catalogSelector TEXT,
              coverPath TEXT,
              createdAt TEXT NOT NULL,
              isFinished INTEGER NOT NULL DEFAULT 0
            )
          ''');
          await database.execute('''
            CREATE TABLE reading_states(
              bookId TEXT PRIMARY KEY,
              characterOffset INTEGER NOT NULL DEFAULT 0,
              currentChapter TEXT NOT NULL DEFAULT '',
              progressRatio REAL NOT NULL DEFAULT 0,
              lastReadAt TEXT,
              FOREIGN KEY(bookId) REFERENCES books(id) ON DELETE CASCADE
            )
          ''');
          await database.execute('''
            CREATE TABLE chapters(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              bookId TEXT NOT NULL,
              chapterIndex INTEGER NOT NULL,
              title TEXT NOT NULL,
              characterOffset INTEGER NOT NULL,
              FOREIGN KEY(bookId) REFERENCES books(id) ON DELETE CASCADE,
              UNIQUE(bookId, chapterIndex)
            )
          ''');
          await database.execute('''
            CREATE TABLE web_chapters(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              bookId TEXT NOT NULL,
              url TEXT NOT NULL,
              title TEXT NOT NULL,
              position INTEGER NOT NULL,
              isDownloaded INTEGER NOT NULL DEFAULT 0,
              FOREIGN KEY(bookId) REFERENCES books(id) ON DELETE CASCADE,
              UNIQUE(bookId, url)
            )
          ''');
        },
      ),
    );

Map<String, Object?> _bookMap(String id, BookSourceType sourceType) => {
  'id': id,
  'title': id,
  'author': '測試作者',
  'sourceType': sourceType.name,
  'catalogUrl': sourceType == BookSourceType.web
      ? 'https://example.com/catalog'
      : null,
  'createdAt': '2026-07-30T00:00:00.000Z',
  'isFinished': 0,
};

Future<Set<String>> _tableNames(Database database) async => {
  for (final row in await database.query(
    'sqlite_master',
    columns: ['name'],
    where: 'type = ?',
    whereArgs: ['table'],
  ))
    row['name']! as String,
};
