import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";

const runtimeMobiles = new Map();
let devicePollTimer = null;
console.log("[main.js] loading...");
let treeLoadTimer = null;
let treeProgress = 0;

function setPluginUiState(connected) {
  const dot = document.getElementById('plugin-dot');
  const text = document.getElementById('plugin-status');
  const stat = document.getElementById('plugin-stat');
  const label = document.getElementById('plugin-stat-label');
  if (connected) {
    dot.className = 'dot green';
    text.innerText = 'Plugin: Connected';
    stat.innerText = 'OK';
    stat.style.color = '#22c55e';
    label.innerText = 'Connected';
  } else {
    dot.className = 'dot red';
    text.innerText = 'Plugin: Disconnected';
    stat.innerText = '-';
    stat.style.color = '#999';
    label.innerText = 'Not connected';
  }
}

function setPluginUiLabel(text) {
  const label = document.getElementById('plugin-stat-label');
  if (label) label.innerText = text;
}

function setPluginHeartbeatLabel(text) {
  const hb = document.getElementById('plugin-heartbeat');
  if (hb) hb.innerText = text;
}

async function refreshPluginStatus() {
  try {
    const health = await invoke('get_plugin_health');
    const connected = !!health?.connected;
    setPluginUiState(connected);
    if (!connected) {
      setPluginUiLabel('Not connected');
      setPluginHeartbeatLabel('Last heartbeat: --');
      return;
    }
    const age = Number.isFinite(health?.age_ms) ? health.age_ms : null;
    const stat = document.getElementById('plugin-stat');
    if (age === null) {
      setPluginHeartbeatLabel('Last heartbeat: --');
    } else if (age < 1000) {
      setPluginHeartbeatLabel(`Last heartbeat: ${age}ms ago`);
    } else {
      setPluginHeartbeatLabel(`Last heartbeat: ${(age / 1000).toFixed(1)}s ago`);
    }
    if (age !== null && age > 20000) {
      setPluginUiLabel('Weak');
      if (stat) {
        stat.innerText = 'Weak';
        stat.style.color = '#999';
      }
    } else if (age !== null && age > 7000) {
      setPluginUiLabel('Medium');
      if (stat) {
        stat.innerText = 'Med';
        stat.style.color = '#b07b26';
      }
    } else {
      setPluginUiLabel('Strong');
      if (stat) {
        stat.innerText = 'OK';
        stat.style.color = '#22c55e';
      }
    }
  } catch (_) {}
}

async function renderPairingQr() {
  try {
    const data = await invoke('get_pairing_qr');
    const qrEl = document.getElementById('pairing-qr');
    const payloadEl = document.getElementById('pairing-payload');
    if (qrEl) qrEl.innerHTML = data.svg || '<div class="dev-empty">QR unavailable</div>';
    if (payloadEl) payloadEl.innerText = data.payload || '';
  } catch (e) {
    const qrEl = document.getElementById('pairing-qr');
    if (qrEl) qrEl.innerHTML = '<div class="dev-empty">QR generate failed</div>';
    console.error(e);
  }
}

function setTreeLoading(status, percent) {
  const clamped = Math.max(0, Math.min(100, percent));
  const statusEl = document.getElementById('tree-loading-status');
  const percentEl = document.getElementById('tree-loading-percent');
  const fillEl = document.getElementById('tree-progress-fill');
  if (statusEl) statusEl.innerText = status;
  if (percentEl) percentEl.innerText = `${Math.round(clamped)}%`;
  if (fillEl) fillEl.style.width = `${clamped}%`;
}

function startTreeLoading() {
  if (treeLoadTimer) clearInterval(treeLoadTimer);
  treeProgress = 0;
  setTreeLoading('Loading project tree...', treeProgress);
  treeLoadTimer = setInterval(() => {
    if (treeProgress < 90) {
      treeProgress += Math.max(1, (90 - treeProgress) * 0.08);
      setTreeLoading('Loading project tree...', treeProgress);
    }
  }, 180);
}

function finishTreeLoading(ok) {
  if (treeLoadTimer) {
    clearInterval(treeLoadTimer);
    treeLoadTimer = null;
  }
  treeProgress = 100;
  setTreeLoading(ok ? 'Loaded' : 'Failed to load', treeProgress);
}

function normalizeTreePayload(raw) {
  if (!raw) return null;
  let data = raw;
  if (typeof data === 'string') {
    try {
      data = JSON.parse(data);
    } catch (_) {
      return null;
    }
  }
  if (data.pages) return data;
  if (data.data && data.data.pages) return data.data;
  return null;
}

function showPage(name) {
  document.querySelectorAll('.content > div').forEach(d => d.classList.add('hidden'));
  document.getElementById('page-' + name).classList.remove('hidden');
  document.querySelectorAll('.nav-item').forEach(n => n.classList.remove('active'));
  document.querySelector(`.nav-item[data-page="${name}"]`).classList.add('active');
  document.getElementById('page-title').innerText = name.charAt(0).toUpperCase() + name.slice(1);
}

async function sendToPlugin(msg) {
  try {
    const sent = await invoke('send_to_plugin', { msg });
    return !!sent;
  } catch(e) {
    console.error(e);
    return false;
  }
}

async function blockDevice(id) {
  await invoke('block_mobile', { socketId: id });
  updateDevices();
}

listen('plugin-status', (event) => {
  setPluginUiState(event.payload === 'connected');
});

listen('mobile-connected', (event) => {
  const m = event?.payload || {};
  const id = m.socketId || `${m.deviceName || 'Mobile'}-${Date.now()}`;
  runtimeMobiles.set(id, {
    id,
    name: m.deviceName || 'Mobile',
    width: Number(m.screenWidth || 0),
    height: Number(m.screenHeight || 0),
  });
  renderDevicesFromPayload(Array.from(runtimeMobiles.values()));
});

listen('mobile-disconnected', (event) => {
  const id = event?.payload;
  if (typeof id === 'string') runtimeMobiles.delete(id);
  if (runtimeMobiles.size === 0) {
    updateDevices();
  } else {
    renderDevicesFromPayload(Array.from(runtimeMobiles.values()));
  }
});
listen('mobile-list-updated', (event) => {
  const list = Array.isArray(event?.payload) ? event.payload : [];
  runtimeMobiles.clear();
  for (const m of list) {
    if (!m) continue;
    runtimeMobiles.set(m.id || `${m.name || 'Mobile'}-${Math.random()}`, m);
  }
  renderDevicesFromPayload(Array.from(runtimeMobiles.values()));
});
listen('design-updated', () => {
  setPluginUiState(true);
  setPluginUiLabel('Design synced');
});
function renderProjectTree(raw) {
  try {
    const data = normalizeTreePayload(raw);
    const tree = document.getElementById('project-tree');
    if (!data || !data.pages) {
      tree.innerHTML = '<div style="color:#999;">No valid export payload received</div>';
      finishTreeLoading(false);
      return;
    }
    const pages = Array.isArray(data.pages) ? data.pages : Object.values(data.pages || {});
    if (pages.length === 0) {
      tree.innerHTML = '<div style="color:#999;">Export succeeded, but no pages found</div>';
      finishTreeLoading(true);
      return;
    }
    let html = '';
    let frameCount = 0;
    pages.forEach((page, pageIdx) => {
      if (!page) return;
      const pageId = page.id || `page-${pageIdx}`;
      const pageContentId = `tree-page-content-${pageId.replace(/[^a-zA-Z0-9_-]/g, '_')}`;
      html += `<div class="tree-page-head" data-page-toggle="${pageContentId}">
        <span class="tree-page-toggle" data-page-arrow="${pageContentId}">-</span>
        <span class="icon">PAGE</span>
        <span class="name"><b>${page.name || 'Untitled Page'}</b></span>
      </div>`;
      html += `<div class="tree-page-content" id="${pageContentId}">`;
      const frames = Array.isArray(page.frames) ? page.frames : Object.values(page.frames || {});
      for (const frame of frames) {
        if (!frame) continue;
        frameCount += 1;
        const fw = Number.isFinite(frame.width) ? frame.width : 0;
        const fh = Number.isFinite(frame.height) ? frame.height : 0;
        html += `<div class="tree-frame-row" data-frame-id="${frame.id || ''}">
          <span class="icon">FRAME</span>
          <span class="name">${frame.name || 'Untitled Frame'}</span>
          <span class="dim">${fw}x${fh}</span>
        </div>`;
        const layers = Array.isArray(frame.layers) ? frame.layers : Object.values(frame.layers || {});
        for (const layer of layers) {
          if (!layer) continue;
          html += `<div class="tree-layer-row">
            <span class="icon">${layer.type === 'TEXT' ? 'TEXT' : 'LAYER'}</span>
            <span class="name">${layer.name || 'Layer'}</span>
          </div>`;
        }
      }
      html += `</div>`;
    });
    if (frameCount === 0) {
      tree.innerHTML = html + '<div style="color:#999;padding:8px 6px;">No frames found in export payload</div>';
      finishTreeLoading(true);
      return;
    }
    tree.innerHTML = html;
    tree.querySelectorAll('[data-frame-id]').forEach(el => {
      el.addEventListener('click', () => {
        if (!el.dataset.frameId) return;
        sendToPlugin({ type: 'select-frame', frameId: el.dataset.frameId });
      });
    });
    tree.querySelectorAll('[data-page-toggle]').forEach(el => {
      el.addEventListener('click', () => {
        const targetId = el.dataset.pageToggle;
        const content = document.getElementById(targetId);
        const arrow = tree.querySelector(`[data-page-arrow="${targetId}"]`);
        if (!content) return;
        const hide = content.style.display !== 'none' ? true : false;
        content.style.display = hide ? 'none' : 'block';
        if (arrow) arrow.innerText = hide ? '+' : '-';
      });
    });
    finishTreeLoading(true);
  } catch (err) {
    console.error('Project tree render error:', err);
    const tree = document.getElementById('project-tree');
    if (tree) tree.innerHTML = '<div style="color:#999;">Render failed. Check export payload format.</div>';
    finishTreeLoading(false);
  }
}

listen('full-export-data', (event) => {
  setTreeLoading('Processing export data...', 95);
  renderProjectTree(event.payload);
});

async function refreshProjectTreeFromCache() {
  try {
    const data = await invoke('get_full_export');
    if (data) renderProjectTree(data);
  } catch (_) {
    finishTreeLoading(false);
  }
}

async function updateDevices() {
  try {
    const result = await invoke('get_mobiles');
    const mobiles = Array.isArray(result) ? result : [];
    renderDevicesFromPayload(mobiles);
  } catch(e) { console.error(e); }
}

function renderDevicesFromPayload(listData) {
  const mobiles = Array.isArray(listData) ? listData : [];
  const lists = ['dashboard-devices', 'devices-list'];
  for (const listId of lists) {
    const list = document.getElementById(listId);
    if (!list) continue;
    if (mobiles.length === 0) {
      list.innerHTML = '<div class="dev-empty">No devices connected</div>';
    } else {
      list.innerHTML = mobiles.map(m => `
        <div class="dev-item">
          <span>DEV</span>
          <div class="info">
            <div class="name">${m.name}</div>
            <div class="meta">${m.width}x${m.height}</div>
          </div>
          <button class="block-btn" data-id="${m.id}">x</button>
        </div>
      `).join('');
      list.querySelectorAll('.block-btn').forEach(btn => {
        btn.addEventListener('click', () => blockDevice(btn.dataset.id));
      });
    }
  }
  const countEl = document.getElementById('device-count');
  if (countEl) countEl.innerText = mobiles.length;
}

document.addEventListener('DOMContentLoaded', () => {
  document.querySelectorAll('.nav-item[data-page]').forEach(el => {
    el.addEventListener('click', () => showPage(el.dataset.page));
  });

  document.getElementById('sync-btn').addEventListener('click', () => sendToPlugin({ type: 'manual-sync' }));
  document.getElementById('export-btn').addEventListener('click', async () => {
    startTreeLoading();
    const synced = await sendToPlugin({ type: 'manual-sync' });
    if (!synced) {
      setTreeLoading('Plugin not connected', 100);
      const tree = document.getElementById('project-tree');
      if (tree) tree.innerHTML = '<div style="color:#b45309;">Plugin disconnected. Reopen plugin and try again.</div>';
      return;
    }
    await new Promise(r => setTimeout(r, 250));
    const exported = await sendToPlugin({ type: 'full-export' });
    if (!exported) {
      setTreeLoading('Export command failed', 100);
      return;
    }
    setTimeout(refreshProjectTreeFromCache, 700);
    setTimeout(refreshProjectTreeFromCache, 1600);
    setTimeout(() => {
      if (treeLoadTimer) finishTreeLoading(false);
    }, 7000);
  });



  showPage('dashboard');
  updateDevices();
  if (devicePollTimer) clearInterval(devicePollTimer);
  devicePollTimer = setInterval(() => {
    updateDevices();
  }, 2000);
  refreshPluginStatus();
  setInterval(refreshPluginStatus, 2000);
  renderPairingQr();
  setTreeLoading('Idle', 0);
  refreshProjectTreeFromCache();

  invoke('get_local_ip').then(ip => {
    const sidebarIp = document.getElementById('server-ip');
    const settingsAddr = document.getElementById('settings-server-addr');
    if (sidebarIp) sidebarIp.innerText = ip + ':3000';
    if (settingsAddr) settingsAddr.value = ip + ':3000';
  }).catch(() => {});
});



