const express = require('express');
const http = require('http');
const path = require('path');
const { Server } = require('socket.io');
const cors = require('cors');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
const winston = require('winston');
const Database = require('better-sqlite3');
const { v4: uuidv4 } = require('uuid');
const os = require('os');

// ── Logger ──────────────────────────────────────────────────────────
const logger = winston.createLogger({
  level: process.env.LOG_LEVEL || 'info',
  format: winston.format.combine(
    winston.format.timestamp(),
    winston.format.printf(({ level, message, timestamp, ...meta }) => {
      const extra = Object.keys(meta).length ? ` ${JSON.stringify(meta)}` : '';
      return `${timestamp} [${level.toUpperCase()}] ${message}${extra}`;
    }),
  ),
  transports: [
    new winston.transports.Console(),
    ...(process.env.LOG_FILE
      ? [new winston.transports.File({ filename: process.env.LOG_FILE })]
      : []),
  ],
});

// ── Config ──────────────────────────────────────────────────────────
const PORT = parseInt(process.env.PORT || '3000', 10);
const HOST = process.env.HOST || '0.0.0.0';
const CORS_ORIGIN = process.env.CORS_ORIGIN || '*';
const MAX_BUFFER = parseInt(process.env.MAX_BUFFER || '52428800', 10); // 50MB
const ROOM_SECRET_LENGTH = parseInt(process.env.ROOM_SECRET_LENGTH || '24', 10);
const DB_PATH = process.env.DB_PATH || path.join(__dirname, 'seelo.db');
const RATE_LIMIT_WINDOW = parseInt(process.env.RATE_LIMIT_WINDOW || '60000', 10);
const RATE_LIMIT_MAX = parseInt(process.env.RATE_LIMIT_MAX || '100', 10);

// ── Database ────────────────────────────────────────────────────────
let db;
try {
  db = new Database(DB_PATH, { verbose: process.env.NODE_ENV === 'development' ? logger.debug : null });
  db.pragma('journal_mode = WAL');
  db.pragma('foreign_keys = ON');
  db.exec(`
    CREATE TABLE IF NOT EXISTS rooms (
      room_id TEXT PRIMARY KEY,
      room_secret TEXT NOT NULL,
      created_at INTEGER NOT NULL,
      last_active INTEGER NOT NULL
    );
    CREATE TABLE IF NOT EXISTS room_designs (
       room_id TEXT PRIMARY KEY,
       design_data TEXT,
       updated_at INTEGER NOT NULL,
       FOREIGN KEY (room_id) REFERENCES rooms(room_id)
    );
    CREATE TABLE IF NOT EXISTS sessions (
      session_id TEXT PRIMARY KEY,
      room_id TEXT,
      role TEXT NOT NULL DEFAULT 'mobile',
      device_name TEXT,
      screen_width INTEGER DEFAULT 0,
      screen_height INTEGER DEFAULT 0,
      connected_at INTEGER NOT NULL,
      last_seen INTEGER NOT NULL,
      FOREIGN KEY (room_id) REFERENCES rooms(room_id)
    );
    CREATE INDEX IF NOT EXISTS idx_sessions_room ON sessions(room_id);
    CREATE INDEX IF NOT EXISTS idx_sessions_seen ON sessions(last_seen);
  `);
  logger.info(`Database initialised at ${DB_PATH}`);
} catch (err) {
  logger.error(`Failed to open database: ${err.message}`);
  process.exit(1);
}

const stmts = {
  upsertRoom: db.prepare(`
    INSERT INTO rooms (room_id, room_secret, created_at, last_active)
    VALUES (@room_id, @room_secret, @now, @now)
    ON CONFLICT(room_id) DO UPDATE SET last_active = @now
  `),
  getRoom: db.prepare('SELECT * FROM rooms WHERE room_id = ?'),
  deleteRoom: db.prepare('DELETE FROM rooms WHERE room_id = ?'),
  upsertDesign: db.prepare(`
    INSERT INTO room_designs (room_id, design_data, updated_at)
    VALUES (@room_id, @design_data, @now)
    ON CONFLICT(room_id) DO UPDATE SET design_data = @design_data, updated_at = @now
  `),
  getDesign: db.prepare('SELECT design_data FROM room_designs WHERE room_id = ?'),
  deleteDesign: db.prepare('DELETE FROM room_designs WHERE room_id = ?'),
  insertSession: db.prepare(`
    INSERT INTO sessions (session_id, room_id, role, device_name, screen_width, screen_height, connected_at, last_seen)
    VALUES (@session_id, @room_id, @role, @device_name, @screen_width, @screen_height, @now, @now)
  `),
  updateSessionSeen: db.prepare('UPDATE sessions SET last_seen = @now WHERE session_id = @session_id'),
  deleteSession: db.prepare('DELETE FROM sessions WHERE session_id = ?'),
  getRoomSessions: db.prepare('SELECT * FROM sessions WHERE room_id = ? ORDER BY connected_at DESC'),
  cleanupOldRooms: db.prepare('DELETE FROM rooms WHERE last_active < @cutoff'),
  cleanupOldSessions: db.prepare('DELETE FROM sessions WHERE last_seen < @cutoff'),
};

// In-memory cache for active designs (faster than reading DB every time)
const designCache = new Map();

// ── Express App ─────────────────────────────────────────────────────
const app = express();

// Security headers
app.use(helmet({
  contentSecurityPolicy: false,
  crossOriginEmbedderPolicy: false,
}));

// CORS
app.use(cors({
  origin: CORS_ORIGIN === '*' ? true : CORS_ORIGIN.split(',').map(s => s.trim()),
  methods: ['GET', 'POST'],
}));

// Rate limiting
const limiter = rateLimit({
  windowMs: RATE_LIMIT_WINDOW,
  max: RATE_LIMIT_MAX,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many requests, please try again later.' },
});
app.use(limiter);

app.use(express.json({ limit: '1mb' }));

// Health check
app.get('/health', (req, res) => {
  const uptime = process.uptime();
  res.json({
    status: 'ok',
    uptime,
    version: '2.0.0',
    clients: io?.engine?.clientsCount || 0,
    timestamp: new Date().toISOString(),
  });
});

// Cleanup old rooms/sessions periodically
const CLEANUP_INTERVAL = parseInt(process.env.CLEANUP_INTERVAL || '3600000', 10); // 1h
const CLEANUP_AGE = parseInt(process.env.CLEANUP_AGE || '86400000', 10); // 24h
setInterval(() => {
  const cutoff = Date.now() - CLEANUP_AGE;
  const r = stmts.cleanupOldRooms.run({ cutoff });
  const s = stmts.cleanupOldSessions.run({ cutoff });
  if (r.changes > 0 || s.changes > 0) {
    logger.info(`Cleanup: removed ${r.changes} rooms, ${s.changes} stale sessions`);
  }
}, CLEANUP_INTERVAL);

// ── Helpers ─────────────────────────────────────────────────────────
function generateRoomSecret() {
  return uuidv4().replace(/-/g, '').slice(0, ROOM_SECRET_LENGTH);
}

function sanitisePayload(payload) {
  if (typeof payload !== 'object' || payload === null) return {};
  const sanitised = {};
  for (const [key, value] of Object.entries(payload)) {
    if (typeof value === 'string') {
      sanitised[key] = value.slice(0, 512);
    } else if (typeof value === 'number' && Number.isFinite(value)) {
      sanitised[key] = value;
    } else if (typeof value === 'boolean') {
      sanitised[key] = value;
    }
  }
  return sanitised;
}

function canAccessRoom(roomId, roomSecret) {
  if (!roomId || !roomSecret) return false;
  const row = stmts.getRoom.get(roomId);
  if (!row) return false;
  return row.room_secret === roomSecret;
}

function getPhysicalLocalIp() {
  const interfaces = os.networkInterfaces();
  let fallbackIp = '127.0.0.1';
  let preferredIp = null;

  for (const devName in interfaces) {
    const lowerName = devName.toLowerCase();
    if (
      lowerName.includes('virtual') ||
      lowerName.includes('vmware') ||
      lowerName.includes('vbox') ||
      lowerName.includes('wsl') ||
      lowerName.includes('loopback') ||
      lowerName.includes('host-only') ||
      lowerName.includes('vethernet')
    ) {
      continue;
    }
    const iface = interfaces[devName];
    for (let i = 0; i < iface.length; i++) {
      const alias = iface[i];
      if (alias.family === 'IPv4' && alias.address !== '127.0.0.1' && !alias.internal) {
        const ip = alias.address;
        if (ip.startsWith('192.168.') || ip.startsWith('10.')) {
          return ip;
        }
        preferredIp = ip;
      }
    }
  }
  return preferredIp || fallbackIp;
}

// ── Socket.IO Server ────────────────────────────────────────────────
const server = http.createServer(app);
const io = new Server(server, {
  cors: {
    origin: CORS_ORIGIN === '*' ? true : CORS_ORIGIN.split(',').map(s => s.trim()),
    methods: ['GET', 'POST'],
  },
  maxHttpBufferSize: MAX_BUFFER,
  pingInterval: 25000,
  pingTimeout: 20000,
});

const localIp = getPhysicalLocalIp();

io.on('connection', (socket) => {
  const clientIp = socket.handshake.address;
  logger.info(`Client connected: ${socket.id} from ${clientIp}`, { clientIp });

  socket.emit('server-ip', { ip: localIp });

  // ── Register Room (Plugin only) ────────────────────────────────────
  // ── Auto-register for plugin clients ───────────────────────────────
  socket.on('join-room', (payload) => {
    const data = sanitisePayload(payload);
    const { roomId, roomSecret, role } = data;
    if (!roomId) {
      socket.emit('error-msg', { message: 'roomId required' });
      return;
    }

    // If plugin and no room exists, auto-register with generated secret
    if (role === 'plugin') {
      try {
        const existing = stmts.getRoom.get(roomId);
        if (!existing) {
          const secret = roomSecret || generateRoomSecret();
          stmts.upsertRoom.run({ room_id: roomId, room_secret: secret, now: Date.now() });
          logger.info(`Room auto-registered: ${roomId} (secret: ${secret})`);
          socket.emit('room-registered', { roomId, roomSecret: secret });
        }
      } catch (err) {
        logger.error(`Failed to auto-register room ${roomId}: ${err.message}`);
      }
    }

    // Plugins can always join their own room; mobile devices need credentials
    if (role !== 'plugin' && !canAccessRoom(roomId, roomSecret)) {
      logger.warn(`Unauthorised join attempt: ${socket.id} → room ${roomId}`);
      socket.emit('error-msg', { message: 'Invalid room credentials' });
      return;
    }

    socket.join(roomId);
    logger.info(`Client ${socket.id} joined room ${roomId} as ${role || 'unknown'}`);

    if (role === 'mobile') {
      const deviceName = (data.deviceName || 'Mobile Device').slice(0, 64);
      const screenWidth = Math.min(Math.max(parseInt(data.screenWidth) || 0, 0), 7680);
      const screenHeight = Math.min(Math.max(parseInt(data.screenHeight) || 0, 0), 7680);

      try {
        stmts.insertSession.run({
          session_id: socket.id,
          room_id: roomId,
          role: 'mobile',
          device_name: deviceName,
          screen_width: screenWidth,
          screen_height: screenHeight,
          now: Date.now(),
        });
      } catch (err) {
        logger.error(`Failed to save session ${socket.id}: ${err.message}`);
      }

      socket.to(roomId).emit('mobile-connected', { socketId: socket.id, timestamp: Date.now(), deviceName, screenWidth, screenHeight });
      socket.emit('join-ack', { roomId });
      // Notify all clients in room with full mobile list
      _emitMobileList(roomId);
    }

    if (role === 'plugin') {
      socket.emit('join-ack', { roomId });
      _emitMobileList(roomId);
    }

    // Send cached design if available
    const cached = designCache.get(roomId);
    if (cached) {
      socket.emit('design-changed', { design: cached });
    } else {
      const row = stmts.getDesign.get(roomId);
      if (row?.design_data) {
        try {
          const parsed = JSON.parse(row.design_data);
          designCache.set(roomId, parsed);
          socket.emit('design-changed', { design: parsed });
        } catch { /* ignore corrupt cache */ }
      }
    }
  });

  // ── Resize ─────────────────────────────────────────────────────────
  socket.on('request-resize', (payload) => {
    if (!payload || !payload.roomId || !payload.roomSecret) return;
    if (!canAccessRoom(payload.roomId, payload.roomSecret)) return;
    const width = Math.min(Math.max(parseInt(payload.width) || 0, 100), 7680);
    const height = Math.min(Math.max(parseInt(payload.height) || 0, 100), 7680);
    const name = (payload.name || '').slice(0, 64);
    io.to(payload.roomId).emit('resize-request', {
      type: 'resize-frame', width, height, name, roomId: payload.roomId,
    });
  });

  // ── Navigate ───────────────────────────────────────────────────────
  socket.on('navigate-frame', (payload) => {
    if (!payload || !payload.roomId || !payload.roomSecret) return;
    if (!canAccessRoom(payload.roomId, payload.roomSecret)) return;
    io.to(payload.roomId).emit('frame-navigation', payload);
  });

  // ── Plugin heartbeat ──────────────────────────────────────────────
  socket.on('plugin-heartbeat', (msg) => {
    if (socket.rooms.size > 0) {
      stmts.updateSessionSeen.run({ session_id: socket.id, now: Date.now() });
    }
  });

  // ── Design update from plugin UI ───────────────────────────────────
  socket.on('design-update', (data) => {
    // Determine room from socket's joined rooms (skip the default socket.id room)
    const roomId = [...socket.rooms].find(r => r !== socket.id);
    if (!roomId) return;
    const row = stmts.getRoom.get(roomId);
    if (!row) return;
    designCache.set(roomId, data);
    try {
      stmts.upsertDesign.run({ room_id: roomId, design_data: JSON.stringify(data), now: Date.now() });
    } catch (err) {
      logger.error(`Failed to persist design-update for ${roomId}: ${err.message}`);
    }
    socket.to(roomId).emit('design-changed', { design: data });
  });

  socket.on('full-export', (data) => {
    const roomId = [...socket.rooms].find(r => r !== socket.id);
    if (!roomId) return;
    const row = stmts.getRoom.get(roomId);
    if (!row) return;
    socket.to(roomId).emit('full-export-data', data);
  });

  // ── Ping/pong for mobile latency ───────────────────────────────────
  socket.on('ping', (data) => {
    socket.emit('pong', { ts: data?.ts || Date.now() });
  });

  // ── Login ──────────────────────────────────────────────────────────
  socket.on('login-request', () => {
    // Placeholder for future auth integration
    socket.emit('login-result', { token: null, name: null, message: 'Login flow not yet implemented' });
  });

  // ── Emit mobile list to all clients in a room ──────────────────────
  function _emitMobileList(roomId) {
    try {
      const rows = stmts.getRoomSessions.all(roomId);
      const list = rows
        .filter(r => r.role === 'mobile')
        .map(r => ({
          socketId: r.session_id,
          deviceName: r.device_name || 'Device',
          screenWidth: r.screen_width || 0,
          screenHeight: r.screen_height || 0,
        }));
      io.to(roomId).emit('mobile-list', list);
    } catch (err) {
      logger.error(`Failed to emit mobile-list for ${roomId}: ${err.message}`);
    }
  }

  // ── Disconnect ─────────────────────────────────────────────────────
  socket.on('disconnect', (reason) => {
    logger.info(`Client disconnected: ${socket.id} (${reason})`);
    try {
      const session = stmts.deleteSession.run(socket.id);
      if (session.changes > 0) {
        for (const room of socket.rooms) {
          if (room !== socket.id) {
            socket.to(room).emit('mobile-disconnected', socket.id);
            _emitMobileList(room);
          }
        }
      }
    } catch (err) {
      logger.error(`Error during disconnect cleanup ${socket.id}: ${err.message}`);
    }
  });
});

// ── Start ───────────────────────────────────────────────────────────
const gracefulShutdown = (signal) => {
  logger.info(`${signal} received — shutting down gracefully...`);
  // Notify all connected clients
  io.emit('server-shutdown', { message: 'Server is restarting, reconnect shortly' });
  // Close all sockets
  io.close(() => {
    logger.info('All socket connections closed');
    server.close(() => {
      db.close();
      logger.info('Server stopped');
      process.exit(0);
    });
  });
  // Force exit after 5s regardless
  setTimeout(() => {
    logger.error('Forced exit after timeout');
    process.exit(1);
  }, 5000);
};

process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));
process.on('SIGINT', () => gracefulShutdown('SIGINT'));

server.listen(PORT, HOST, () => {
  logger.info(`Seelo Server v2.0.0 running on ${HOST}:${PORT}`);
  logger.info(`Local IP for devices: ${localIp}`);
  logger.info(`CORS origin: ${CORS_ORIGIN}`);
  logger.info(`Max buffer: ${(MAX_BUFFER / 1024 / 1024).toFixed(1)}MB`);
});
