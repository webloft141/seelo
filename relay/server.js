const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const path = require('path');
const cors = require('cors');
const rateLimit = require('express-rate-limit');
const admin = require('firebase-admin');

const store = require('./store');

// Firebase Admin — local file first, then env var, then ADC fallback
const fs = require('fs');
if (fs.existsSync('./service-account.json')) {
  const sa = JSON.parse(fs.readFileSync('./service-account.json', 'utf8'));
  admin.initializeApp({ credential: admin.credential.cert(sa) });
  console.log('Firebase Admin initialized (local file)');
} else if (process.env.FIREBASE_SERVICE_ACCOUNT) {
  const sa = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT);
  admin.initializeApp({ credential: admin.credential.cert(sa) });
  console.log('Firebase Admin initialized (env var)');
} else {
  try {
    admin.initializeApp({ projectId: 'seelo-acef3' });
    console.log('Firebase Admin (ADC fallback)');
  } catch (e) {
    console.warn('Firebase Admin not available — auth verification disabled');
  }
}

const app = express();
app.use(cors());
app.use(express.json({ limit: '50mb' }));
app.use(express.urlencoded({ extended: true }));

// Rate limiting — 60 req/min per IP for API routes
const apiLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 60,
  message: { error: 'Too many requests, slow down' },
  standardHeaders: true,
  legacyHeaders: false,
});
app.use('/api', apiLimiter);

const server = http.createServer(app);
const io = new Server(server, {
  cors: { origin: '*', methods: ['GET', 'POST'] },
  pingInterval: 30000,
  pingTimeout: 60000,
});

// Active sessions (declared early so health check can reference it)
const sessions = {};
const userSessions = {}; // uid -> Set<sessionId>

// Serve socket.io client for Figma plugin (overcomes CSP issues)
app.get('/socket.io.min.js', (req, res) => {
  res.sendFile(path.join(__dirname, 'socket.io.min.js'));
});

// --- Health check (for Render uptime monitoring) ---
app.get('/health', (req, res) => {
  res.json({
    status: 'ok',
    uptime: process.uptime(),
    sessions: Object.keys(sessions).length,
    users: Object.keys(store._raw()?.users || {}).length,
    timestamp: new Date().toISOString(),
  });
});
app.get('/api/health', (req, res) => {
  res.json({
    status: 'ok',
    uptime: process.uptime(),
    sessions: Object.keys(sessions).length,
    timestamp: new Date().toISOString(),
  });
});

// --- Static routes ---
app.get('/viewer.html', (req, res) => {
  res.sendFile(path.join(__dirname, 'viewer.html'));
});
app.get('/', (req, res) => {
  res.sendFile(path.join(__dirname, 'viewer.html'));
});
app.get('/terms', (req, res) => {
  res.sendFile(path.join(__dirname, 'terms.html'));
});
app.get('/privacy', (req, res) => {
  res.sendFile(path.join(__dirname, 'privacy.html'));
});
app.get('/oauth-callback', (req, res) => {
  res.sendFile(path.join(__dirname, 'oauth-callback.html'));
});

// --- Auth Session API (for Figma plugin Google sign-in) ---
// In-memory store for pending auth sessions: sessionId -> { customToken, uid, email }
const authSessions = new Map();

// Clean up old sessions every 5 minutes
setInterval(() => {
  const now = Date.now();
  for (const [id, data] of authSessions) {
    if (now - data.created > 10 * 60 * 1000) authSessions.delete(id); // 10 min TTL
  }
}, 300000);

// Figma plugin calls this after Google sign-in completes in the popup page
app.post('/api/auth/complete', async (req, res) => {
  const { sessionId, idToken } = req.body;
  if (!sessionId || !idToken) {
    return res.status(400).json({ error: 'Missing sessionId or idToken' });
  }
  try {
    const decoded = await verifyTokenCached(idToken);
    const uid = decoded.uid;
    const email = decoded.email || '';
    // Create a Firebase custom token so the plugin's Auth SDK can sign in
    let customToken = '';
    try {
      customToken = await admin.auth().createCustomToken(uid);
    } catch (e) {
      console.warn('Failed to create custom token:', e.message);
    }
    authSessions.set(sessionId, {
      uid,
      email,
      customToken,
      created: Date.now(),
    });
    // Also ensure user exists in store
    const user = store.getUser(uid);
    user.email = email || user.email;
    res.json({ success: true, uid, email });
  } catch (e) {
    res.status(401).json({ error: 'Invalid token' });
  }
});

// Plugin polls this endpoint to check if auth completed
app.get('/api/auth/session', (req, res) => {
  const sessionId = req.query.sessionId || '';
  if (!sessionId) return res.status(400).json({ error: 'Missing sessionId' });
  const session = authSessions.get(sessionId);
  if (!session) return res.json({ status: 'pending' });
  res.json({
    status: 'complete',
    uid: session.uid,
    email: session.email,
    customToken: session.customToken || '',
  });
});

// Google ID token → Firebase custom token (for plugin signInWithCredential fallback)
app.post('/api/auth/google-token', async (req, res) => {
  const { idToken } = req.body;
  if (!idToken) return res.status(400).json({ error: 'Missing idToken' });
  try {
    const apiKey = process.env.FIREBASE_API_KEY || 'AIzaSyBS6bV8-6kC8bEsEOs5k2kMtPUEqhaYCbQ';
    const r = await fetch(`https://identitytoolkit.googleapis.com/v1/accounts:signInWithIdp?key=${apiKey}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        requestUri: 'http://localhost',
        postBody: `id_token=${idToken}&providerId=google.com`,
        returnSecureToken: true,
      }),
    });
    const data = await r.json();
    if (data.error) {
      return res.status(401).json({ error: data.error.message || 'Token verification failed' });
    }
    const uid = data.localId;
    const customToken = await admin.auth().createCustomToken(uid);
    // Ensure user exists in store
    const user = store.getUser(uid);
    user.email = data.email || user.email;
    res.json({ success: true, customToken, uid, email: data.email || '' });
  } catch (e) {
    res.status(500).json({ error: 'Server error' });
  }
});

// --- Subscription API ---

// Verify Firebase ID token
async function verifyToken(req, res, next) {
  const auth = req.headers.authorization;
  if (!auth || !auth.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Missing token' });
  }
  const idToken = auth.split(' ')[1];
  try {
    const decoded = await verifyTokenCached(idToken);
    req.uid = decoded.uid;
    req.email = decoded.email || '';
    next();
  } catch (e) {
    return res.status(401).json({ error: 'Invalid token' });
  }
}

// Register / get user (GET and POST both supported)
app.get('/api/user', verifyToken, (req, res) => {
  const user = store.getUser(req.uid);
  user.email = req.email || user.email;
  const plan = store.getUserPlan(req.uid);
  res.json({ uid: user.uid, email: user.email, plan: plan.plan, maxDevices: plan.maxDevices, expiresAt: plan.expiresAt });
});
app.post('/api/user', verifyToken, (req, res) => {
  const user = store.getUser(req.uid);
  user.email = req.email || user.email;
  const plan = store.getUserPlan(req.uid);
  res.json({ uid: user.uid, email: user.email, plan: plan.plan, maxDevices: plan.maxDevices, expiresAt: plan.expiresAt });
});

// Activate a license key
app.post('/api/activate-key', verifyToken, (req, res) => {
  const { key } = req.body;
  if (!key || typeof key !== 'string') {
    return res.status(400).json({ error: 'Missing key' });
  }
  const result = store.activateKey(key.trim().toUpperCase(), req.uid);
  if (result.error) {
    return res.status(400).json({ error: result.error });
  }
  res.json({ success: true, plan: result.plan, maxDevices: result.maxDevices, expiresAt: result.expiresAt });
});

// Cancel subscription (revert to free)
app.post('/api/cancel-subscription', verifyToken, (req, res) => {
  const user = store.cancelPlan(req.uid);
  res.json({ success: true, plan: 'free' });
});

// Get subscription status (with expiry)
app.get('/api/subscription/:uid?', verifyToken, (req, res) => {
  const uid = req.params.uid || req.uid;
  if (uid !== req.uid) return res.status(403).json({ error: 'Forbidden' });
  const plan = store.getUserPlan(uid);
  const user = store.getUser(uid);
  res.json({
    uid,
    plan: plan.plan,
    maxDevices: plan.maxDevices,
    expiresAt: plan.expiresAt,
    createdAt: user.createdAt,
  });
});

// Get all plans
app.get('/api/plans', (req, res) => {
  const list = store.getPlans();
  res.json({ plans: list });
});

// --- Device listing, analytics, team endpoints ---

// List connected devices for the current user
app.get('/api/devices', verifyToken, (req, res) => {
  const uid = req.uid;
  const sessionIds = userSessions[uid] ? [...userSessions[uid]] : [];
  const devices = [];
  for (const sid of sessionIds) {
    const session = sessions[sid];
    if (!session) continue;
    const viewerCount = session.viewers ? session.viewers.length : 0;
    devices.push({
      sessionId: sid,
      viewerCount,
      maxViewers: session.maxViewers || 1,
      viewerIds: session.viewers || [],
      desktopConnected: Boolean(session.plugin),
    });
  }
  res.json({ devices, totalDevices: devices.reduce((s, d) => s + d.viewerCount, 0) });
});

// Analytics for the current user
app.get('/api/analytics', verifyToken, (req, res) => {
  const uid = req.uid;
  const user = store.getUser(uid);
  const stats = user.stats || { totalSessions: 0, totalPreviews: 0 };
  const sessionIds = userSessions[uid] ? [...userSessions[uid]] : [];
  let activeConnections = 0;
  for (const sid of sessionIds) {
    const session = sessions[sid];
    if (session && session.viewers) activeConnections += session.viewers.length;
  }
  res.json({
    totalSessions: stats.totalSessions || 0,
    totalPreviews: stats.totalPreviews || 0,
    activeConnections,
  });
});

// Team info
app.get('/api/team', verifyToken, (req, res) => {
  const uid = req.uid;
  const plan = store.getUserPlan(uid);
  res.json({
    teamName: 'My Team',
    plan: plan.plan,
    memberCount: 1,
    maxMembers: plan.plan.includes('team') ? 25 : 1,
    features: plan.plan.includes('team')
      ? ['Unlimited shared sessions', 'Admin dashboard', 'Team analytics']
      : [],
  });
});

// --- Firebase token cache (30 min TTL) ---
const tokenCache = new Map();
const CACHE_TTL = 30 * 60 * 1000; // 30 minutes

async function verifyTokenCached(idToken) {
  const cached = tokenCache.get(idToken);
  if (cached && (Date.now() - cached.ts) < CACHE_TTL) {
    return cached.decoded;
  }
  const decoded = await admin.auth().verifyIdToken(idToken);
  tokenCache.set(idToken, { decoded, ts: Date.now() });
  // Evict old entries periodically
  if (tokenCache.size > 1000) {
    const now = Date.now();
    for (const [key, val] of tokenCache) {
      if ((now - val.ts) > CACHE_TTL) tokenCache.delete(key);
    }
  }
  return decoded;
}

// --- Socket rate limiting ---
const socketRateMap = new Map();

function checkSocketRate(socket, event, maxPerSec = 5) {
  const key = socket.id + ':' + event;
  const now = Date.now();
  const entry = socketRateMap.get(key);
  if (!entry || (now - entry.window) > 1000) {
    socketRateMap.set(key, { window: now, count: 1 });
    return true;
  }
  entry.count++;
  if (entry.count > maxPerSec) {
    socket.emit('rate-limited', { event, message: 'Slow down' });
    return false;
  }
  return true;
}

// --- Socket.IO ---

io.on('connection', (socket) => {
  // Per-IP connection limit (max 5 concurrent connections per IP)
  const ip = socket.handshake.address;
  let ipConnections = 0;
  for (const [, s] of io.sockets.sockets) {
    if (s.handshake.address === ip) ipConnections++;
  }
  if (ipConnections > 20) {
    socket.emit('rate-limited', { message: 'Too many connections from this IP' });
    socket.disconnect();
    return;
  }

  socket.on('join-session', async ({ sessionId, role, maxViewers, uid, idToken }) => {
    if (!checkSocketRate(socket, 'join-session', 2)) return;
    if (!sessionId) return;

    // Plugin connects — resolve maxViewers from auth or fallback
    if (role === 'plugin') {
      let resolvedMax = 1;
      if (uid && idToken) {
        try {
          const decoded = await verifyTokenCached(idToken);
          if (decoded.uid === uid) {
            resolvedMax = store.getMaxDevices(uid);
          }
        } catch (_) {}
      }
      const numericMax = typeof maxViewers === 'number' && maxViewers > 0
        ? Math.min(maxViewers, resolvedMax)
        : resolvedMax;
      if (!sessions[sessionId]) {
        sessions[sessionId] = { plugin: socket.id, maxViewers: numericMax, viewers: [], design: null };
      } else {
        sessions[sessionId].plugin = socket.id;
      }
      socket.data.sessionId = sessionId;
      socket.data.role = 'plugin';
      socket.data.uid = uid || null;
      socket.join(sessionId);
      const userPlan = uid ? store.getUserPlan(uid).plan : 'free';
      socket.emit('plan-limit', { maxViewers: numericMax, plan: userPlan });
      if (uid) {
        if (!userSessions[uid]) userSessions[uid] = new Set();
        userSessions[uid].add(sessionId);
        store.incrementUserStat(uid, 'totalSessions');
      }
      return;
    }

    // Viewer connects
    if (role === 'viewer') {
      const session = sessions[sessionId];
      if (!session) {
        socket.emit('room-full', { message: 'Session not found', max: 0, current: 0 });
        return;
      }

      // Check viewer limit
      const currentViewers = session.viewers.length;
      const maxAllowed = session.maxViewers > 0 ? session.maxViewers : 1;
      if (currentViewers >= maxAllowed) {
        // Free plan (maxViewers=1): swap mode — replace old viewer
        if (maxAllowed === 1 && currentViewers === 1) {
          const oldSocketId = session.viewers[0];
          const oldSocket = io.sockets.sockets.get(oldSocketId);
          if (oldSocket) {
            oldSocket.emit('device-replaced', { message: 'Connected from another device' });
            oldSocket.disconnect();
          }
          session.viewers = [socket.id];
        } else {
          socket.emit('room-full', { message: 'Device limit reached', max: maxAllowed, current: currentViewers });
          return;
        }
      }

      // Check if this viewer is already in the room (reconnect)
      const existingIndex = session.viewers.indexOf(socket.id);
      if (existingIndex === -1) {
        session.viewers.push(socket.id);
      }

      socket.data.sessionId = sessionId;
      socket.data.role = 'viewer';
      socket.join(sessionId);

      // Send current design to the newly connected viewer
      if (session.design) {
        socket.emit('cloud-design', session.design);
      }

      // Send existing notes to the newly connected viewer
      if (session.notes && session.notes.length > 0) {
        socket.emit('existing-notes', { notes: session.notes });
      }

      // Emit updated viewer count
      const finalViewerCount = session.viewers.length;
      io.to(sessionId).emit('viewer-count', finalViewerCount);
      return;
    }
  });

  socket.on('cloud-design', (data) => {
    if (!checkSocketRate(socket, 'cloud-design', 10)) return;
    const sessionId = socket.data.sessionId;
    if (!sessionId || !data) return;
    if (!sessions[sessionId]) sessions[sessionId] = { maxViewers: 1, viewers: [], design: null };
    sessions[sessionId].design = data;
    socket.to(sessionId).emit('cloud-design', data);
    const uid = socket.data.uid;
    if (uid) store.incrementUserStat(uid, 'totalPreviews');
  });

  // Desktop mode heartbeat — prevent disconnect from idle timeouts
  socket.on('plugin-heartbeat', () => {});

  socket.on('request-frame-list', (data) => {
    if (!checkSocketRate(socket, 'request-frame-list', 5)) return;
    if (!data || !data.frames || !data.sessionId) return;
    if (!sessions[data.sessionId]) sessions[data.sessionId] = { maxViewers: 1, viewers: [], design: null };
    sessions[data.sessionId].frameList = data.frames;
    socket.to(data.sessionId).emit('frame-list', data);
  });

  socket.on('frame-select', (data) => {
    if (!checkSocketRate(socket, 'frame-select', 5)) return;
    if (!data || !data.frameId || !data.sessionId) return;
    socket.to(data.sessionId).emit('frame-select', data);
  });

  socket.on('add-note', (data) => {
    if (!checkSocketRate(socket, 'add-note', 5)) return;
    if (!data || !data.sessionId || !data.note) return;
    if (!sessions[data.sessionId]) sessions[data.sessionId] = { maxViewers: 1, viewers: [], design: null };
    if (!sessions[data.sessionId].notes) sessions[data.sessionId].notes = [];
    sessions[data.sessionId].notes.push(data.note);
    socket.to(data.sessionId).emit('note-added', data);
  });

  socket.on('delete-note', (data) => {
    if (!checkSocketRate(socket, 'delete-note', 5)) return;
    if (!data || !data.sessionId || !data.noteId) return;
    const session = sessions[data.sessionId];
    if (session && session.notes) {
      session.notes = session.notes.filter(n => n.id !== data.noteId);
    }
    socket.to(data.sessionId).emit('note-deleted', data);
  });

  socket.on('auto-send-toggle', (data) => {
    if (!checkSocketRate(socket, 'auto-send-toggle', 5)) return;
    if (!data || !data.sessionId) return;
    socket.to(data.sessionId).emit('auto-send-toggle', data);
  });

  socket.on('request-design', (data) => {
    if (!checkSocketRate(socket, 'request-design', 5)) return;
    if (!data || !data.sessionId) return;
    const session = sessions[data.sessionId];
    if (session && session.design) {
      socket.emit('cloud-design', session.design);
    }
  });

  socket.on('disconnect', () => {
    const sessionId = socket.data.sessionId;
    if (sessionId) {
      const session = sessions[sessionId];
      if (session) {
        const wasPlugin = socket.data.role === 'plugin';
        if (wasPlugin) {
          session.plugin = null;
        } else {
          session.viewers = session.viewers.filter(id => id !== socket.id);
        }
        const room = io.sockets.adapter.rooms.get(sessionId);
        const viewerCount = room ? room.size - (session.plugin ? 1 : 0) : 0;
        if (viewerCount <= 0 && !session.plugin) {
          delete sessions[sessionId];
        } else {
          io.to(sessionId).emit('viewer-count', viewerCount);
        }
      }
      const uid = socket.data.uid;
      if (uid && userSessions[uid]) {
        userSessions[uid].delete(sessionId);
        if (userSessions[uid].size === 0) delete userSessions[uid];
      }
    }
  });
});

// ── Admin Dashboard (built-in) ──
const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD || 'admin123';

function adminAuth(req, res, next) {
  const token = req.headers['x-admin-token'] || req.query.token;
  if (token !== ADMIN_PASSWORD) {
    return res.status(401).json({ error: 'Unauthorized' });
  }
  next();
}

app.post('/api/admin/login', (req, res) => {
  if (req.body.password === ADMIN_PASSWORD) {
    return res.json({ token: ADMIN_PASSWORD });
  }
  res.status(401).json({ error: 'Wrong password' });
});

app.get('/api/admin/stats', adminAuth, (req, res) => {
  const keys = store.listLicenseKeys();
  res.json({
    totalKeys: keys.length,
    usedKeys: keys.filter(k => k.usedBy).length,
    availableKeys: keys.filter(k => !k.usedBy).length,
    totalRevenue: keys.reduce((s, k) => s + (k.amountPaid || 0), 0),
    totalUsers: Object.keys(store._raw().users || {}).length,
    proUsers: Object.values(store._raw().users || {}).filter(u => u.plan && (u.plan.includes('pro') || u.plan.includes('team'))).length,
  });
});

app.get('/api/admin/keys', adminAuth, (req, res) => {
  const keys = store.listLicenseKeys().sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));
  res.json({ keys });
});

app.post('/api/admin/keys', adminAuth, (req, res) => {
  const { planId, durationDays, customerName, customerEmail, amountPaid, notes } = req.body;
  if (!planId) return res.status(400).json({ error: 'planId required' });
  const key = store.addLicenseKey(planId, parseInt(durationDays) || 30, {
    name: customerName || '', email: customerEmail || '', amount: parseInt(amountPaid) || 0, notes: notes || '',
  });
  if (!key) return res.status(400).json({ error: 'Invalid plan ID' });
  store.forceSave();
  res.json({ success: true, key });
});

app.get('/api/admin/plans', adminAuth, (req, res) => {
  res.json({ plans: store.getPlans().filter(p => p.id !== 'free') });
});

app.get('/api/admin/export/csv', adminAuth, (req, res) => {
  res.setHeader('Content-Type', 'text/csv');
  res.setHeader('Content-Disposition', 'attachment; filename=seelo-keys.csv');
  res.send(store.exportKeysCSV());
});

app.get('/admin', (req, res) => {
  res.sendFile(path.join(__dirname, 'admin.html'));
});

// --- Graceful shutdown ---
function shutdown(signal) {
  console.log(`\n${signal} received — shutting down gracefully...`);
  // Notify all connected clients
  io.emit('server-shutdown', { message: 'Server is restarting, reconnect shortly' });
  // Force save store data
  const { forceSave } = require('./store');
  if (typeof forceSave === 'function') forceSave();
  // Close all socket connections
  io.close(() => {
    console.log('All socket connections closed');
    // Close HTTP server
    server.close(() => {
      console.log('HTTP server closed');
      process.exit(0);
    });
  });
  // Force exit after 5s regardless
  setTimeout(() => {
    console.error('Forced exit after timeout');
    process.exit(1);
  }, 5000);
}

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));

// Start
const PORT = process.env.PORT || 3001;
server.listen(PORT, () => {
  console.log(`Seelo relay listening on port ${PORT}`);
});
