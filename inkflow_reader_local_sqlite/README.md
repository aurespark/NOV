# Inkflow Reader

## v6 線上小說

可從書籍介紹頁或目錄頁匯入線上小說，解析後逐章保存於 SQLite。程式支援靜態與 JavaScript 動態目錄、章內分頁、部分下載、目錄更新、Android 前景下載、離線閱讀、逐章進度與快取清除。

安全限制：只處理 HTTP/HTTPS 公開或已授權內容，不繞過登入、CAPTCHA、DRM 或付費牆；WebView 會拒絕自訂 scheme，並在完成後釋放。

Android 需要網路、通知及 dataSync 前景服務權限。首次大量下載前請確認網路與可用空間。

Inkflow Reader 是一個 Flutter TXT 小說閱讀器。它以本機書庫為核心，支援匯入 `.txt`、記錄閱讀進度、解析章節、調整閱讀版面，也支援從小說目錄 URL 匯入網頁章節清單。

## 功能

- 匯入本機 `.txt` 檔案，並複製到 App Support 目錄保存。
- 自動偵測 UTF-8、UTF-16 LE/BE，非 UTF-8 文字預設嘗試 Big5，也可手動選 Big5、GBK。
- 使用 SQLite 保存書籍資料、章節、閱讀位置、進度與完讀狀態。
- 書庫可依最近閱讀、書名或進度排序，並支援書名/作者搜尋。
- 閱讀器使用分批分頁，避免長文本一次排版造成卡頓。
- 閱讀設定支援字級、行高、字距、背景/文字主題、TTF 字型匯入與點擊翻頁。
- 可輸入小說目錄 URL，解析頁面標題、推測章節連結群，並保存網頁章節列表。

## URL 匯入目前做到的事

1. 在書庫新增來源時選擇網頁 URL。
2. 驗證 URL 必須是 `http` 或 `https`。
3. 下載目錄頁 HTML，解析 `<title>`、`h1`、`h2` 或 `og:title` 作為書名來源。
4. 收集頁面中的章節候選連結，排除常見導覽/登入/首頁類連結。
5. 依 DOM 位置與 URL 樣式分群，挑出最像章節列表的一群。
6. 將書籍與章節連結寫入 SQLite 的 `books` 與 `web_chapters`。
7. 點開網頁書籍時顯示已匯入的章節列表。

尚未實作：點擊網頁章節後下載章節本文並進入閱讀器。

## 專案結構

```text
lib/
  main.dart
  src/
    app.dart
    core/services/
      book_file_store.dart        # TXT 檔案保存
      encoding_service.dart       # TXT 編碼偵測與解碼
      font_loader_service.dart    # TTF 匯入與載入
      library_database.dart       # SQLite 書庫
      web_catalog_resolver.dart   # 網頁目錄連結解析
    features/
      library/                    # 書庫、書籍模型、網頁章節列表
      reader/                     # 閱讀器、設定面板、分頁引擎
test/                             # 單元與 Widget 測試
tool/check_canvas_interactions.js # design_canvas.html 互動檢查
```

## 開發環境

- Flutter SDK 3.35 或以上
- Dart SDK 3.9 或以上

安裝依賴：

```bash
flutter pub get
```

執行檢查：

```bash
flutter analyze
flutter test
```

啟動 App：

```bash
flutter run
```

如需重新產生平台目錄：

```bash
flutter create . --platforms=android,ios,web
```

## 資料儲存

- SQLite 資料庫：`inkflow_reader.db`
- 主要資料表：
  - `books`：書籍基本資料與來源
  - `reading_states`：目前閱讀位置、章節與進度
  - `chapters`：本機 TXT 章節標記
  - `web_chapters`：網頁目錄解析出的章節連結
- 匯入的 TXT 會存到 App Support 的 `books/<book-id>.txt`。

## 目前限制

- 網頁章節目前只匯入目錄與連結，尚未下載本文。
- 網頁目錄解析是啟發式規則，遇到特殊網站版型可能需要調整 `WebCatalogResolver`。
- UI 文字有部分編碼損毀，README 已先整理為可讀版本。
- `design_canvas.html` 是靜態設計/互動原型，不直接使用 Flutter App 的 SQLite 與服務層。
