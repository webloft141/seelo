const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const path = require('path');

const app = express();
const server = http.createServer(app);
const io = new Server(server);

app.get('/viewer.html', (req, res) => {
  res.sendFile(path.join(__dirname, 'viewer.html'));
});
app.get('/', (req, res) => {
  res.sendFile(path.join(__dirname, 'viewer.html'));
});

// Active sessions: sessionId -> latest design data
const sessions = {};

io.on('connection', (socket) => {
  socket.on('join-session', ({ sessionId, role }) => {
    if (!sessionId) return;
    socket.join(sessionId);
    socket.data.sessionId = sessionId;
    socket.data.role = role || 'viewer';

    // Send current design to newly connected viewer
    if (role === 'viewer' && sessions[sessionId]) {
      socket.emit('cloud-design', sessions[sessionId]);
    }

    // Broadcast viewer count update
    const room = io.sockets.adapter.rooms.get(sessionId);
    const count = room ? room.size : 0;
    io.to(sessionId).emit('viewer-count', count);
  });

  socket.on('cloud-design', (data) => {
    const sessionId = socket.data.sessionId;
    if (!sessionId || !data) return;

    // Cache latest design
    sessions[sessionId] = data;

    // Broadcast to all viewers in session (exclude sender)
    socket.to(sessionId).emit('cloud-design', data);
  });

  socket.on('disconnect', () => {
    const sessionId = socket.data.sessionId;
    if (sessionId) {
      const room = io.sockets.adapter.rooms.get(sessionId);
      const count = room ? room.size : 0;
      if (count > 0) {
        io.to(sessionId).emit('viewer-count', count);
      } else {
        // Clean up session data when last person leaves
        delete sessions[sessionId];
      }
    }
  });
});

const port = process.env.PORT || 3001;
server.listen(port, () => {
  console.log('Seelo relay listening on port ' + port);
});
