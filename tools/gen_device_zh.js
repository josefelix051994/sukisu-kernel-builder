#!/usr/bin/env node
/**
 * 生成 tools/device_zh.tsv: <机型代码>\t<中文型号>
 *
 * 数据来源: tools/data/mi_devices.yml(XiaomiFirmwareUpdater 的 MIUI 机型表, 按地区记录
 *   codename → "营销名 + 地区"), 逐机型取各地区的营销名去重后作为该 codename 的机型名。
 *   这样避免"共用内核的分支把多台设备混在一起"的问题(例: cas/cmi/umi 以前都被写成
 *   "小米10 Ultra / 小米10 Pro / 小米10 / 红米K30 Pro", 现在分别是 小米10 Ultra、小米10 Pro、小米10)。
 *
 * 用法: node tools/gen_device_zh.js [devices.conf]
 */
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const CONF = process.argv[2] || path.join(ROOT, 'devices.conf');
const YML = path.join(__dirname, 'data', 'mi_devices.yml');
const OUT = path.join(__dirname, 'device_zh.tsv');

/* ---------- 1. 读 devices.conf 的设备列表 (保持出现顺序) ---------- */
const ids = [];
for (const raw of fs.readFileSync(CONF, 'utf8').split('\n')) {
  const line = raw.replace(/\r$/, '');
  if (!line || line.startsWith('#')) continue;
  const id = line.split('|')[0].trim();
  if (id && !ids.includes(id)) ids.push(id);
}

/* ---------- 2. 解析 mi_devices.yml ---------- */
const REGION_WORDS = [
  'China', 'Global', 'EEA', 'India', 'Russia', 'Indonesia', 'Turkey', 'Taiwan', 'Hong Kong',
  'Singapore', 'Malaysia', 'Thailand', 'Vietnam', 'Philippines', 'Japan', 'Korea', 'Mexico',
  'Brazil', 'Latin America', 'Europe', 'Middle East', 'Africa', 'Ukraine', 'Kazakhstan',
  'Spain', 'Italy', 'France', 'Germany', 'Poland', 'Czech', 'Romania', 'Hungary', 'Bulgaria',
  'Greece', 'Portugal', 'Netherlands', 'Belgium', 'Austria', 'Switzerland', 'Croatia',
  'Serbia', 'Bosnia', 'Slovenia', 'Slovakia', 'Sweden', 'Norway', 'Denmark', 'Finland',
  'Iceland', 'Ireland', 'UK', 'GB',
].sort((a, b) => b.length - a.length); // 先匹配长的, 避免 Latin America 被切碎

const REGION_TAIL = new RegExp(`\\s+(${REGION_WORDS.map((w) => w.replace(/ /g, '\\s+')).join('|')})$`);
// 地区后缀 → 优先级(越小越靠前): 中国 → 国际 → 印度 → EEA → 其它
function regionRank(key) {
  if (/_(eea_)?global$/.test(key) === false) return 0;           // 无地区后缀 = 中国版
  if (/^.*_global$/.test(key) && !/_(eea|in|id|ru|tr|tw)_global$/.test(key)) return 1;
  if (/_in_global$|_in$|_india$/.test(key)) return 2;
  if (/_eea_global$/.test(key)) return 3;
  return 4;
}
function baseCodename(key) {
  return key
    .replace(/_(eea_)?global$/, '')
    .replace(/_(in|id|ru|tr|tw|cn|india)$/, '');
}

const ymlRaw = fs.readFileSync(YML, 'utf8');
const byBase = new Map(); // base -> [{ rank, names: [..] }]
let curKey = null;
let curIdx = 0;
for (const raw of ymlRaw.split('\n')) {
  const line = raw.replace(/\r$/, '');
  if (!line.trim() || line.trim().startsWith('#')) continue;
  if (/^[^\s][^:]*:\s*$/.test(line)) {
    curKey = line.slice(0, line.lastIndexOf(':')).trim();
    curIdx = 0;
    continue;
  }
  if (curKey && /^\s*-\s+/.test(line)) {
    curIdx += 1;
    // 每个键下: 第 1 条是"营销名 + 地区", 第 2 条是内部型号代码(如 ALIOTHGlobal) → 只取第 1 条
    if (curIdx > 1) continue;
    const val = line.replace(/^\s*-\s+/, '').trim();
    const base = baseCodename(curKey);
    if (!byBase.has(base)) byBase.set(base, []);
    byBase.get(base).push({ rank: regionRank(curKey), names: val.split(/\s*\/\s*/) });
  }
}

/* ---------- 3. 人工覆盖(OnePlus / 通用 GKI / 数据源未收录的老机型) ---------- */
const OVERRIDE = {
  'gki-a12': '通用 GKI / Android 12',
  'gki-a13': '通用 GKI / Android 13',
  'gki-a14': '通用 GKI / Android 14',
  'gki-a15': '通用 GKI / Android 15',
  'gki-a16': '通用 GKI / Android 16',
  op7pro: 'OnePlus 7 Pro',
  op8: 'OnePlus 8',
  op8t: 'OnePlus 8T',
  op9: 'OnePlus 9',
  op9rt: 'OnePlus 9RT',
  laurel: 'Mi A3',          // MiCode 分支 laurel-*, 数据源里叫 laurel_sprout
  onc: 'Redmi Y3',          // 数据源里叫 onc_in_global
};

/* ---------- 4. 英文 → 中文 ---------- */
const REPS = [
  [/^POCOPHONE\b/, 'POCO'],
  [/^Redmi\s+Pad\b/, '红米平板'],
  [/^Redmi\b/, '红米'],
  [/^Xiaomi\s+Pad\b/, '小米平板'],
  [/^Xiaomi\b/, '小米'],
  [/^Mi\s+Pad\b/, '小米平板'],
  [/\bMi\s+Pad\b/, '小米平板'],
  [/^Mi\s+CC\s*9(e?)(?:\s+Meitu)?\b/, '小米CC9$1'],
  [/^Mi\s+MIX\b/, '小米MIX'],
  [/^Mi\s+MAX\b/, '小米MAX'],
  [/^MIX\b/, '小米MIX'],
  [/^Mi\b/, '小米'],
  [/^OnePlus\b/, '一加'],
  [/K40\s+Gaming/gi, 'K40 电竞版'],
  [/K50\s+Gaming/gi, 'K50 电竞版'],
  [/K60\s+Gaming/gi, 'K60 电竞版'],
  [/Note\s+12\s+Pro\s+Speed/gi, 'Note 12 Pro 极速版'],
];

function toZh(en) {
  let s = en.trim();
  for (const [re, rep] of REPS) s = s.replace(re, rep);
  s = s.replace(/\s{2,}/g, ' ').trim();
  // 中文品牌名与型号之间不留空格: 红米 K40 → 红米K40; 小米 平板 5 → 小米平板5
  s = s.replace(/^(红米|小米)\s+/g, '$1');
  s = s.replace(/^(红米|小米)平板\s+/g, '$1平板');
  return s;
}

/* ---------- 5. 生成每个机型的名字列表 ---------- */
const rows = [];
for (const id of ids) {
  let enNames;
  if (OVERRIDE[id]) {
    enNames = [OVERRIDE[id]];
  } else {
    const cand = byBase.get(id) || byBase.get(`${id}_sprout`) || null;
    if (!cand) {
      // 退化: 用 devices.conf 第 3 列显示名
      const line = fs.readFileSync(CONF, 'utf8').split('\n').find((l) => l.split('|')[0].trim() === id) || '';
      enNames = [line.split('|')[2] ? line.split('|')[2].trim() : id];
    } else {
      cand.sort((a, b) => a.rank - b.rank);
      const seen = new Set();
      enNames = [];
      const push = (name) => {
        if (enNames.length >= 3) return; // 每台最多 3 个名字
        const clean = name.replace(REGION_TAIL, '').replace(/\s+/g, ' ').trim();
        if (clean && !seen.has(clean)) {
          seen.add(clean);
          enNames.push(clean);
        }
      };
      for (const entry of cand) {
        const pieces = entry.names.map((n) => n.replace(REGION_TAIL, '').trim());
        // "Redmi K40 Pro / Pro+ China" 这类写法: 后段只是变体后缀, 需补回公共前缀
        const first = pieces[0] || '';
        const basePrefix = first.replace(/\s+(Pro\+?|Ultra|Prime|Lite|Turbo|Hypercharge|Discovery|Plus)\b.*$/i, '').trim();
        pieces.forEach((p, i) => {
          const isVariant = i > 0 && /^(Pro\+?|Ultra|Prime|Lite|Turbo|Hypercharge|Discovery|Plus|\+)/i.test(p);
          push(isVariant && basePrefix ? `${basePrefix} ${p}` : p);
        });
        if (enNames.length >= 3) break; // 最多保留 3 个名字, 避免列表过长
      }
      if (!enNames.length) enNames = [id];
    }
  }
  // 已有中文的(OVERRIDE/GKI)直接用; 其余走翻译; 最后保证"中文名在前, 英文名在后"
  const zhNames = enNames.map((n) => (/[\u4e00-\u9fff]/.test(n) && !/^OnePlus|^Mi\s|^Redmi|^Xiaomi|^POCO/.test(n) ? n : toZh(n)));
  const hasZh = (s) => /[\u4e00-\u9fff]/.test(s);
  const ordered = [
    ...zhNames.filter((n) => hasZh(n)),
    ...zhNames.filter((n) => !hasZh(n)),
  ];
  rows.push([id, ordered.join(' / ')]);
}

/* ---------- 6. 写出 ---------- */
rows.sort((a, b) => a[0].localeCompare(b[0]));
const header = [
  '# 机型代码\t中文型号 (由 tools/gen_device_zh.js 自动生成, 数据源 tools/data/mi_devices.yml)',
  '# 想改某个机型的显示名: 改 tools/gen_device_zh.js 的 OVERRIDE, 或直接改本文件后不要重跑生成器',
  '# 多地区同款机型用 " / " 分隔, 中文名在前英文名在后',
].join('\n');
fs.writeFileSync(OUT, `${header}\n${rows.map(([a, b]) => `${a}\t${b}`).join('\n')}\n`, 'utf8');
console.log(`生成 ${OUT}: ${rows.length} 条`);
