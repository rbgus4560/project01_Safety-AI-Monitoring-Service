# 프로젝트 여러 곳에서 함께 사용하는 보조 코드 파일입니다.
# 상수, 스키마, 로그 같은 공통 흐름을 담고 있습니다.

from __future__ import annotations

from fastapi.responses import HTMLResponse


def build_dashboard_html() -> HTMLResponse:
    return HTMLResponse(
        """
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Safety Monitor Client</title>
  <style>
    :root {
      --bg: #0c1117;
      --panel: #121a24;
      --panel-2: #182231;
      --line: #293548;
      --text: #eef4fb;
      --muted: #97a7bb;
      --accent: #4fc3a1;
      --warn: #f3b74f;
      --danger: #f06b6b;
      --info: #6fb5ff;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      font-family: "Segoe UI", "Pretendard", sans-serif;
      background:
        radial-gradient(circle at top right, rgba(79, 195, 161, 0.15), transparent 28%),
        radial-gradient(circle at top left, rgba(111, 181, 255, 0.12), transparent 24%),
        var(--bg);
      color: var(--text);
    }
    .page {
      max-width: 1480px;
      margin: 0 auto;
      padding: 28px;
    }
    .hero {
      display: grid;
      grid-template-columns: 2fr 1fr;
      gap: 18px;
      margin-bottom: 18px;
    }
    .card {
      background: linear-gradient(180deg, rgba(255,255,255,0.03), transparent), var(--panel);
      border: 1px solid var(--line);
      border-radius: 20px;
      padding: 18px;
      box-shadow: 0 16px 40px rgba(0, 0, 0, 0.25);
    }
    .eyebrow {
      color: var(--accent);
      font-size: 12px;
      letter-spacing: 0.14em;
      text-transform: uppercase;
      margin-bottom: 10px;
    }
    h1, h2, h3, p { margin: 0; }
    h1 {
      font-size: 34px;
      line-height: 1.08;
      margin-bottom: 10px;
    }
    .sub {
      color: var(--muted);
      line-height: 1.6;
      max-width: 72ch;
    }
    .chips, .stats {
      display: flex;
      flex-wrap: wrap;
      gap: 10px;
      margin-top: 16px;
    }
    .chip, .pill {
      padding: 8px 12px;
      border-radius: 999px;
      border: 1px solid var(--line);
      background: rgba(255,255,255,0.03);
      color: var(--text);
      font-size: 13px;
    }
    .stats {
      display: grid;
      grid-template-columns: repeat(4, 1fr);
      gap: 12px;
    }
    .stat {
      background: var(--panel-2);
      border: 1px solid var(--line);
      border-radius: 16px;
      padding: 14px;
    }
    .stat .label {
      color: var(--muted);
      font-size: 12px;
      margin-bottom: 8px;
      text-transform: uppercase;
      letter-spacing: 0.1em;
    }
    .stat .value {
      font-size: 26px;
      font-weight: 700;
    }
    .layout {
      display: grid;
      grid-template-columns: 420px 1fr;
      gap: 18px;
    }
    .stack {
      display: grid;
      gap: 18px;
    }
    .form-grid {
      display: grid;
      gap: 12px;
    }
    .two-col {
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 12px;
    }
    label {
      display: grid;
      gap: 8px;
      color: var(--muted);
      font-size: 13px;
    }
    input, select, button, textarea {
      font: inherit;
    }
    input, select, textarea {
      width: 100%;
      background: #0f1620;
      color: var(--text);
      border: 1px solid var(--line);
      border-radius: 14px;
      padding: 12px 14px;
    }
    button {
      border: 0;
      border-radius: 14px;
      padding: 12px 14px;
      cursor: pointer;
      font-weight: 600;
      transition: transform 120ms ease, opacity 120ms ease;
    }
    button:hover { transform: translateY(-1px); }
    button:disabled { opacity: 0.5; cursor: default; transform: none; }
    .btn-primary { background: var(--accent); color: #062119; }
    .btn-secondary { background: #223044; color: var(--text); }
    .btn-danger { background: var(--danger); color: white; }
    .toolbar {
      display: flex;
      gap: 10px;
      flex-wrap: wrap;
      margin-top: 14px;
    }
    table {
      width: 100%;
      border-collapse: collapse;
    }
    th, td {
      text-align: left;
      padding: 12px 10px;
      border-bottom: 1px solid rgba(255,255,255,0.06);
      vertical-align: top;
      font-size: 14px;
    }
    th {
      color: var(--muted);
      font-weight: 600;
      font-size: 12px;
      letter-spacing: 0.08em;
      text-transform: uppercase;
    }
    .table-wrap {
      overflow: auto;
      border-radius: 16px;
      border: 1px solid var(--line);
      margin-top: 14px;
    }
    .row-actions {
      display: flex;
      gap: 8px;
      flex-wrap: wrap;
    }
    .mini {
      padding: 7px 10px;
      border-radius: 10px;
      font-size: 12px;
    }
    .status {
      display: inline-flex;
      align-items: center;
      gap: 8px;
      padding: 7px 10px;
      border-radius: 999px;
      font-size: 12px;
      border: 1px solid var(--line);
      background: rgba(255,255,255,0.03);
      white-space: nowrap;
    }
    .dot {
      width: 8px;
      height: 8px;
      border-radius: 50%;
      background: var(--muted);
    }
    .status.running .dot { background: var(--accent); }
    .status.error .dot { background: var(--danger); }
    .status.waiting .dot { background: var(--warn); }
    .status.idle .dot { background: var(--info); }
    .muted {
      color: var(--muted);
    }
    .section-title {
      display: flex;
      justify-content: space-between;
      align-items: center;
      gap: 12px;
      margin-bottom: 8px;
    }
    .helper {
      color: var(--muted);
      font-size: 13px;
      line-height: 1.5;
      margin-top: 8px;
    }
    .notice {
      border-left: 3px solid var(--info);
      padding-left: 12px;
    }
    .flash {
      margin-top: 12px;
      padding: 12px 14px;
      border-radius: 14px;
      font-size: 13px;
      display: none;
    }
    .flash.ok { display: block; background: rgba(79,195,161,0.12); color: #baf1e2; }
    .flash.error { display: block; background: rgba(240,107,107,0.12); color: #ffd4d4; }
    .events {
      display: grid;
      gap: 10px;
      margin-top: 14px;
    }
    .event-card {
      border: 1px solid var(--line);
      border-radius: 16px;
      padding: 14px;
      background: rgba(255,255,255,0.03);
    }
    .event-card strong {
      display: inline-block;
      margin-bottom: 6px;
    }
    code {
      font-family: "Cascadia Code", Consolas, monospace;
      font-size: 12px;
      color: #cbe4ff;
    }
    @media (max-width: 1100px) {
      .hero, .layout, .stats, .two-col { grid-template-columns: 1fr; }
      .page { padding: 18px; }
    }
  </style>
</head>
<body>
  <div class="page">
    <section class="hero">
      <div class="card">
        <div class="eyebrow">Local Analysis Client</div>
        <h1>Own the weights locally, analyze locally, report to the server.</h1>
        <p class="sub">
          This client is the operator-facing console for source registration and runtime control.
          Local video files, YOLO weights, TensorRT engines, and GPU inference all stay on this machine.
          Only detections, events, runtime status, and event clips are pushed to the server.
        </p>
        <div class="chips">
          <div class="chip" id="remoteServerChip">Server: loading...</div>
          <div class="chip" id="modelChip">Model: loading...</div>
          <div class="chip" id="engineChip">Engine: loading...</div>
          <div class="chip" id="deviceChip">Device: loading...</div>
        </div>
      </div>
      <div class="card">
        <div class="eyebrow">Runtime Snapshot</div>
        <div class="stats">
          <div class="stat">
            <div class="label">Sources</div>
            <div class="value" id="sourcesCount">0</div>
          </div>
          <div class="stat">
            <div class="label">Running</div>
            <div class="value" id="runningCount">0</div>
          </div>
          <div class="stat">
            <div class="label">Events</div>
            <div class="value" id="eventsCount">0</div>
          </div>
          <div class="stat">
            <div class="label">Errors</div>
            <div class="value" id="errorCount">0</div>
          </div>
        </div>
        <p class="helper notice" id="healthSummary" style="margin-top: 16px;">Checking local client health...</p>
      </div>
    </section>

    <section class="layout">
      <div class="stack">
        <div class="card">
          <div class="section-title">
            <div>
              <div class="eyebrow">Register Source</div>
              <h2>Add a local file, stream, or camera</h2>
            </div>
          </div>
          <div class="form-grid">
            <label>
              Source Type
              <select id="sourceType">
                <option value="video">Local Video File</option>
                <option value="stream">RTSP / HTTP Stream</option>
                <option value="camera">Camera Index</option>
              </select>
            </label>
            <div id="videoInputBlock">
              <label>
                Select Video File
                <input id="videoFile" type="file" accept=".mp4,.mov,.avi,.mkv,video/*">
              </label>
            </div>
            <div id="streamInputBlock" style="display:none;">
              <label>
                Stream URL
                <input id="streamValue" type="text" placeholder="rtsp://127.0.0.1:8554/live">
              </label>
            </div>
            <div id="cameraInputBlock" style="display:none;">
              <label>
                Camera Index
                <input id="cameraValue" type="number" min="0" step="1" value="0">
              </label>
            </div>
            <div class="two-col">
              <label>
                Client ID
                <input id="clientId" type="text" placeholder="client-01">
              </label>
              <label>
                Session ID
                <input id="sessionId" type="text" placeholder="Leave blank to auto-generate">
              </label>
            </div>
            <div class="toolbar">
              <button class="btn-primary" id="registerBtn">Register on Client</button>
              <button class="btn-secondary" id="refreshBtn">Refresh Dashboard</button>
            </div>
            <p class="helper">
              Local files are registered on this client. Analysis output is then mirrored to the server automatically.
            </p>
            <div class="flash" id="flash"></div>
          </div>
        </div>

        <div class="card">
          <div class="eyebrow">What This UI Covers</div>
          <h2>Operator UX checklist</h2>
          <div class="events">
            <div class="event-card">
              <strong>Source registration</strong>
              <div class="muted">Local file upload, stream URL entry, and camera index entry are handled here.</div>
            </div>
            <div class="event-card">
              <strong>Runtime control</strong>
              <div class="muted">Start, stop, restart, and delete controls are available per source below.</div>
            </div>
            <div class="event-card">
              <strong>Inference ownership</strong>
              <div class="muted">The UI surfaces where the weights and TensorRT engine live so operators know this machine owns inference.</div>
            </div>
          </div>
        </div>
      </div>

      <div class="stack">
        <div class="card">
          <div class="section-title">
            <div>
              <div class="eyebrow">Registered Sources</div>
              <h2>Local analysis sessions</h2>
            </div>
            <div class="pill" id="autoRefreshStatus">Auto refresh: 5s</div>
          </div>
          <div class="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>Source</th>
                  <th>Status</th>
                  <th>Progress</th>
                  <th>Actions</th>
                </tr>
              </thead>
              <tbody id="sourcesTable">
                <tr><td colspan="4" class="muted">Loading sources...</td></tr>
              </tbody>
            </table>
          </div>
        </div>

        <div class="card">
          <div class="section-title">
            <div>
              <div class="eyebrow">Latest Events</div>
              <h2>Recent analysis outcomes</h2>
            </div>
          </div>
          <div class="events" id="eventsList">
            <div class="event-card muted">Loading events...</div>
          </div>
        </div>
      </div>
    </section>
  </div>

  <script>
    const flash = document.getElementById('flash');
    const sourceType = document.getElementById('sourceType');
    const videoInputBlock = document.getElementById('videoInputBlock');
    const streamInputBlock = document.getElementById('streamInputBlock');
    const cameraInputBlock = document.getElementById('cameraInputBlock');
    const registerBtn = document.getElementById('registerBtn');
    const refreshBtn = document.getElementById('refreshBtn');

    function setFlash(message, kind = 'ok') {
      flash.className = `flash ${kind}`;
      flash.textContent = message;
    }

    function clearFlash() {
      flash.className = 'flash';
      flash.textContent = '';
    }

    function escapeHtml(text) {
      return String(text ?? '')
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
    }

    function updateSourceInputs() {
      const mode = sourceType.value;
      videoInputBlock.style.display = mode === 'video' ? 'block' : 'none';
      streamInputBlock.style.display = mode === 'stream' ? 'block' : 'none';
      cameraInputBlock.style.display = mode === 'camera' ? 'block' : 'none';
    }

    function statusClass(status) {
      const normalized = String(status || '').toLowerCase();
      if (normalized.includes('error')) return 'error';
      if (normalized.includes('running') || normalized.includes('processing') || normalized.includes('reconnecting') || normalized.includes('starting')) return 'running';
      if (normalized.includes('registered') || normalized.includes('stopped')) return 'waiting';
      return 'idle';
    }

    function progressText(source, status) {
      if (!status) return '-';
      const duration = Number(source?.source_duration_seconds || status?.source_duration_seconds || 0);
      const current = Number(status?.last_source_time_seconds || 0);
      if (duration > 0) {
        const percent = Math.max(0, Math.min(100, (current / duration) * 100));
        return `${current.toFixed(1)} / ${duration.toFixed(1)}s (${percent.toFixed(1)}%)`;
      }
      if (current > 0) return `${current.toFixed(1)}s`;
      return '-';
    }

    async function getJson(url, options) {
      const response = await fetch(url, options);
      if (!response.ok) {
        throw new Error(`${response.status} ${response.statusText}`);
      }
      return response.json();
    }

    async function postAction(url, options = {}) {
      try {
        await fetch(url, { method: 'POST', ...options });
        await refreshDashboard();
      } catch (error) {
        setFlash(`Action failed: ${error.message}`, 'error');
      }
    }

    async function deleteSource(sourceKey) {
      if (!confirm(`Delete source\\n\\n${sourceKey}\\n\\nand clear local data?`)) return;
      try {
        const encoded = encodeURIComponent(sourceKey);
        const response = await fetch(`/api/sources/${encoded}?clear_data=true`, { method: 'DELETE' });
        if (!response.ok) throw new Error(`${response.status} ${response.statusText}`);
        setFlash('Source deleted.');
        await refreshDashboard();
      } catch (error) {
        setFlash(`Delete failed: ${error.message}`, 'error');
      }
    }

    async function registerSource() {
      clearFlash();
      registerBtn.disabled = true;
      try {
        const type = sourceType.value;
        const clientId = document.getElementById('clientId').value.trim();
        const sessionId = document.getElementById('sessionId').value.trim();

        if (type === 'video') {
          const fileInput = document.getElementById('videoFile');
          const file = fileInput.files[0];
          if (!file) throw new Error('Choose a local video file first.');
          const form = new FormData();
          form.append('file', file);
          form.append('client_id', clientId);
          form.append('session_id', sessionId);
          form.append('reset_existing', 'true');
          form.append('start_immediately', 'true');
          const response = await fetch('/api/sources/upload', { method: 'POST', body: form });
          if (!response.ok) throw new Error(`${response.status} ${response.statusText}`);
        } else {
          const sourceValue = type === 'stream'
            ? document.getElementById('streamValue').value.trim()
            : document.getElementById('cameraValue').value.trim();
          if (!sourceValue) throw new Error('Provide a source value.');
          const response = await fetch('/api/sources', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
              source_type: type,
              source_value: sourceValue,
              client_id: clientId,
              session_id: sessionId,
              reset_existing: true,
              start_immediately: true
            })
          });
          if (!response.ok) throw new Error(`${response.status} ${response.statusText}`);
        }

        setFlash('Source registered on the client and queued for local analysis.');
        document.getElementById('streamValue').value = '';
        await refreshDashboard();
      } catch (error) {
        setFlash(error.message, 'error');
      } finally {
        registerBtn.disabled = false;
      }
    }

    async function refreshDashboard() {
      try {
        const [health, sources, statuses, events, config] = await Promise.all([
          getJson('/health'),
          getJson('/api/sources'),
          getJson('/api/source-status'),
          getJson('/api/events/latest?limit=12'),
          getJson('/api/client/config')
        ]);

        document.getElementById('healthSummary').textContent =
          `Client health: ${health.status} | Local DB: ${health.event_log_path}`;
        document.getElementById('remoteServerChip').textContent = `Server: ${config.remote_server_base_url}`;
        document.getElementById('modelChip').textContent =
          `Weights: ${config.model_exists ? 'ready' : 'missing'} (${config.model_path.split('\\\\').slice(-1)[0]})`;
        document.getElementById('engineChip').textContent =
          `TensorRT: ${config.engine_exists ? 'ready' : 'not built'} (${config.engine_path.split('\\\\').slice(-1)[0]})`;
        document.getElementById('deviceChip').textContent = `Device: ${config.analysis_device}`;

        const sourceItems = sources.items || [];
        const statusItems = statuses.items || [];
        const statusMap = Object.fromEntries(statusItems.map((item) => [item.source_key, item]));
        const eventItems = events.items || [];

        document.getElementById('sourcesCount').textContent = String(sourceItems.length);
        document.getElementById('runningCount').textContent = String(statusItems.filter((item) => item.is_running).length);
        document.getElementById('eventsCount').textContent = String(eventItems.length);
        document.getElementById('errorCount').textContent = String(statusItems.filter((item) => String(item.error_message || '').trim().length > 0).length);

        const sourcesTable = document.getElementById('sourcesTable');
        if (sourceItems.length === 0) {
          sourcesTable.innerHTML = '<tr><td colspan="4" class="muted">No sources registered on this client yet.</td></tr>';
        } else {
          sourcesTable.innerHTML = sourceItems.map((source) => {
            const status = statusMap[source.source_key];
            const label = escapeHtml(source.source_slug || source.source_key);
            const detail = escapeHtml(source.original_source_value || source.source_value);
            const state = escapeHtml(status?.state || 'registered');
            const stateClass = statusClass(status?.state);
            const progress = escapeHtml(progressText(source, status));
            const sourceKey = JSON.stringify(source.source_key);
            return `
              <tr>
                <td>
                  <strong>${label}</strong><br>
                  <span class="muted">${escapeHtml(source.source_type)}</span><br>
                  <code>${detail}</code>
                </td>
                <td>
                  <span class="status ${stateClass}">
                    <span class="dot"></span>${state}
                  </span>
                  ${status?.error_message ? `<div class="helper" style="color:#ffd4d4;margin-top:8px;">${escapeHtml(status.error_message)}</div>` : ''}
                </td>
                <td>${progress}</td>
                <td>
                  <div class="row-actions">
                    <button class="mini btn-secondary" onclick='postAction("/api/sources/" + encodeURIComponent(${sourceKey}) + "/start")'>Start</button>
                    <button class="mini btn-secondary" onclick='postAction("/api/sources/" + encodeURIComponent(${sourceKey}) + "/stop")'>Stop</button>
                    <button class="mini btn-secondary" onclick='postAction("/api/sources/" + encodeURIComponent(${sourceKey}) + "/restart")'>Restart</button>
                    <button class="mini btn-danger" onclick='deleteSource(${sourceKey})'>Delete</button>
                  </div>
                </td>
              </tr>
            `;
          }).join('');
        }

        const eventsList = document.getElementById('eventsList');
        if (eventItems.length === 0) {
          eventsList.innerHTML = '<div class="event-card muted">No recent events yet.</div>';
        } else {
          eventsList.innerHTML = eventItems.slice().reverse().map((item) => `
            <div class="event-card">
              <strong>${escapeHtml(item.event_type || 'event')}</strong>
              <div class="muted">${escapeHtml(item.status || '-')} · ${escapeHtml(item.source_key || '-')}</div>
              <div class="helper">${escapeHtml(item.message || item.title || '')}</div>
            </div>
          `).join('');
        }
      } catch (error) {
        setFlash(`Refresh failed: ${error.message}`, 'error');
      }
    }

    sourceType.addEventListener('change', updateSourceInputs);
    registerBtn.addEventListener('click', registerSource);
    refreshBtn.addEventListener('click', refreshDashboard);

    updateSourceInputs();
    refreshDashboard();
    setInterval(refreshDashboard, 5000);
  </script>
</body>
</html>
        """.strip()
    )
