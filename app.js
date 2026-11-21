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
  lastLogText: '',
  logWaiting: false,
  logBusy: false,
  logFollow: true,
  pollCount: 0,
  etags: {},       // path -> { etag, data }: 304 条件请求不计入限速额度
  errBackoff: 0,   // 连续出错次数(指数退避)
  pollMs: 10000,   // 轮询间隔(正常 10 秒)
};

/* ---------- API(带限速诊断 + ETag 条件请求) ---------- */
class ApiError extends Error {
  constructor(message, { status, kind = 'http', waitMs = 0 } = {}) {
    super(message);
    this.status = status;
    this.kind = kind;      // ratelimit | secondary | auth | network | http
    this.waitMs = waitMs;  // 建议等待时间(毫秒)
  }
}

function rateLimitHint(res) {
  const remaining = res.headers.get('x-ratelimit-remaining');
  const reset = res.headers.get('x-ratelimit-reset');
  const retryAfter = res.headers.get('retry-after');
  if (remaining === '0' && reset) {
    return { kind: 'ratelimit', waitMs: Math.max(30000, new Date(Number(reset) * 1000).getTime() - Date.now() + 5000) };
  }
  if (retryAfter && Number(retryAfter) > 0) return { kind: 'secondary', waitMs: Math.max(30000, Number(retryAfter) * 1000) };
  return { kind: 'secondary', waitMs: 60000 };
}

async function api(path, opts = {}) {
  const headers = { Accept: 'application/vnd.github+json' };
  if (state.token) headers.Authorization = `Bearer ${state.token}`;
  let res;
  try {
    res = await fetch(`${API}${path}`, { ...opts, headers: { ...headers, ...(opts.headers || {}) } });
  } catch (e) {
    throw new ApiError(`网络请求失败: ${e.message}`, { kind: 'network', waitMs: 5000 });
  }
  if (res.status === 401) {
    throw new ApiError('Token 无效或已过期, 请在页面顶部重新保存(需要 repo + workflow 权限)。', { status: 401, kind: 'auth' });
  }
  if (res.status === 403 || res.status === 429) {
    const rl = rateLimitHint(res);
    const mins = Math.max(1, Math.ceil(rl.waitMs / 60000));
    throw new ApiError(
      rl.kind === 'ratelimit'
        ? `GitHub API 请求额度已用尽(5000 次/小时), 约 ${mins} 分钟后自动恢复, 期间会暂停轮询。`
        : `GitHub 触发二级限速(同一 Token 请求过快), 约 ${mins} 分钟内自动退避重试。`,
      { status: res.status, kind: rl.kind, waitMs: rl.waitMs },
    );
  }
  return res;
}

async function apiJson(path, opts = {}) {
  const isGet = !opts.method || opts.method === 'GET';
  const cacheKey = isGet ? path : null;
  const cached = cacheKey ? state.etags[cacheKey] : null;
  const reqOpts = { ...opts };
  if (cached) reqOpts.headers = { ...(reqOpts.headers || {}), 'If-None-Match': cached.etag };
  const res = await api(path, reqOpts);
  if (res.status === 304 && cached) return cached.data;
  if (res.status === 204) return null;
  const text = await res.text();
  let data = null;
  try { data = JSON.parse(text); } catch { data = text; }
  if (!res.ok) throw new ApiError(`GitHub API ${res.status}: ${(data && data.message) || text}`, { status: res.status });
  if (cacheKey) {
    const etag = res.headers.get('etag');
    if (etag) state.etags[cacheKey] = { etag, data };
  }
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
  $('version').addEventListener('change', updateActionButtons);
  $('custom-mode').addEventListener('change', toggleCustom);
  const logBox = $('log');
  logBox.addEventListener('scroll', () => {
    state.logFollow = logBox.scrollHeight - logBox.scrollTop - logBox.clientHeight < 60;
    $('log-follow').textContent = state.logFollow ? '跟随更新' : '已暂停跟随(滚动到底部恢复)';
  });

  try {
    const res = await fetch('devices.json', { cache: 'no-store' });
    const buf = await res.arrayBuffer();
    let text;
    if (buf.byteLength >= 2 && buf[0] === 0xFF && buf[1] === 0xFE) {
      text = new TextDecoder('utf-16le').decode(buf);           // 防御: PowerShell 重定向写入的 UTF-16LE
    } else {
      text = new TextDecoder('utf-8').decode(buf);
    }
    text = text.replace(/^\uFEFF/, '');
    const data = JSON.parse(text);
    state.devices = data.devices;
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
function deviceLabel(d) {
  const en = d.brand && d.model ? `${d.brand} ${d.model}` : d.display;
  // 优先显示中文型号, 括号内是机型代码; 英文名放进 title 供悬停查看
  return {
    text: d.zh ? `${d.zh} (${d.id})` : `${en} (${d.id})`,
    title: d.zh ? `${d.id} · ${en}` : `${d.id}`,
  };
}

// 按搜索词重建设备下拉(顺序沿用 devices.json 里的中文名排序)
function fillDeviceOptions(keyword) {
  const sel = $('device');
  const keep = sel.value;
  const kw = (keyword || '').trim().toLowerCase();
  const list = state.devices.filter((d) => {
    if (!kw) return true;
    const hay = [d.zh, d.id, d.display, d.brand, d.model].filter(Boolean).join(' ').toLowerCase();
    return hay.includes(kw);
  });
  sel.innerHTML = '';
  for (const d of list) {
    const { text, title } = deviceLabel(d);
    const o = document.createElement('option');
    o.value = d.id;
    o.textContent = text;
    o.title = title;
    sel.appendChild(o);
  }
  if (keep && list.some((d) => d.id === keep)) sel.value = keep;
  else if (list.length) sel.value = list[0].id;
  renderVersions();
}

function renderDevices() {
  fillDeviceOptions('');
  const filter = $('device-filter');
  if (filter) {
    filter.addEventListener('input', (e) => fillDeviceOptions(e.target.value));
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
    o.textContent = `${i + 1}. ${v.label}${v.unsupported ? ' ⚠ 不支持' : ''}`;
    sel.appendChild(o);
  });
  const v = dev.versions[0];
  // 按设备类型预选集成分支: GKI → main, 传统内核 → builtin (用户仍可手动改)
  $('ksu-branch').value = v && v.gki == 1 ? 'main' : 'builtin';
  const zhLine = dev.zh ? `中文型号: <b>${esc(dev.zh)}</b> · ` : '';
  $('device-info').innerHTML = v
    ? `${zhLine}机型代码: <code>${esc(dev.id)}</code> · 仓库: <code>${v.repo}</code> · 分支: <code>${v.branch}</code> · defconfig: <code>${v.defconfig || '自动探测'}</code> · 内核: Linux ${v.kver}${v.gki == 1 ? ' · GKI' : ''}${v.unsupported ? ' · <b style="color:#f59e0b">⚠ 该内核版本不受支持(仅编译演练)</b>' : ''}`
    : '';
  updateActionButtons();
}

function selectedVersion() {
  const id = $('device').value;
  const dev = state.devices.find((d) => d.id === id);
  if (!dev) return null;
  const idx = parseInt($('version').value, 10) - 1;
  return dev.versions[idx] || dev.versions[0] || null;
}

function updateActionButtons() {
  const v = $('custom-mode').checked ? null : selectedVersion();
  const bad = !!(v && v.unsupported);
  $('build-btn').disabled = bad;
  $('dry-run-btn').disabled = false;
  if (bad) setMsg('该设备/内核版本不受 SukiSU-Ultra 支持(Linux 3.x 仅可演练), 请改选其它版本。', true);
}

function toggleCustom() {
  const on = $('custom-mode').checked;
  $('custom-fields').hidden = !on;
  $('device').disabled = on;
  $('version').disabled = on;
  if (on) {
    $('ksu-branch').value = '';
  } else {
    renderVersions();
  }
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
    state.lastLogText = '';
    state.logWaiting = false;
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
    susfs: String($('susfs').checked),
    jobs: $('jobs').value.trim(),
    clean: String($('clean').checked),
    custom_repo: custom ? $('custom-repo').value.trim() : '',
    custom_branch: custom ? $('custom-branch').value.trim() : '',
    custom_defconfig: custom ? $('custom-defconfig').value.trim() : '',
    custom_kver: custom ? $('custom-kver').value.trim() : '',
    custom_android: custom ? $('custom-android').value.trim() : '',
    custom_gki: custom ? String($('custom-gki').checked) : 'false',
    publish: String($('publish').checked),
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

/* ---------- 运行状态轮询(自调度 + 限速/错误退避) ---------- */
async function attachRun(runId) {
  stopPolling();
  state.curRunId = runId;
  $('progress-card').hidden = false;
  state.lastLogText = '';
  state.logWaiting = false;
  state.logBusy = false;
  state.errBackoff = 0;
  state.etags = {};
  $('log').textContent = '';
  $('artifacts').hidden = true;
  $('cancel-btn').hidden = true;
  showRunError('');
  state.pollCount = 0;
  await tick();
}

function scheduleTick(ms) {
  stopPolling();
  // 标签页不可见时降频(60 秒), 避免长时间挂后台把 API 额度耗尽; 回到前台立即刷新
  const delay = document.hidden ? Math.max(60000, ms) : Math.max(3000, ms);
  state.pollTimer = setTimeout(tick, delay);
}

document.addEventListener('visibilitychange', () => {
  if (!document.hidden && state.curRunId && !state.pollTimer) tick();
});

function showRunError(text) {
  const el = $('run-error');
  if (!el) return;
  if (!text) { el.hidden = true; el.textContent = ''; return; }
  el.hidden = false;
  el.textContent = text;
}

async function tick() {
  state.pollTimer = null;
  const runId = state.curRunId;
  if (!runId) return;
  try {
    const run = await apiJson(`/repos/${OWNER}/${REPO}/actions/runs/${runId}`);
    if (state.curRunId !== runId) return;
    renderRun(run);
    const jobs = await apiJson(`/repos/${OWNER}/${REPO}/actions/runs/${runId}/jobs`);
    if (state.curRunId !== runId) return;
    const jobList = jobs.jobs || [];
    renderSteps(jobList);
    // job 对象不带 logs_url 字段, 按 job.id 构造日志端点
    const jobLogsUrl = jobList.length ? `${API}/repos/${OWNER}/${REPO}/actions/jobs/${jobList[0].id}/logs` : null;
    showRunError('');
    state.errBackoff = 0;
    if (run.status === 'in_progress' || run.status === 'queued') {
      if (!state.logBusy && !document.hidden) refreshLog(run, jobLogsUrl);
      scheduleTick(state.pollMs);
    } else if (run.status === 'completed') {
      stopPolling();
      await refreshLog(run, jobLogsUrl, true);
      await renderArtifacts(run);
      $('cancel-btn').hidden = true;
      await renderHistory();
    }
  } catch (e) {
    if (state.curRunId !== runId) return;
    $('run-status-badge').textContent = '轮询出错';
    $('run-status-badge').className = 'badge failure';
    if (e.status === 404) {
      stopPolling();
      showRunError(`${e.message}\n该运行可能已被删除或仓库无权访问; 请刷新页面查看「最近构建」列表。`);
      return;
    }
    if (e.kind === 'ratelimit' || e.kind === 'secondary') {
      const next = new Date(Date.now() + e.waitMs);
      showRunError(`${e.message}\n下次自动重试: ${next.toLocaleTimeString()}`);
      scheduleTick(e.waitMs);
    } else {
      state.errBackoff = Math.min((state.errBackoff || 0) + 1, 5);
      const ladder = [5000, 10000, 20000, 40000, 60000];
      const waitMs = ladder[state.errBackoff - 1] || 60000;
      showRunError(`${e.message}\n第 ${state.errBackoff} 次失败, ${Math.round(waitMs / 1000)} 秒后重试(可点右上角「在 GitHub 打开」查看)。`);
      scheduleTick(waitMs);
    }
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
    // GitHub 步骤状态: completed+success / completed+skipped / completed+failure /
    // in_progress / queued。skipped 表示前序步骤失败被跳过, 不是本步骤出错。
    let cls, txt;
    if (s.status === 'completed') {
      if (s.conclusion === 'success') { cls = 'ok'; txt = '完成'; }
      else if (s.conclusion === 'skipped') { cls = 'skip'; txt = '已跳过'; }
      else { cls = 'fail'; txt = `失败(${s.conclusion})`; }
    } else if (s.status === 'in_progress') { cls = 'run'; txt = '进行中'; }
    else { cls = 'queued'; txt = '等待中'; }
    tr.innerHTML = `<td>${esc(s.name)}</td>
      <td><span class="step-status"><span class="dot ${cls}"></span>${esc(txt)}</span></td>
      <td>${esc(duration(s.started_at, s.completed_at))}</td>`;
    tb.appendChild(tr);
  }
  const failed = steps.find((s) => s.status === 'completed' && s.conclusion === 'failure');
  if (failed) {
    const tr = document.createElement('tr');
    tr.innerHTML = `<td colspan="3" class="step-note">步骤「${esc(failed.name)}」失败, 其后步骤已自动跳过(非上传/打包本身出错)。</td>`;
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

/* ---------- 实时日志(轮询 job 级日志端点) ----------
 * 实测 GitHub API 行为:
 *  - run 级 /logs: 进行中返回 404, 结束后返回 zip(不便于展示)
 *  - job 级 /logs: 302 跳转到 Azure blob 的 job-logs.txt(签名 URL, 无需鉴权),
 *    进行中该 blob 会逐渐增长, 结束后返回完整 text/plain —— 用它最稳 */
async function refreshLog(run, jobLogsUrl, isFinal) {
  if (state.logBusy) return;
  state.logBusy = true;
  try {
    const url = jobLogsUrl || run.logs_url;
    if (!url) { state.logBusy = false; return; }
    const h = { Accept: 'application/vnd.github+json' };
    if (state.token) h.Authorization = `Bearer ${state.token}`;
    const res = await fetch(url, { headers: h });
    const ct = res.headers.get('content-type') || '';
    if (ct.includes('zip') || ct.includes('octet-stream')) {
      // 极端情况: job 级也返回 zip —— 放弃解析
      if (!$('log').textContent) $('log').textContent = '(日志为压缩包格式, 请点右上角「在 GitHub 打开」查看。)';
      state.logBusy = false;
      return;
    }
    if (!res.ok) {
      // 进行中时 blob 可能尚未生成(404), 安静重试
      if (!isFinal && !state.logWaiting && !$('log').textContent) {
        state.logWaiting = true;
        $('log').textContent = '(构建日志尚未生成, 自动每 10 秒重试…)\n';
      } else if (isFinal && !$('log').textContent) {
        $('log').textContent = '(无法获取日志, 请点右上角「在 GitHub 打开」查看。)';
      }
      state.logBusy = false;
      if (!isFinal) setTimeout(() => { if (state.curRunId === run.id) refreshLog(run, jobLogsUrl); }, 10000);
      return;
    }
    const text = await res.text();
    if (text && text !== state.lastLogText) {
      state.lastLogText = text;
      state.logWaiting = false;
      const lines = text.split('\n');
      $('log').textContent = (lines.length > 300 ? '...(已截断, 仅显示末尾 300 行)\n' : '') + lines.slice(-300).join('\n');
      if (state.logFollow) $('log').scrollTop = $('log').scrollHeight;
    }
    state.logBusy = false;
    if (!isFinal && (run.status === 'in_progress' || run.status === 'queued')) {
      setTimeout(() => { if (state.curRunId === run.id) refreshLog(run, jobLogsUrl); }, 10000);
    } else if (isFinal && !$('log').textContent) {
      $('log').textContent = '(日志为空, 请点右上角「在 GitHub 打开」查看。)';
    }
  } catch {
    state.logBusy = false;
    if (!isFinal) setTimeout(() => { if (state.curRunId === run.id) refreshLog(run, jobLogsUrl); }, 10000);
  }
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
      ul.innerHTML = '<li>没有可用产物(可能已过期、为演练任务, 或编译失败)</li>';
    }
    // 自动发布提示: 产物同时发布到 Release 页
    const relHint = $('release-hint');
    if (relHint) {
      relHint.hidden = arts.length === 0;
      relHint.querySelector('a').href = `https://github.com/${OWNER}/${REPO}/releases`;
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
function stopPolling() { if (state.pollTimer) { clearTimeout(state.pollTimer); state.pollTimer = null; } }

document.addEventListener('DOMContentLoaded', init);
