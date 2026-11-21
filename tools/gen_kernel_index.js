#!/usr/bin/env node
// 生成 README 里的「内核下载索引」: 中文机型名 → 统一 Release 里的资产直链
// 用法: node tools/gen_kernel_index.js [--write]
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const OWNER = 'xingyiqaq';
const REPO = 'sukisu-kernel-builder';
const TAG = '内核合集';
const START = '<!-- KERNEL-INDEX:START -->';
const END = '<!-- KERNEL-INDEX:END -->';

const sanitizeAsset = (s) =>
  String(s)
    .replace(/[/\\:*?"<>|]/g, '_')
    .replace(/\s+/g, '_')
    .replace(/_+/g, '_')
    .replace(/^_|_$/g, '');

const data = JSON.parse(fs.readFileSync(path.join(ROOT, 'devices.json'), 'utf8'));
const rows = [];
let supported = 0;
for (const dev of data.devices) {
  const zh = (dev.zh || '').split(' / ')[0] || dev.display || dev.id;
  for (const v of dev.versions) {
    if (v.unsupported) continue;
    const asset = `${sanitizeAsset(zh)}_${dev.id}_${v.kver}.zip`;
    const url = `https://github.com/${OWNER}/${REPO}/releases/download/${encodeURIComponent(TAG)}/${encodeURIComponent(asset)}`;
    rows.push(`| ${zh} | \`${dev.id}\` | ${v.kver} | ${v.android || ''} | [${asset}](${url}) |`);
    supported++;
  }
}

const block = [
  START,
  `共 ${rows.length} 个可编译机型/内核版本组合, 资产名格式 \`中文机型名_机型代码_内核版本.zip\`(同一组合重新编译会覆盖同名资产, 链接长期有效)。`,
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

if (process.argv.includes('--write')) {
  fs.writeFileSync(path.join(ROOT, 'docs', 'kernel-index.md'), `${block}\n`);
}
console.log(`已生成索引: ${rows.length} 行 (${supported} 个组合)`);
console.log(rows.slice(0, 3).join('\n'));
console.log('...');
console.log(rows[rows.length - 1]);
