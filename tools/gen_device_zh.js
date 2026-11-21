/* 一次性工具: 生成 tools/device_zh.tsv (机型代码 -> 中文型号)
 * 数据来源: MiCode/Xiaomi_Kernel_OpenSource README 的机型表(权威) + 少量人工补充
 * 用法: node tools/gen_device_zh.js
 */
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const mapFile = path.join(__dirname, '.tmp_map.txt');       // codename \t English names
const outFile = path.join(__dirname, 'device_zh.tsv');

/* 人工补充: README 无记录或不在表内的机型(已核对来源) */
const EXTRA = {
  bomb: 'Redmi 10X, Redmi 10X Pro',
  evergo: 'Redmi Note 11T 5G',                     // Xiaomi-MT6833/kernel_xiaomi_evergo
  ingres: 'Redmi K50 Gaming, POCO F4 GT',          // LineageOS device_xiaomi_ingres
  lmi: 'Redmi K30 Pro, POCO F2 Pro',
  nitrogen: 'MI MAX3, MI 8Lite',
  perseus: 'MIX 2S',
  pyxis: 'MI CC 9, MI CC 9 Meitu Edition',
  sagit: 'Mi 6, Mi MIX 2',
  umi: 'Mi 10, Mi 10 Pro',
  vangogh: 'Mi 10T Lite, Redmi Note 9 Pro 5G',
  /* 一加(OnePlusOSS 分支) */
  op7pro: 'OnePlus 7, 7 Pro, 7T, 7T Pro',
  op8: 'OnePlus 8, 8 Pro',
  op8t: 'OnePlus 8T, 9R',
  op9: 'OnePlus 9, 9 Pro',
  op9rt: 'OnePlus 9RT',
  /* GKI 通用 */
  'gki-a12': 'General GKI, Android 12',
  'gki-a13': 'General GKI, Android 13',
  'gki-a14': 'General GKI, Android 14',
  'gki-a15': 'General GKI, Android 15',
  'gki-a16': 'General GKI, Android 16',
};

/* 显示名与 README 冲突时的人工修正(以实际机型为准) */
const OVERRIDE = {
  alioth: 'Redmi K40, POCO F3, Mi 10S',
  raphael: 'Redmi K20 Pro, Mi 9T Pro',
  davinci: 'Redmi K20, Mi 9T',
  ginkgo: 'Redmi Note 8, Redmi Note 8T',
  surya: 'POCO X3 NFC',
  haydn: 'Redmi K40 Pro, Redmi K40 Pro+',
  veux: 'Redmi Note 11 Pro 5G, POCO X4 Pro 5G',
  munch: 'Redmi K40S, POCO F4',
  camellian: 'POCO M3 Pro 5G, Redmi Note 10 5G, Redmi Note 10T',
  marble: 'Redmi Note 12 Turbo, POCO F5',
};

/* 英文 -> 中文 的机型系列替换(顺序敏感) */
const REPS = [
  [/POCOPHONE/gi, 'POCO'],
  [/\bRedmi POCO\b/gi, 'POCO'],
  [/\bRedmi POCO\b/gi, 'POCO'],
  [/\bMI CC 9e\b/gi, '小米CC9e'],
  [/\bMI CC 9\b/gi, '小米CC9'],
  [/\bMI CC9\b/gi, '小米CC9'],
  [/\bMI MAX3\b/gi, '小米MAX3'],
  [/\bMI MAX 3\b/gi, '小米MAX3'],
  [/\bMI 8Lite\b/gi, '小米8 Lite'],
  [/\bMI 8 Lite\b/gi, '小米8 Lite'],
  [/\bMIX FOLD\b/gi, '小米MIX FOLD'],
  [/\bMIX /g, '小米MIX '],
  [/\bMi 10 Lite 5G\b/gi, '小米10 Lite 5G'],
  [/\bMi 10 Lite Zoom\b/gi, '小米10 Lite Zoom'],
  [/\bMi A1\b/gi, '小米A1'],
  [/\bMi A2 lite\b/gi, '小米A2 Lite'],
  [/\bMi A2\b/gi, '小米A2'],
  [/\bMi A3\b/gi, '小米A3'],
  [/^\s*Mi\s+/i, '小米'],
  [/\bMi\s+/g, '小米'],
  [/^\s*MI\s+/i, '小米'],
  [/\bMI\s+/g, '小米'],
  [/\bXiaomi\s+/gi, '小米'],
  [/\bREDMI\s+/g, '红米'],
  [/\bRedmi\s+/g, '红米'],
  [/\bCivi\b/g, '小米Civi'],
  [/\bNote PAD\b/gi, 'Note'],
  /* 营销后缀本地化 */
  [/\bK40 Gaming\b/g, 'K40 电竞版'],
  [/\bK50 Gaming\b/g, 'K50 电竞版'],
  [/\bNote 12 Pro Speed\b/g, 'Note 12 Pro 极速版'],
  [/\bMix Flip\b/gi, 'MIX Flip'],
  [/\bPad\b/g, 'Pad'],
  [/\bGeneral GKI\b/g, '通用 GKI'],
  [/\bOnePlus\b/g, '一加'],
];

function translate(one) {
  let s = String(one).replace(/\s+/g, ' ').trim();
  for (const [re, rep] of REPS) s = s.replace(re, rep);
  // 清理: 双空格、中英之间多余空格(中文与英文/数字之间保留单空格更易读，这里只压缩重复)
  return s.replace(/\s+/g, ' ').trim();
}

function splitNames(english) {
  return english
    .split(/[,/]/)
    .map((s) => s.trim())
    .filter(Boolean);
}

const map = {};
if (fs.existsSync(mapFile)) {
  for (const raw of fs.readFileSync(mapFile, 'utf8').split('\n')) {
    // 兼容读取过程中可能混入的 NUL 字节(UTF-16 源被按 UTF-8 读)与 BOM 残留
    const line = raw.replace(/\u0000/g, '');
    const [idRaw, enRaw] = line.split('\t');
    const id = (idRaw || '').replace(/^[^\x21-\x7e]+/, '').trim();   // 去掉 UTF-16 BOM 产生的 U+FFFD 前缀
    const en = (enRaw || '').trim();
    if (id && en) map[id] = en;
  }
}
Object.assign(map, EXTRA);
Object.assign(map, OVERRIDE);

const rows = [];
for (const [id, en] of Object.entries(map)) {
  const names = splitNames(en).map(translate).filter(Boolean);
  // 去重(同一英文可能被两条规则翻成相同中文)
  const uniq = [...new Set(names)];
  if (!uniq.length) continue;
  rows.push([id, uniq.join(' / ')]);
}
rows.sort((a, b) => a[0].localeCompare(b[0]));

const header = [
  '# 机型代码 -> 中文型号(由 tools/gen_device_zh.js 生成)',
  '# 数据来源: MiCode/Xiaomi_Kernel_OpenSource README 官方机型表 + 人工核对补充',
  '# 格式: <codename>\\t<中文型号, 多合一同设备用 " / " 分隔>',
  '# 未列出的机型代码在网页上回退显示英文/代码',
].join('\n');
fs.writeFileSync(outFile, header + '\n' + rows.map((r) => r.join('\t')).join('\n') + '\n', 'utf8');
console.log(`生成 ${outFile}: ${rows.length} 条`);
