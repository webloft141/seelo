# Seelo

Real-time Figma preview on your mobile device over local Wi-Fi.

## Architecture

```
Figma Plugin ──WebSocket──> Node Server ──WebSocket──> Mobile App (Flutter)
     │                                                        │
     └── Exports frames as PNG                           Displays full-screen
         Syncs on selection change                       Swipe = navigate frames
                                                        Shake = open settings
```

## Components

### 1. Server (`server/`)

Node.js + Socket.IO relay server with SQLite persistence.

```bash
cd server
npm install
npm start        # runs on port 3000
npm run dev      # watch mode (Node 22+)
```

**Environment variables:**

| Variable | Default | Description |
|----------|---------|-------------|
| `PORT` | `3000` | Server port |
| `HOST` | `0.0.0.0` | Bind address |
| `CORS_ORIGIN` | `*` | Allowed origins |
| `MAX_BUFFER` | `52428800` | Max design payload (50MB) |
| `DB_PATH` | `./seelo.db` | SQLite database path |
| `LOG_LEVEL` | `info` | Winston log level |
| `LOG_FILE` | (none) | Log file path |
| `RATE_LIMIT_MAX` | `100` | Max requests per window |
| `RATE_LIMIT_WINDOW` | `60000` | Rate limit window (ms) |
| `ROOM_SECRET_LENGTH` | `24` | Auto-generated room secret length |
| `CLEANUP_INTERVAL` | `3600000` | Stale room cleanup (ms) |
| `CLEANUP_AGE` | `86400000` | Max room age (ms) |

**Docker:**

```bash
cd server
docker compose up -d
```

**API:**

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | Health check + client count |

### 2. Figma Plugin (`plugin/`)

Figma plugin that exports selected frames and syncs them via the server.

Install in Figma: `Plugins → Development → Import plugin from manifest...` → select `plugin/manifest.json`

**Features:**
- Auto-syncs on selection change (700ms debounce)
- Exports as 2x PNG for sharp quality
- Extracts text layers and `[video]` layers
- Frame navigation (previous/next)
- Auto-resize frames from mobile
- Configurable server URL in plugin UI

### 3. Mobile App (`lib/main.dart`)

Flutter app that displays Figma frame previews in real-time.

```bash
flutter run       # on connected device/emulator
```

**Features:**
- QR code scanning for instant pairing
- Manual server address entry
- Swipe left/right for frame navigation
- Double-tap to reset zoom and re-sync
- Pinch-to-zoom (up to 4x)
- Shake to open settings
- Immersive mode (hidden system UI)
- Configurable screen size, room ID, port
- Error display with retry feedback

## Quick Start

1. **Start the server:**
   ```bash
   cd server && npm install && npm start
   ```

2. **Load the Figma plugin:**
   In Figma, go to `Plugins → Development → Import plugin from manifest...` and select `plugin/manifest.json`.

3. **Run the mobile app:**
   ```bash
   flutter run
   ```

4. **Connect:**
   - Open the Seelo plugin in Figma
   - Tap the QR icon or scan from the mobile app
   - The plugin auto-syncs on selection change

## Security Notes

- Server uses rate limiting, helmet security headers, and Input validation
- Room access is protected by generated secrets
- Server is designed for **local network use only**
- Do not expose the server to the public internet without adding authentication

## Development

```bash
# Server tests
cd server && npm test
```

## License

ISC
