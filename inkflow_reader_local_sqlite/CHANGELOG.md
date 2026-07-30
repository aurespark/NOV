# 修改紀錄

此檔案記錄墨讀專案每次正式修改。日期以 Asia/Taipei 為準。


## 2026-07-30 — M2 URL、編碼與靜態目錄

### 新增

- 新增統一 URL 安全政策：限制 HTTP／HTTPS、最多 5 次重新導向、阻擋私人／回環位址，並正規化 fragment、追蹤參數、預設埠與相對網址。
- 新增 UTF-8、Big5、GBK 網頁解碼流程；依 HTTP Header、meta charset 與安全回退順序判定，不再以 Latin-1 當作通用回退。
- 新增錯誤頁、登入頁、CAPTCHA 與付費阻擋頁辨識。
- 新增多頁目錄 visited set、50 頁上限、跨頁 URL 去重、中文／全形章號解析及 70% 整體倒序校正。
- 新增匯入前確認畫面，顯示書名、來源網域、章節數及警告；重複來源只允許開啟或進入更新流程。
- 新增穩定的網頁編碼、重複章節、多頁目錄、循環與倒序測試 fixture。

### 修正

- 移除 rebase 後殘留於 `web_catalog_resolver.dart` 的 Git 衝突標記。
- 目錄解析結果改為決定性排序；相同 HTML 每次維持相同章節順序。
- 匯入流程在寫入前再次檢查正規化來源，避免同一操作程序建立重複書籍。

### 驗證

- 已加入 URL、編碼、阻擋頁、去重、多頁循環、倒序與章號解析單元測試。
- 已完成遠端檔案衝突標記與相依呼叫靜態檢查。
- 此 Codex 環境未安裝 Flutter SDK；`flutter analyze`、`flutter test`、Android debug build 與裝置手動驗收留待使用者此次 M2 檢查執行。

## 2026-07-30 — M1 領域模型與 SQLite v4

### 新增

- 新增線上章節、章內分頁、下載錯誤與結果、目錄差異、閱讀定位及下載工作領域模型。
- 新增 `web_chapter_pages`、`web_chapter_reading_states`、`web_download_jobs` 與查詢索引。
- 新增領域狀態機、v3 migration、交易回滾、repository CRUD、級聯刪除、快取保留與啟動修復測試。
- 新增 M1 GitHub Actions 驗證流程。

### 修改

- SQLite schema 由 v3 升級為 v4，migration 保留既有書籍、網頁目錄與閱讀進度。
- `WebChapter` 擴充下載狀態、正文、重試與錯誤欄位；只有 `complete` 視為已下載。
- 章節狀態、正文、錯誤與分頁採 transaction 原子寫入；失敗或重新下載開始不覆寫既有正文。
- 擴充資料庫 repository，集中處理線上章節、分頁、閱讀定位、下載工作、目錄差異與快取管理。


## 2026-07-25 — 閱讀面板響應式修正

- 修正窄螢幕開啟章節與閱讀設定時出現的 `RenderFlex overflowed`。
- 手機窄螢幕改為「章節／閱讀設定」分頁切換，較寬畫面維持左右並排。
- 閱讀主題按鈕改為自動換行，匯入字體區在極窄畫面改為上下排列。

## 2026-07-25 — Kotlin 跨磁碟機建置修正

- 暫時關閉 Kotlin 與 Kotlin/Java 漸進式編譯，避免 Windows 在 C 槽與 D 槽之間計算相對路徑時造成 Android 建置失敗。

## 2026-07-25 — Android 建置修正

- 修正 Gradle Wrapper 版本與啟動器，由錯誤的 2.x 更新為 Flutter 3.44.8 所需的 9.1.0，並加入發行檔 SHA-256 驗證。
- 保持 Android Gradle Plugin 9.0.1 與 Kotlin 2.3.20 不變。

## 2026-07-25 — Flutter 專案初始化

- 使用 Flutter 3.44.8／Dart 3.12.2 建立 Android 與 iOS 平台檔案。
- 安裝並鎖定 Riverpod、file_picker、sqflite、path_provider 等既有相依套件。
- 產生平台外掛註冊檔與 `pubspec.lock`。
- 移除 Flutter 自動產生且不適用本專案的 `MyApp` 範本測試。
- 修正分批分頁測試，使其逐批驗證完整文字範圍。
- 修正靜態分析指出的區塊括號與未使用匯入。

## 2026-07-25 — 本機儲存與分批精準分頁

### 新增

- 新增 SQLite 資料庫，包含 `books`、`reading_states`、`chapters` 三張資料表。
- 新增本機 TXT 檔案儲存，匯入後複製至 App 私人目錄。
- 新增 App 重開後載入書架、閱讀進度與章節。
- 新增閱讀進度延遲寫入，以及 App 進入背景／離開閱讀器時立即保存。
- 新增分批精準分頁，每輪最多計算 6 頁並限制約 10 毫秒運算時間。
- 新增「頁數計算中」狀態與尚未完成分頁時的章節延後跳轉。

### 修改

- 閱讀進度由頁碼改為原文 `characterOffset`。
- TXT 選檔器固定只允許 `.txt`。
- 字體選檔器與匯入服務固定只允許 `.ttf`，不再接受 OTF。
- 書籍刪除改為同步刪除 SQLite 紀錄與本機 TXT。
- Canvas 的 TXT／TTF 選檔限制與正式 App 保持一致。

### 保留

- 原有動態字體、閱讀設定、左右翻頁、章節側欄、搜尋與排序。
- 分頁邊界暫時只存在記憶體，尚未寫入 SQLite。

## 2026-07-24 — 章節側欄

- 點擊閱讀畫面中央時，左側顯示章節、右側顯示閱讀設定。
- 支援常見中文章回標題與 `Chapter`／`Section`。
- 點擊章節可跳至對應文字位置。

## 2026-07-24 — 動態頁數修正

- 移除 Canvas 固定三頁邏輯。
- 12,000 字測試可分為 47 頁，全文內容完整保留。
## 2026-07-31 — M2 目錄探索重構

- 將靜態目錄解析改為頁面角色辨識、目錄入口探索、多訊號候選、受限圖遍歷、多群組合併與完整性診斷。
- 支援介紹頁、純數字分頁、多卷／多容器、非標準章名與重複最新章節區。
- 新增 complete／warning／fallbackRequired 與停止原因，並比對章號缺口、目錄證據及最新章提示，供 M7 動態 WebView 備援使用。
- 同書範圍支援 path 與 query 型書 ID；加入連結密度評分，降低導覽／推薦區誤判。
- 新增 M2 Flutter 驗證 workflow 與匯入對話框 Widget 回歸測試。
- 修正匯入對話框 TextEditingController 路由卸載時序造成的 Flutter _dependents.isEmpty assertion。

