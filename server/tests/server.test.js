const { describe, it, before, after } = require('node:test');
const assert = require('node:assert/strict');
const http = require('http');
const { io: ioc } = require('socket.io-client');

const BASE = process.env.TEST_URL || 'http://127.0.0.1:3001';

async function fetchHealth() {
  return new Promise((resolve, reject) => {
    http.get(`${BASE}/health`, (res) => {
      let data = '';
      res.on('data', (c) => data += c);
      res.on('end', () => resolve({ status: res.statusCode, body: JSON.parse(data) }));
    }).on('error', reject);
  });
}

function connectSocket(path = '') {
  return new Promise((resolve, reject) => {
    const socket = ioc(BASE + path, {
      transports: ['websocket'],
      reconnection: false,
      timeout: 5000,
    });
    socket.on('connect', () => resolve(socket));
    socket.on('connect_error', reject);
    setTimeout(() => reject(new Error('Socket connection timeout')), 5000);
  });
}

describe('Seelo Server', () => {
  let serverProcess;

  before(async () => {
    // Health check with retries
    for (let i = 0; i < 10; i++) {
      try {
        const health = await fetchHealth();
        if (health.status === 200) return;
      } catch {}
      await new Promise(r => setTimeout(r, 500));
    }
    throw new Error('Server not reachable');
  });

  it('GET /health returns ok', async () => {
    const res = await fetchHealth();
    assert.equal(res.status, 200);
    assert.equal(res.body.status, 'ok');
    assert.equal(res.body.version, '2.0.0');
  });

  it('socket connects and receives server-ip', async () => {
    const socket = await connectSocket();
    const ip = await new Promise(resolve => socket.once('server-ip', resolve));
    assert.ok(ip.ip, 'should have ip field');
    socket.close();
  });

  it('register-room requires roomId and roomSecret', async () => {
    const socket = await connectSocket();
    const err = await new Promise(resolve => {
      socket.once('error-msg', resolve);
      socket.emit('register-room', {});
    });
    assert.ok(err.message.includes('roomId'));
    socket.close();
  });

  it('full room lifecycle works', async () => {
    const roomId = 'test-room-' + Date.now();
    const roomSecret = 'test-secret-123';

    // Plugin registers room
    const plugin = await connectSocket();
    plugin.emit('register-room', { roomId, roomSecret, role: 'plugin' });
    await new Promise(resolve => plugin.once('room-registered', resolve));

    // Mobile joins room
    const mobile = await connectSocket();
    const joinResult = await new Promise((resolve, reject) => {
      mobile.once('error-msg', reject);
      mobile.once('join-ack', resolve);
      mobile.emit('join-room', { roomId, roomSecret, role: 'mobile', deviceName: 'Test Phone' });
    });
    assert.equal(joinResult.roomId, roomId);

    // Mobile should get mobile-connected on plugin
    const connectedInfo = await new Promise(resolve => plugin.once('mobile-connected', resolve));
    assert.equal(connectedInfo.deviceName, 'Test Phone');

    // Design update
    const design = { imageData: 'data:image/png;base64,test' };
    plugin.emit('update-design', { roomId, roomSecret, design });
    const received = await new Promise(resolve => mobile.once('design-changed', resolve));
    assert.deepEqual(received.design, design);

    plugin.close();
    mobile.close();
  });

  it('rejects unauthorised room access', async () => {
    const socket = await connectSocket();
    const err = await new Promise(resolve => {
      socket.once('error-msg', resolve);
      socket.emit('join-room', { roomId: 'nonexistent', roomSecret: 'wrong' });
    });
    assert.ok(err.message.includes('Invalid room credentials'));
    socket.close();
  });

  it('rejects unauthorised design update', async () => {
    const socket = await connectSocket();
    const err = await new Promise(resolve => {
      socket.once('error-msg', resolve);
      socket.emit('update-design', { roomId: 'nonexistent', roomSecret: 'wrong', design: {} });
    });
    assert.ok(err.message.includes('Invalid room credentials'));
    socket.close();
  });
});
