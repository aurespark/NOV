const fs = require('fs');
const path = require('path');

const html = fs.readFileSync(path.join(__dirname, '..', 'design_canvas.html'), 'utf8');
if (!html.includes('id="txtFile" type="file" accept=".txt"')) {
  throw new Error('TXT 選檔器未固定為 .txt');
}
if (!html.includes('id="fontFile" type="file" accept=".ttf"')) {
  throw new Error('字體選檔器未固定為 .ttf');
}
if (/accept="[^"]*otf/i.test(html)) {
  throw new Error('字體選檔器仍允許 OTF');
}
const checks = [
  ['上一頁', 'readerPrevious'],
  ['閱讀設定', 'readerMenu'],
  ['下一頁', 'readerNext'],
  ['匯入字體', 'fontImport'],
];

for (const [name, id] of checks) {
  const hasHandler =
    html.includes(`$('#${id}').addEventListener('pointerup'`) ||
    html.includes(`$('#${id}').onclick=`);
  if (!html.includes(`id="${id}"`) || !hasHandler) {
    throw new Error(`${name}點擊區未正確連接`);
  }
}

if (!html.includes('z-index:5;display:grid') || !html.includes('new TextDecoder') || !html.includes('new FontFace')) {
  throw new Error('Canvas 點擊層、TXT 解碼器或字體載入器缺失');
}

if (!html.includes('id="chapterList"') || !html.includes('function findChapters') || !html.includes('function pageForOffset')) {
  throw new Error('Canvas 章節側欄或章節跳轉未正確連接');
}

if (html.includes('return [0,1,2].map') || html.includes('Math.ceil(source.length/3)')) {
  throw new Error('Canvas 仍固定切成三頁');
}

const splitPagesSource = html.match(/function splitPages\(text\)\{[^\n]+\}/)?.[0];
if (!splitPagesSource) throw new Error('找不到 Canvas 分頁函式');
const splitPages = Function('$', `${splitPagesSource};return splitPages`)(
  selector => ({value: selector === '#fontSize' ? '18' : '1.9'}),
);
const longText = '測'.repeat(12000);
const pages = splitPages(longText);
if (pages.length <= 3 || pages.join('') !== longText) {
  throw new Error(`長篇 TXT 分頁失敗：${pages.length} 頁`);
}

const findChaptersSource = html.match(/function findChapters\(text\)\{[^\n]+\}/)?.[0];
if (!findChaptersSource) throw new Error('找不到 Canvas 章節解析函式');
const findChapters = Function(`${findChaptersSource};return findChapters`)();
const chapters = findChapters('序章\r\n內容\r\n第一章 相遇\r\n內容\r\nChapter 2 End\r\n內容');
if (chapters.length !== 3 || chapters[1].title !== '第一章 相遇') {
  throw new Error(`章節辨識失敗：${chapters.map(chapter => chapter.title).join('、')}`);
}

console.log(`Canvas 翻頁、設定、TXT 解碼、字體匯入、章節跳轉與長篇分頁：OK（12000 字 → ${pages.length} 頁，${chapters.length} 章）`);
