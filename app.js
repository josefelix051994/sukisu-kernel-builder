/* SukiSU-Ultra 内核编译 · GitHub Actions 前端逻辑 */
'use strict';

const API = 'https://api.github.com';
const OWNER = 'xingyiqaq';
const REPO = 'sukisu-kernel-builder';
const WORKFLOW_FILE = 'build.yml';
const REF = 'main';

const $ = (id) => document.getElementById(id);
const state = {
  token: localStorage.getItem('gh-token') || '',
  devices: [],
  curRunId: null,
  curDeviceLabel: '',
  pollTimer: null,
  logXHR: null,
  logLen: 0,
  logFollow: true,
  pollCount: 0,
};

/* ---------- API ---------- */
async function api(path, opts = {}) {
  const headers = { Accept: 'application/vnd.github+json' };
  if (state.token) headers.Authorization = `Bearer ${state.token}`;
  const res = await fetch(`${API}${path}`, { ...opts, headers: { ...headers, ...(opts.headers || {}) } });
  if (res.status === 401 || res.status === 403) {
    throw new Error(`GitHub API 返回 ${res.status}: Token 无效或权限不足(需要 repo + workflow 权限)`);
  }
  return res;
}

async function apiJson(path, opts = {}) {
  const res = await api(path, opts);
  if (res.status === 204) return null;
  const text = await res.text();
  let data = null;
  try { data = JSON.parse(text); } catch { data = text; }
  if (!res.ok) throw new Error(`GitHub API ${res.status}: ${(data && data.message) || text}`);
  return data;
}

/* ---------- 初始加载 ---------- */
async function init() {
  $('gh-token').value = state.token;
  renderTokenStatus();
  $('save-token').addEventListener('click', saveToken);
  $('clear-token').addEventListener('click', () => { localStorage.removeItem('gh-token'); state.token = ''; $('gh-token').value = ''; renderTokenStatus(); });
  $('build-btn').addEventListener('click', () => startBuild(false));
  $('dry-run-btn').addEventListener('click', () => startBuild(true));
  $('cancel-btn').addEventListener('click', cancelRun);
  $('device').addEventListener('change', renderVersions);
  $('custom-mode').addEventListener('change', toggleCustom);
  const logBox = $('log');
  logBox.addEventListener('scroll', () => {
    state.logFollow = logBox.scrollHeight - logBox.scrollTop - logBox.clientHeight < 60;
    $('log-follow').textContent = state.logFollow ? '跟随更新' : '已暂停跟随(滚动到底部恢复)';
  });

  try {
    const res = await fetch('devices.json', { cache: 'no-store' });
    state.devices = (await res.json()).devices;
    renderDevices();
  } catch (e) {
    $('device-info').textContent = '设备列表加载失败: ' + e.message;
  }
  await renderHistory();
  // 恢复: 若 token 存在且有进行中的构建, 自动挂载
  if (state.token) await autoResume();
}

function renderTokenStatus() {
  $('token-status').textContent = state.token
    ? '✓ 已保存 Token(仅存于本浏览器 localStorage)'
    : '尚未保存 Token, 触发编译前请先保存。';
}
function saveToken() {
  state.token = $('gh-token').value.trim();
  if (!state.token) { $('token-status').textContent = 'Token 不能为空。'; return; }
  localStorage.setItem('gh-token', state.token);
  renderTokenStatus();
}

/* ---------- 设备/版本 ---------- */
function renderDevices() {
  const sel = $('device');
  sel.innerHTML = '';
  for (const d of state.devices) {
    const o = document.createElement('option');
    o.value = d.id;
    o.textContent = `${d.display} (${d.id})`;
    sel.appendChild(o);
  }
  renderVersions();
}

function renderVersions() {
  const id = $('device').value;
  const dev = state.devices.find((d) => d.id === id);
  const sel = $('version');
  sel.innerHTML = '';
  if (!dev) return;
  dev.versions.forEach((v, i) => {
    const o = document.createElement('option');
    o.value = String(i + 1);
    o.textContent = `${i + 1}. ${v.label}`;
    sel.appendChild(o);
  });
  const v = dev.versions[0];
  $('device-info').innerHTML = v
    ? `仓库: <code>${v.repo}</code> · 分支: <code>${v.branch}</code> · defconfig: <code>${v.defconfig || '自动探测'}</code> · 内核: Linux ${v.kver}`
    : '';
}

function toggleCustom() {
  const on = $('custom-mode').checked;
  $('custom-fields').hidden = !on;
  $('device').disabled = on;
  $('version').disabled = on;
}

/* ---------- 触发构建 ---------- */
async function startBuild(dryRun) {
  if (!state.token) { setMsg('请先保存 GitHub Token。', true); $('token-card').scrollIntoView({ behavior: 'smooth' }); return; }
  const inputs = collectInputs(dryRun);
  $('build-btn').disabled = true; $('dry-run-btn').disabled = true;
  try {
    setMsg(dryRun ? '正在触发演练任务…' : '正在触发编译任务…');
    await apiJson(`/repos/${OWNER}/${REPO}/actions/workflows/${WORKFLOW_FILE}/dispatches`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ ref: REF, inputs }),
    });
    state.curDeviceLabel = inputs.custom_repo ? `自定义: ${inputs.custom_repo}@${inputs.custom_branch}` : `设备: ${inputs.device} (v${inputs.version})`;
    setMsg('任务已触发, 正在等待 runner 启动…');
    $('progress-card').hidden = false;
    $('artifacts').hidden = true;
    $('log').textContent = '';
    $('cancel-btn').hidden = false;
    state.logLen = 0;
    const run = await findNewRun();
    if (!run) { setMsg('触发成功但 30 秒内未找到对应运行, 请稍后在「最近构建」中查看。', true); return; }
    state.curRunId = run.id;
    attachRun(run.id);
  } catch (e) {
    setMsg('触发失败: ' + e.message, true);
  } finally {
    $('build-btn').disabled = false; $('dry-run-btn').disabled = false;
  }
}

function collectInputs(dryRun) {
  const custom = $('custom-mode').checked;
  const inputs = {
    device: custom ? 'custom' : $('device').value,
    version: custom ? '1' : $('version').value || '1',
    ksu_branch: $('ksu-branch').value,
    ksu_mode: $('ksu-mode').value,
    kpm: String($('kpm').checked),
    debug_ksu: String($('debug-ksu').checked),
    jobs: $('jobs').value.trim(),
    clean: String($('clean').checked),
    custom_repo: custom ? $('custom-repo').value.trim() : '',
    custom_branch: custom ? $('custom-branch').value.trim() : '',
    custom_defconfig: custom ? $('custom-defconfig').value.trim() : '',
    custom_kver: custom ? $('custom-kver').value.trim() : '',
    custom_android: custom ? $('custom-android').value.trim() : '',
    custom_gki: custom ? String($('custom-gki').checked) : 'false',
    dry_run: String(dryRun),
  };
  if (custom && (!inputs.custom_repo || !inputs.custom_branch)) {
    throw new Error('自定义源必须填写仓库 URL 和分支');
  }
  return inputs;
}

async function findNewRun() {
  const t0 = Date.now() - 3000;
  for (let i = 0; i < 15; i++) {
    await sleep(2000);
    try {
      const data = await apiJson(`/repos/${OWNER}/${REPO}/actions/runs?event=workflow_dispatch&per_page=5`);
      for (const run of data.workflow_runs || []) {
        if (new Date(run.created_at).getTime() >= t0) return run;
      }
    } catch { /* 继续等 */ }
  }
  return null;
}

/* ---------- 运行状态轮询 ---------- */
async function attachRun(runId) {
  stopPolling();
  state.curRunId = runId;
  $('progress-card').hidden = false;
  state.logLen = 0;
  $('log').textContent = '';
  $('artifacts').hidden = true;
  $('cancel-btn').hidden = true;
  state.pollCount = 0;
  await tick();
  state.pollTimer = setInterval(tick, 3000);
}

async function tick() {
  if (!state.curRunId) return;
  try {
    const run = await apiJson(`/repos/${OWNER}/${REPO}/actions/runs/${state.curRunId}`);
    renderRun(run);
    const jobs = await apiJson(`/repos/${OWNER}/${REPO}/actions/runs/${state.curRunId}/jobs`);
    renderSteps(jobs.jobs || []);
    if (run.status === 'in_progress' || run.status === 'queued') {
      startLogStream(run);
    } else if (run.status === 'completed') {
      stopLogStream();
      if (!$('log').textContent) {
        $('log').textContent = '(构建已结束, 实时日志流已关闭。点击右上角「在 GitHub 打开」可查看完整日志。)';
      }
      await renderArtifacts(run);
      $('cancel-btn').hidden = true;
      stopPolling();
      await renderHistory();
    }
  } catch (e) {
    $('run-status-badge').textContent = '轮询出错';
    $('run-status-badge').className = 'badge failure';
  }
}

function renderRun(run) {
  const badge = $('run-status-badge');
  const map = { queued: '排队中', in_progress: '编译中', completed: '已结束' };
  badge.textContent = map[run.status] || run.status;
  badge.className = 'badge ' + run.status;
  if (run.status === 'completed') badge.textContent = `已结束 · ${conclusionText(run.conclusion)}`;
  badge.classList.add(conclusionClass(run.conclusion));
  $('run-name').textContent = `${state.curDeviceLabel} · 运行 #${run.run_number} · 事件 ${run.event} · 分支 ${run.head_branch}`;
  $('run-link').href = run.html_url;
  $('cancel-btn').hidden = !(run.status === 'in_progress' || run.status === 'queued');
}

function conclusionText(c) {
  return { success: '成功 ✅', failure: '失败 ❌', cancelled: '已取消', timed_out: '超时', skipped: '跳过' }[c] || c || '';
}
function conclusionClass(c) { return c || ''; }

function renderSteps(jobs) {
  const tb = $('steps-body');
  const steps = jobs.flatMap((j) => j.steps || []);
  tb.innerHTML = '';
  for (const s of steps) {
    const tr = document.createElement('tr');
    const cls = s.status === 'completed'
      ? (s.conclusion === 'success' ? 'ok' : 'fail')
      : s.status === 'in_progress' ? 'run' : 'queued';
    const txt = s.status === 'completed'
      ? (s.conclusion === 'success' ? '完成' : `失败(${s.conclusion})`)
      : s.status === 'in_progress' ? '进行中' : '等待中';
    tr.innerHTML = `<td>${esc(s.name)}</td>
      <td><span class="step-status"><span class="dot ${cls}"></span>${esc(txt)}</span></td>
      <td>${esc(duration(s.started_at, s.completed_at))}</td>`;
    tb.appendChild(tr);
  }
}

function duration(a, b) {
  if (!a) return '—';
  const end = b ? new Date(b) : new Date();
  const s = Math.max(0, Math.round((end - new Date(a)) / 1000));
  if (s < 60) return `${s}s`;
  const m = Math.floor(s / 60);
  return m >= 60 ? `${Math.floor(m / 60)}h${m % 60}m` : `${m}m${s % 60}s`;
}

/* ---------- 实时日志(XHR 流式读取) ---------- */
function startLogStream(run) {
  if (state.logXHR || !run.logs_url) return;
  const xhr = new XMLHttpRequest();
  state.logXHR = xhr;
  state.logLen = 0;
  $('log').textContent = '';
  xhr.open('GET', run.logs_url, true);
  if (state.token) xhr.setRequestHeader('Authorization', `Bearer ${state.token}`);
  xhr.onprogress = () => {
    const t = xhr.responseText || '';
    if (t.length > state.logLen) {
      $('log').textContent += t.slice(state.logLen);
      state.logLen = t.length;
      trimLog();
      if (state.logFollow) $('log').scrollTop = $('log').scrollHeight;
    }
  };
  xhr.onerror = () => {
    state.logXHR = null;
    $('log').textContent += '\n[日志流连接失败, 请点击右上角「在 GitHub 打开」查看日志]\n';
  };
  xhr.onloadend = () => { state.logXHR = null; };
  try { xhr.send(); } catch { state.logXHR = null; }
}
function stopLogStream() {
  if (state.logXHR) { try { state.logXHR.abort(); } catch {} state.logXHR = null; }
}
function trimLog() {
  const box = $('log');
  const lines = box.textContent.split('\n');
  if (lines.length > 400) box.textContent = '...(已截断)\n' + lines.slice(-300).join('\n');
}

/* ---------- 产物 ---------- */
async function renderArtifacts(run) {
  try {
    const data = await apiJson(`/repos/${OWNER}/${REPO}/actions/runs/${run.id}/artifacts`);
    const arts = (data.artifacts || []).filter((a) => !a.expired);
    const wrap = $('artifacts');
    wrap.hidden = arts.length === 0;
    const ul = $('artifact-list');
    ul.innerHTML = '';
    for (const a of arts) {
      const li = document.createElement('li');
      const mb = (a.size_in_bytes / 1048576).toFixed(1);
      li.innerHTML = `<span>📦 ${esc(a.name)}</span><span class="size">${mb} MB</span>`;
      const btn = document.createElement('button');
      btn.className = 'btn small primary';
      btn.textContent = '下载';
      btn.addEventListener('click', () => downloadArtifact(a));
      li.appendChild(btn);
      ul.appendChild(li);
    }
    if (arts.length === 0) {
      wrap.hidden = false;
      ul.innerHTML = '<li>没有可用产物(可能已过期或为演练任务)</li>';
    }
  } catch { /* 忽略 */ }
}

async function downloadArtifact(a) {
  try {
    const res = await api(`/repos/${OWNER}/${REPO}/actions/artifacts/${a.id}/zip`);
    if (!res.ok) throw new Error(`下载失败: HTTP ${res.status}`);
    const blob = await res.blob();
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = `${a.name}.zip`;
    document.body.appendChild(link);
    link.click();
    link.remove();
    setTimeout(() => URL.revokeObjectURL(url), 60000);
  } catch (e) {
    alert('浏览器直接下载失败, 请点击「在 GitHub 打开」到 Actions 页面下载产物。(' + e.message + ')');
  }
}

/* ---------- 取消 ---------- */
async function cancelRun() {
  if (!state.curRunId) return;
  try {
    await apiJson(`/repos/${OWNER}/${REPO}/actions/runs/${state.curRunId}/cancel`, { method: 'POST' });
    $('cancel-btn').hidden = true;
  } catch (e) {
    alert('取消失败: ' + e.message);
  }
}

/* ---------- 历史 ---------- */
async function renderHistory() {
  const ul = $('history');
  ul.innerHTML = '<li class="hint">加载中…</li>';
  try {
    const data = await apiJson(`/repos/${OWNER}/${REPO}/actions/runs?event=workflow_dispatch&per_page=6`);
    const runs = data.workflow_runs || [];
    ul.innerHTML = '';
    if (runs.length === 0) { ul.innerHTML = '<li class="hint">暂无构建记录</li>'; return; }
    for (const r of runs) {
      const li = document.createElement('li');
      const a = document.createElement('a');
      a.textContent = `#${r.run_number} · ${conclusionText(r.conclusion) || r.status}`;
      a.addEventListener('click', () => { state.curDeviceLabel = `运行 #${r.run_number}`; attachRun(r.id); $('progress-card').scrollIntoView({ behavior: 'smooth' }); });
      const when = document.createElement('span');
      when.className = 'when';
      when.textContent = new Date(r.created_at).toLocaleString();
      li.appendChild(a);
      li.appendChild(when);
      ul.appendChild(li);
    }
  } catch (e) {
    ul.innerHTML = `<li class="hint">加载失败: ${esc(e.message)}</li>`;
  }
}

async function autoResume() {
  try {
    const data = await apiJson(`/repos/${OWNER}/${REPO}/actions/runs?event=workflow_dispatch&per_page=1`);
    const run = (data.workflow_runs || [])[0];
    if (run && (run.status === 'in_progress' || run.status === 'queued')) {
      state.curDeviceLabel = `运行 #${run.run_number}`;
      attachRun(run.id);
    }
  } catch { /* 忽略 */ }
}

/* ---------- 工具 ---------- */
function sleep(ms) { return new Promise((r) => setTimeout(r, ms)); }
function esc(s) { return String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c])); }
function setMsg(text, isErr) { const m = $('build-msg'); m.textContent = text; m.style.color = isErr ? 'var(--red)' : ''; }
function stopPolling() { if (state.pollTimer) { clearInterval(state.pollTimer); state.pollTimer = null; } }

document.addEventListener('DOMContentLoaded', init);
