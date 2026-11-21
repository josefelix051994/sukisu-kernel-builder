#!/usr/bin/env node
/**
 * 对 devices.json 做展示层整理(网页用):
 *   1) 设备按中文型号排序(中文按拼音, 英文按字母), 同名时按机型代码;
 *   2) 每个设备的 zh 名字串保证"中文名在前, 英文名在后"。
 *
 * 用法: node tools/normalize_devices.js   (在 gen_devices.sh 之后执行)
 */
'use strict';
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const FILE = path.join(ROOT, 'devices.json');
const hasZh = (s) => /[\u4e00-\u9fff]/.test(s);
const collator = new Intl.Collator('zh-Hans-CN', { numeric: true, sensitivity: 'base' });

const raw = fs.readFileSync(FILE, 'utf8').replace(/^\uFEFF/, '');
const data = JSON.parse(raw);

for (const dev of data.devices) {
  if (!dev.zh) continue;
  const parts = dev.zh.split(/\s*\/\s*/).filter(Boolean);
  dev.zh = [...parts.filter(hasZh), ...parts.filter((p) => !hasZh(p))].join(' / ');
}

data.devices.sort((a, b) => {
  const ka = a.zh || a.display || a.id;
  const kb = b.zh || b.display || b.id;
  return collator.compare(ka, kb) || a.id.localeCompare(b.id);
});

fs.writeFileSync(FILE, `${JSON.stringify(data, null, 2)}\n`, 'utf8');
console.log(`devices.json 已整理: ${data.devices.length} 台设备(按中文名排序)`);
