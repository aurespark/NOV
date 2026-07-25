# 墨讀（Inkflow Reader）

墨讀是以 Flutter 製作的本機 TXT 小說閱讀器，主要目標是讓 Android 與 iOS 裝置能順暢匯入大型小說、保存書架與閱讀進度，並提供章節跳轉與自訂 TTF 字體。

## 目前功能

- 匯入本機 `.txt`，選檔器只顯示 TXT
- 將原始 TXT 複製到 App 私人資料夾，外部檔案權限失效後仍可閱讀
- SQLite 保存書籍資料、章節文字位置與閱讀進度
- UTF-8、UTF-16 LE／BE、Big5、GBK 解碼
- 分批精準分頁：每批最多 6 頁、約 10 毫秒後交還畫面控制權
- 先恢復到已保存的字元位置，再於背景繼續計算剩餘頁數
- 點擊畫面中央顯示章節與閱讀設定，章節可直接跳轉
- 匯入 `.ttf` 字體，選檔器只顯示 TTF
- 字級、行距、字距、閱讀配色與左右點擊翻頁設定
- 搜尋、排序、編輯、已讀狀態與刪除書籍

`design_canvas.html` 是可直接操作的 UI 預覽。瀏覽器 Canvas 只模擬介面，不會使用 Flutter App 的 SQLite 或私人檔案目錄。

## 儲存架構

```text
書架／閱讀畫面
  ├─ LibraryDatabase
  │   ├─ books：書籍資訊與本機路徑
  │   ├─ reading_states：字元位置、進度、目前章節
  │   └─ chapters：章名與原文文字位置
  ├─ BookFileStore
  │   └─ App Support/books/<book-id>.txt
  └─ PaginationEngine
      └─ 記憶體中的 PageRange(start, end)
```

閱讀進度以「原文字元位置」保存，不以頁碼保存。字體、字級、行距、螢幕大小改變而重新分頁時，仍能回到相同內容。

分頁邊界目前只保存在記憶體。SQLite 分頁快取尚未加入，避免第一版同時處理快取版本與失效清理；若實機測試顯示重新開書的分頁時間仍過長，再加入持久化頁界。

## 主要程式

- `lib/src/core/services/book_file_store.dart`：TXT 複製與刪除
- `lib/src/core/services/library_database.dart`：SQLite 建表與讀寫
- `lib/src/core/services/encoding_service.dart`：TXT 編碼偵測與解碼
- `lib/src/core/services/font_loader_service.dart`：TTF 保存與載入
- `lib/src/features/reader/domain/pagination_engine.dart`：分批精準分頁
- `lib/src/features/reader/presentation/reader_view.dart`：背景批次流程、章節跳轉與進度保存
- `CHANGELOG.md`：每次修改紀錄

## 建立與執行

需要 Flutter 3.35 以上與 Dart 3.9 以上。

若下載內容尚未包含目標平台資料夾，先在專案根目錄執行：

```bash
flutter create . --platforms=android,ios,web
```

再執行：

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

SQLite 與本機檔案功能以 Android／iOS 為正式目標；`design_canvas.html` 用於桌面瀏覽器快速檢查介面。

Canvas 自動檢查：

```bash
node tool/check_canvas_interactions.js
```

## 資料安全

- TXT 先串流複製成暫存檔，確認非空後再重新命名。
- 書籍、初始進度與章節使用同一個 SQLite 交易寫入。
- 資料庫新增失敗時會清除已複製的 TXT，避免留下孤立檔案。
- 閱讀進度停止翻頁 800 毫秒後寫入；App 進入背景或離開閱讀器時立即寫入。
- 刪除書籍會同時刪除 SQLite 紀錄與 App 私人目錄中的 TXT。

## 已知限制

- 網路書籍目前只保存書名、作者與目錄 URL，尚未實作網站內容下載。
- 分頁使用 Flutter `TextPainter`，必須在 UI isolate 執行，因此以短批次主動讓出控制權。
- 尚未加入雲端同步、登入、分頁邊界持久化與重複書籍偵測。
