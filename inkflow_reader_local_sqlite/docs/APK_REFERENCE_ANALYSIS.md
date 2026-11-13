# 參考 APK 分析與移植紀錄（2026-11-13）

參考對象：`cn.uujian.bookdownloader-3.3-82.apk`（uujian 小說下載器）。
分析方式：解壓 APK、讀取 assets、以 Android SDK `dexdump` 反組譯 `classes.dex`（程式已混淆，類別名為 `cn.uujian.i.a` 等）。

標記：**[確認]** = 反組譯或資產檔中直接看到；**[推測]** = 依常數/呼叫順序推斷，未逐行驗證。

## 一、APK 技術分析

| 項目 | 結果 |
|---|---|
| 架構 | 原生 Android（Java），HTML 解析用 **jsoup** [確認]；WebView + `addJavascriptInterface("meta")` 做「轉碼閱讀」頁 [確認] |
| 資料庫 | SQLite：`book(…next…)`、`catalog(bookid,url,title,save,position)`、`html/js/script` 規則表 [確認] |
| 站點規則 | 每站可存 `catalog_selector`、`read_selector`、`reversal`、`sort`（依 host 存在設定中）[確認]；正文找到的容器會回寫成該站 `read_selector`（自動學習）[推測，依 `i/d` 中先讀後寫同一鍵] |
| 下載 | `Jsoup.connect(url).userAgent("Mozilla/5.0").timeout(20000)` [確認]；編碼用 `charset=` 正則 + `meta[charset]`，支援 GBK [確認] |
| 目錄入口 | 在書籍頁找文字 ≤10 字且含「章节目录/查看目录/查看完整目录/全部章节/查看更多章节」的 `<a>`，取 `abs:href` [確認] |
| 目錄容器 | 比較 `ul/ol/dl/table` 內 `li a`/`dd a`/`td a` 數量挑最大者 [確認]；過濾文字為 登录/注册/收藏/返回/首页/男生/女生/会员/目录/排行/分类/出版/倒序/免费、`#` 結尾、含 `ooter`、`/txt.html` 的連結 [確認] |
| 目錄分頁 | 找「下一页/下页/下50章」連結；或 `<select><option>` 分頁並以 JS `$('select').val(n).change()` 切頁 [確認] |
| 排序/去重 | `i/e` 中有 `(List, boolean)` 的去重與反轉函式 [確認存在]，細節 [推測] |
| 正文 | 先用站點 `read_selector`，否則移除文字以連結為主的 `ul/dl`，逐一評分 `div/article…` 取文字最多者 [確認呼叫序，評分公式為推測]；`<br>/<p>/<hN>` 轉 `[br]` 再轉換行，每段加「　　」縮排 [確認] |
| 同章分頁 | 「下一页/下页/第二页/下一小节」且網址檔名含 `_` → 視為同章續頁並合併 [確認] |
| 下一章 | 「下一章/下章/下一节/下节」；另有 `#metaNext`/`#metaContent`/`#metaTitle` 自訂錨點 [確認] |
| 呈現 | 把結果組成簡化 HTML（`<a class='next' href='read:…'>`、`<a class='catalog'>`、「原網頁」），在 WebView 中以 `trans.js` 捲動到底自動載入下一頁 [確認] |
| 失敗處理 | 多為 `printStackTrace` 後回傳空字串，並保留「原網頁」連結讓使用者切回原站 [確認] |

## 二、差異比較與處理

| 功能 | 參考 APK | 原專案 | 本次處理 |
|---|---|---|---|
| 目錄網址識別 | 自動跳「完整目錄」 | 無，需手動貼目錄頁 | **新增** `findCatalogEntryUrl` |
| DOM 解析 | jsoup | `package:html`（已有） | 沿用；修正啟發式「外層容器分數較高」問題 |
| 目錄分頁 | 下一頁 + `<select>` | 只抓單頁 | **新增** `findNextCatalogPageUrl` 與逐頁合併（上限 50 頁） |
| 去重 / 最新章節區塊 | 有 | 保留首次出現 → 最新章節跑到最前面 | **改為保留最後一次出現**，兩種策略都套用 |
| 編碼 | charset 偵測 + GBK | 固定 UTF-8 | **新增** `detectHtmlCharset`/`decodeHtmlBytes`，沿用既有 `EncodingService` |
| 正文擷取 | selector → 文字密度評分 | 只認 `class="content"` 的正則，遇巢狀 div 會截斷 | **改用** `ChapterContentExtractor`（DOM 評分） |
| HTML 清理 | 移除連結清單、腳本 | 正則去標籤 | 移除腳本/隱藏防採集字/導覽/推薦清單/浮水印行 |
| 同章分頁 | 合併 | 即時閱讀路徑沒有 | **新增**（上限 20 頁） |
| 錯誤處理 | 回傳空字串 | 斷線回提示字串 | 中途斷線回傳已取得部分且**不寫快取**；目錄分頁失敗保留已取得章節 |
| 閱讀呈現 | WebView 轉碼頁 | 原生分頁閱讀器 | **不移植**，保留原生閱讀器（更符合 Flutter 架構） |

## 三、修改檔案

- 新增 `lib/src/core/services/novel_html_extractor.dart`：正文擷取、同章分頁、編碼偵測、共用下載器。
- `web_catalog_resolver.dart`：目錄入口、分頁、去重、編碼、評分修正。
- `online_chapter_service.dart`：改用新擷取器，同章分頁合併，失敗不快取。
- `content_sanitizer.dart`：`isAdLine` 改為公開，新增浮水印/導覽行規則。
- `reader_view.dart`、`reader_transition_helper.dart`：下載改用 `fetchNovelHtml`（GBK/Big5 可正確解碼）。
- `chapter_reader_service.dart`：匯出 `ChapterContentExtractor`（讓既有測試可編譯）。
- 新增 `test/core/services/novel_html_extractor_test.dart`（11 項）。

沒有資料庫遷移，也沒有改動資料表結構。

## 四、未移植 / 已知限制

- APK 的「每站自動學習 read_selector」：專案已有 `books.readSelector` 欄位但沒有寫回流程，這次未接上。
- `<select>` 分頁若靠 JS 換頁（option value 不是網址）仍無法處理，需要 WebView 模式。
- gb2312/gb18030 一律以 GBK 解碼，少數罕用字可能錯。
- `ChapterReaderService.loadChapter`、`ChapterAggregationPipeline`、WebView 內 JS 擷取目前不在主要閱讀路徑上，未調整。
