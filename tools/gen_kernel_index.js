#!/usr/bin/env node
// 生成 README 里的「内核下载索引」: 中文机型名 → 统一 Release 里的资产直链
// 用法: node tools/gen_kernel_index.js
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const OWNER = 'xingyiqaq';
const REPO = 'sukisu-kernel-builder';
const TAG = '内核合集';
const START = '<!-- KERNEL-INDEX:START -->';
const END = '<!-- KERNEL-INDEX:END -->';

// GitHub 会把 Release 资产名里的非 ASCII 字符静默删掉, 所以统一用 ASCII:
// 品牌_机型_代码_内核版本.zip (与 build.sh 的 sanitize_asset_name 保持一致)
const ascii = (x) =>
  String(x || '')
    .replace(/[^A-Za-z0-9._-]+/g, '_')
    .replace(/_+/g, '_')
    .replace(/^_|_$/g, '');

const data = JSON.parse(fs.readFileSync(path.join(ROOT, 'devices.json'), 'utf8'));
const rows = [];
let supported = 0;
for (const dev of data.devices) {
  const zh = (dev.zh || '').split(' / ')[0] || dev.display || dev.id;
  for (const v of dev.versions) {
    if (v.unsupported) continue;
    const asset = [dev.brand, dev.model, dev.id, v.kver].map(ascii).filter(Boolean).join('_') + '.zip';
    const url = `https://github.com/${OWNER}/${REPO}/releases/download/${encodeURIComponent(TAG)}/${encodeURIComponent(asset)}`;
    rows.push(`| ${zh} | \`${dev.id}\` | ${v.kver} | ${v.android || ''} | [${asset}](${url}) |`);
    supported++;
  }
}

const block = [
  START,
  `共 ${rows.length} 个可编译机型/内核版本组合。资产名格式 \`品牌_机型_机型代码_内核版本.zip\` —— GitHub 的 Release 资产名不支持中文, 所以资产本身是英文品牌+代码, 中文机型名请看本表首列(下表按中文机型名检索即可)。同一组合重新编译会覆盖同名资产, 链接长期有效。`,
  '',
  '| 中文机型名 | 机型代码 | 内核版本 | Android | 下载 |',
  '|---|---|---|---|---|',
  ...rows,
  END,
].join('\n');

const readmePath = path.join(ROOT, 'README.md');
let readme = fs.readFileSync(readmePath, 'utf8');
if (readme.includes(START) && readme.includes(END)) {
  const re = new RegExp(`${START}[\\s\\S]*?${END}`);
  readme = readme.replace(re, block);
} else {
  readme = `${readme.trimEnd()}\n\n## 十二、内核下载索引(中文机型名)\n\n${block}\n`;
}
fs.writeFileSync(readmePath, readme);
console.log(`已生成索引: ${rows.length} 行 (${supported} 个组合)`);
console.log(rows.slice(0, 2).join('\n'));
console.log('...');
console.log(rows[rows.length - 1]);
