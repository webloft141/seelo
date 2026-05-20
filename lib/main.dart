import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:flutter/services.dart';

enum ConnectionQuality { disconnected, poor, fair, good }

class SavedDevice {
  final String ip;
  final int port;
  final String roomId;
  final String? roomSecret;
  final String label;
  final DateTime lastUsed;

  SavedDevice({
    required this.ip,
    required this.port,
    this.roomId = 'seelo-desktop',
    this.roomSecret,
    this.label = '',
    DateTime? lastUsed,
  }) : lastUsed = lastUsed ?? DateTime.now();

  String get displayLabel => label.isNotEmpty ? label : '$ip:$port';
  Map<String, dynamic> toPayload() => {
    'ip': ip, 'port': port.toString(),
    'roomId': roomId, 'roomSecret': roomSecret,
  };
}

void main() {
  runApp(const SeeloApp());
}

class SeeloConfig {
  int screenWidth = 412;
  int screenHeight = 915;
  String defaultRoomId = 'seelo-desktop';
  int defaultPort = 3000;
  int reconnectAttempts = 20;
  int reconnectDelay = 800;
  int connectTimeout = 10000;

  static final SeeloConfig _instance = SeeloConfig._();
  factory SeeloConfig() => _instance;
  SeeloConfig._();
}

class SeeloApp extends StatelessWidget {
  const SeeloApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Seelo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFF0C0C0C),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0C0C0C),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.white,
        ),
      ),
      home: const SplashScreen(),
    );
  }
}

class AppPalette {
  static const bg = Color(0xFF0C0C0C);
  static const card = Color(0xFF161616);
  static const cardSoft = Color(0xFF1E1E1E);
  static const border = Color(0xFF2C2C2C);
  static const text = Color(0xFFF3F3F3);
  static const dim = Color(0xFFA6A6A6);
  static const white = Colors.white;
}

class FrameMetadata {
  final String? id;
  final String? projectId;
  final double frameWidth;
  final double frameHeight;
  final double exportScale;
  final String? backgroundColor;
  final List<Map<String, dynamic>> textLayers;
  final List<Map<String, dynamic>> videoLayers;
  final String? imageData;

  FrameMetadata({
    this.id,
    this.projectId,
    this.frameWidth = 0,
    this.frameHeight = 0,
    this.exportScale = 2,
    this.backgroundColor,
    this.textLayers = const [],
    this.videoLayers = const [],
    this.imageData,
  });

  double get imagePixelsWidth => frameWidth * exportScale;
  double get imagePixelsHeight => frameHeight * exportScale;
}

class DesignIssue {
  final String type;
  final String message;
  final double x, y, width, height;
  final String? layerName;
  DesignIssue({required this.type, required this.message, required this.x, required this.y, required this.width, required this.height, this.layerName});
}

class DevicePreset {
  final String name;
  final double screenWidth;
  final double screenHeight;
  final double dpr;
  final double exportScale;

  const DevicePreset({
    required this.name,
    required this.screenWidth,
    required this.screenHeight,
    this.dpr = 3.0,
    this.exportScale = 3.0,
  });

  String get label => '$name (${screenWidth.toInt()}\u00D7${screenHeight.toInt()})';
}

const builtInPresets = [
  DevicePreset(name: 'iPhone 15 Pro Max', screenWidth: 430, screenHeight: 932, dpr: 3.0, exportScale: 3.0),
  DevicePreset(name: 'iPhone 15 Pro', screenWidth: 393, screenHeight: 852, dpr: 3.0, exportScale: 3.0),
  DevicePreset(name: 'iPhone 15', screenWidth: 393, screenHeight: 852, dpr: 2.94, exportScale: 3.0),
  DevicePreset(name: 'iPhone SE', screenWidth: 375, screenHeight: 667, dpr: 2.0, exportScale: 2.0),
  DevicePreset(name: 'Pixel 8 Pro', screenWidth: 412, screenHeight: 915, dpr: 3.5, exportScale: 3.0),
  DevicePreset(name: 'Pixel 8', screenWidth: 392, screenHeight: 852, dpr: 2.63, exportScale: 3.0),
  DevicePreset(name: 'Galaxy S24', screenWidth: 412, screenHeight: 915, dpr: 3.0, exportScale: 3.0),
  DevicePreset(name: 'Galaxy S24 Ultra', screenWidth: 412, screenHeight: 915, dpr: 3.69, exportScale: 3.0),
  DevicePreset(name: 'iPad Pro 12.9"', screenWidth: 1024, screenHeight: 1366, dpr: 2.0, exportScale: 2.0),
  DevicePreset(name: 'iPad Air 11"', screenWidth: 820, screenHeight: 1180, dpr: 2.0, exportScale: 2.0),
];

class SessionEntry {
  final String label;
  final DateTime time;
  final bool isCloud;
  SessionEntry(this.label, this.time, {this.isCloud = false});
}

class SeeloConnectionController {
  io.Socket? _socket;
  String roomId = 'seelo-desktop';
  String? roomSecret;
  String serverLabel = 'Not connected';
  bool connecting = false;
  bool _disposed = false;

  String? currentImageData;
  FrameMetadata? currentMetadata;
  String? _lastFrameId;

  final ValueNotifier<int> imageVersion = ValueNotifier<int>(0);
  final ValueNotifier<FrameMetadata?> metadataNotifier = ValueNotifier<FrameMetadata?>(null);
  final ValueNotifier<ConnectionQuality> connectionQuality = ValueNotifier(ConnectionQuality.disconnected);
  final ValueNotifier<int> latencyMs = ValueNotifier(0);
  final ValueNotifier<List<SavedDevice>> savedDevices = ValueNotifier([]);
  final ValueNotifier<List<DesignIssue>> issues = ValueNotifier([]);
  final ValueNotifier<int> viewerCount = ValueNotifier(0);
  final List<SessionEntry> sessionHistory = [];

  Timer? _designTimeout;
  Timer? _pingTimer;
  int _reconnectCount = 0;
  int _latencySum = 0;
  int _latencySamples = 0;

  static const int _maxSavedDevices = 5;

  void _saveDevice(String ip, int port) {
    final devices = List<SavedDevice>.from(savedDevices.value);
    devices.removeWhere((d) => d.ip == ip && d.port == port);
    devices.insert(0, SavedDevice(ip: ip, port: port, roomId: roomId, roomSecret: roomSecret, lastUsed: DateTime.now()));
    if (devices.length > _maxSavedDevices) devices.removeLast();
    savedDevices.value = devices;
  }

  void connectToSaved(SavedDevice device) {
    if (device.ip.isEmpty) return;
    _connectWithPayloadInternal(device.toPayload());
  }

  void dispose() {
    _disposed = true;
    _designTimeout?.cancel();
    _pingTimer?.cancel();
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
  }

  bool get isConnected => _socket?.connected == true;

  void connectWithPayload({required Map<String, dynamic> payload, VoidCallback? onConnected, void Function(String message)? onError, void Function(String message)? onStatus}) {
    _connectWithPayloadInternal(payload, onConnected: onConnected, onError: onError, onStatus: onStatus);
  }

  void _connectToRelay(String relayUrl, String sessionId, {VoidCallback? onConnected, void Function(String message)? onError, void Function(String message)? onStatus}) {
    if (relayUrl.isEmpty || sessionId.isEmpty) {
      onError?.call('Invalid relay link');
      return;
    }
    connecting = true;
    connectionQuality.value = ConnectionQuality.disconnected;
    serverLabel = 'Cloud';
    onStatus?.call('Connecting to cloud...');

    _socket?.disconnect();
    _socket?.dispose();
    _pingTimer?.cancel();

    final config = SeeloConfig();
    final socket = io.io(
      relayUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .enableReconnection()
          .setReconnectionAttempts(config.reconnectAttempts)
          .setReconnectionDelay(config.reconnectDelay)
          .setReconnectionDelayMax(3000)
          .setTimeout(config.connectTimeout)
          .build(),
    );
    _socket = socket;

    socket.onConnect((_) {
      if (_disposed) return;
      connecting = false;
      _reconnectCount = 0;
      connectionQuality.value = ConnectionQuality.good;
      viewerCount.value = 0;
      sessionHistory.insert(0, SessionEntry('Cloud: ${sessionId.length > 8 ? sessionId.substring(0, 8) : sessionId}...', DateTime.now(), isCloud: true));
      socket.emit('join-session', {'sessionId': sessionId, 'role': 'viewer'});
      onConnected?.call();
      onStatus?.call('Cloud connected');
    });

    socket.on('cloud-design', (payload) {
      if (_disposed) return;
      try {
        final design = payload is Map ? payload : null;
        if (design is Map) {
          final imageData = design['imageData'];
          final newId = design['id']?.toString();
          if (imageData is String && imageData.startsWith('data:image')) {
            _lastFrameId = newId;
            currentImageData = imageData;
            currentMetadata = FrameMetadata(
              id: newId,
              projectId: design['projectId']?.toString(),
              frameWidth: (design['width'] ?? 0).toDouble(),
              frameHeight: (design['height'] ?? 0).toDouble(),
              exportScale: (design['exportScale'] ?? 2).toDouble(),
              backgroundColor: design['backgroundColor']?.toString(),
              textLayers: (design['textLayers'] is List ? List<Map<String, dynamic>>.from(design['textLayers'].map((e) => Map<String, dynamic>.from(e))) : []),
              videoLayers: (design['videoLayers'] is List ? List<Map<String, dynamic>>.from(design['videoLayers'].map((e) => Map<String, dynamic>.from(e))) : []),
              imageData: imageData,
            );
            metadataNotifier.value = currentMetadata;
            imageVersion.value++;
          }
        }
      } catch (_) {}
      _designTimeout?.cancel();
      onStatus?.call('Preview synced');
    });

    socket.on('viewer-count', (count) {
      if (_disposed) return;
      viewerCount.value = (count is num) ? count.toInt() : 0;
    });

    socket.onConnectError((err) {
      if (_disposed) return;
      connecting = false;
      _reconnectCount++;
      connectionQuality.value = ConnectionQuality.poor;
      onError?.call('Connection failed ($_reconnectCount)');
      onStatus?.call('Retrying...');
    });

    socket.onDisconnect((_) {
      if (_disposed) return;
      connectionQuality.value = ConnectionQuality.disconnected;
      onStatus?.call('Disconnected');
    });

    socket.onReconnect((_) {
      if (_disposed) return;
      connectionQuality.value = ConnectionQuality.good;
      socket.emit('join-session', {'sessionId': sessionId, 'role': 'viewer'});
      onStatus?.call('Reconnected');
    });

    _designTimeout?.cancel();
    _designTimeout = Timer(const Duration(seconds: 15), () {
      if (_disposed) return;
      if (currentImageData == null) {
        onError?.call('No design received. Click SYNC in plugin.');
        onStatus?.call('Waiting for design...');
      }
    });
  }

  void _connectWithPayloadInternal(Map<String, dynamic> payload, {VoidCallback? onConnected, void Function(String message)? onError, void Function(String message)? onStatus}) {
    final relay = (payload['relay'] ?? '').toString().trim();
    if (relay.isNotEmpty) {
      _connectToRelay(relay, (payload['sessionId'] ?? '').toString(), onConnected: onConnected, onError: onError, onStatus: onStatus);
      return;
    }
    final ip = (payload['ip'] ?? '').toString().trim();
    final port = int.tryParse((payload['port'] ?? SeeloConfig().defaultPort).toString()) ?? SeeloConfig().defaultPort;
    roomId = (payload['roomId'] ?? SeeloConfig().defaultRoomId).toString();
    roomSecret = payload['roomSecret']?.toString();

    if (ip.isEmpty) {
      onError?.call('Invalid: IP missing');
      return;
    }

    connecting = true;
    _reconnectCount = 0;
    connectionQuality.value = ConnectionQuality.disconnected;
    onStatus?.call('Connecting...');

    _socket?.disconnect();
    _socket?.dispose();
    _pingTimer?.cancel();

    final config = SeeloConfig();
    final socket = io.io(
      'http://$ip:$port',
      io.OptionBuilder()
          .setTransports(['websocket']) 
          .enableReconnection()
          .setReconnectionAttempts(config.reconnectAttempts)
          .setReconnectionDelay(config.reconnectDelay)
          .setReconnectionDelayMax(3000)
          .setTimeout(config.connectTimeout)
          .build(),
    );
    _socket = socket;

    void joinAndRequestSync() {
      socket.emit('join-room', {
        'roomId': roomId, 'roomSecret': roomSecret,
        'role': 'mobile', 'deviceName': 'Seelo Mobile',
        'screenWidth': config.screenWidth, 'screenHeight': config.screenHeight,
      });
      socket.emit('request-resize', {
        'type': 'resize-frame', 'name': 'Seelo Mobile',
        'width': config.screenWidth, 'height': config.screenHeight,
        'roomId': roomId, 'roomSecret': roomSecret,
      });
    }

    socket.onConnect((_) {
      if (_disposed) return;
      serverLabel = '$ip:$port';
      _reconnectCount = 0;
      _latencySum = 0;
      _latencySamples = 0;
      connectionQuality.value = ConnectionQuality.good;
      _saveDevice(ip, port);
      sessionHistory.insert(0, SessionEntry('Desktop: $ip:$port', DateTime.now()));
      joinAndRequestSync();
      _startPing();
      onConnected?.call();
      onStatus?.call('Connected');
      connecting = false;
    });

    socket.on('design-changed', (payload) {
      if (_disposed) return;
      try {
        final design = payload is Map ? payload['design'] : null;
        if (design is Map) {
          final imageData = design['imageData'];
          final newId = design['id']?.toString();
          // Frame dedup: skip re-render if same frame ID
          if (newId != null && newId == _lastFrameId && imageData != null && imageData == currentImageData) {
            return;
          }
          if (imageData is String && imageData.startsWith('data:image')) {
            _lastFrameId = newId;
            currentImageData = imageData;
            currentMetadata = FrameMetadata(
              id: newId,
              projectId: design['projectId']?.toString(),
              frameWidth: (design['width'] ?? 0).toDouble(),
              frameHeight: (design['height'] ?? 0).toDouble(),
              exportScale: (design['exportScale'] ?? 2).toDouble(),
              backgroundColor: design['backgroundColor']?.toString(),
              textLayers: (design['textLayers'] is List ? List<Map<String, dynamic>>.from(design['textLayers'].map((e) => Map<String, dynamic>.from(e))) : []),
              videoLayers: (design['videoLayers'] is List ? List<Map<String, dynamic>>.from(design['videoLayers'].map((e) => Map<String, dynamic>.from(e))) : []),
              imageData: imageData,
            );
            metadataNotifier.value = currentMetadata;
            imageVersion.value++;
            _detectIssues();
          }
        }
      } catch (_) {}
      _designTimeout?.cancel();
      onStatus?.call('Preview synced');
    });

    socket.on('error-msg', (payload) {
      if (_disposed) return;
      final msg = payload is Map ? (payload['message'] ?? 'Server error').toString() : 'Server error';
      onError?.call(msg);
    });

    socket.onConnectError((err) {
      if (_disposed) return;
      connecting = false;
      _reconnectCount++;
      connectionQuality.value = ConnectionQuality.poor;
      onError?.call('Connection failed ($_reconnectCount)');
      onStatus?.call('Retrying...');
    });

    socket.onDisconnect((_) {
      if (_disposed) return;
      connectionQuality.value = ConnectionQuality.disconnected;
      onStatus?.call('Disconnected');
    });

    socket.onReconnect((_) {
      if (_disposed) return;
      connectionQuality.value = ConnectionQuality.good;
      joinAndRequestSync();
      onStatus?.call('Reconnected');
      onConnected?.call();
      _startPing();
    });

    _designTimeout?.cancel();
    _designTimeout = Timer(const Duration(seconds: 15), () {
      if (_disposed) return;
      if (currentImageData == null) {
        onError?.call('No design received. Click SYNC in plugin.');
        onStatus?.call('Waiting for design...');
      }
    });
  }

  void _detectIssues() {
    final meta = currentMetadata;
    final list = <DesignIssue>[];
    if (meta == null) { issues.value = list; return; }
    final fw = meta.frameWidth;
    final fh = meta.frameHeight;
    for (final layer in meta.textLayers) {
      final lx = (layer['x'] as num?)?.toDouble() ?? 0;
      final ly = (layer['y'] as num?)?.toDouble() ?? 0;
      final lw = (layer['width'] as num?)?.toDouble() ?? 0;
      final lh = (layer['height'] as num?)?.toDouble() ?? 0;
      final name = layer['characters']?.toString() ?? '';
      if (lw > fw && fw > 0) {
        list.add(DesignIssue(type: 'overflow', message: 'Text wider than frame: "$name"', x: lx, y: ly, width: lw, height: lh, layerName: name));
      }
      if (lx + lw > fw && fw > 0) {
        list.add(DesignIssue(type: 'overflow', message: 'Text extends past right edge', x: lx, y: ly, width: lw, height: lh, layerName: name));
      }
      if (ly + lh > fh && fh > 0) {
        list.add(DesignIssue(type: 'overflow', message: 'Text extends past bottom edge', x: lx, y: ly, width: lw, height: lh, layerName: name));
      }
    }
    for (int i = 0; i < meta.textLayers.length; i++) {
      for (int j = i + 1; j < meta.textLayers.length; j++) {
        final a = meta.textLayers[i]; final b = meta.textLayers[j];
        final ax = (a['x'] as num?)?.toDouble() ?? 0; final ay = (a['y'] as num?)?.toDouble() ?? 0;
        final aw = (a['width'] as num?)?.toDouble() ?? 0; final ah = (a['height'] as num?)?.toDouble() ?? 0;
        final bx = (b['x'] as num?)?.toDouble() ?? 0; final by = (b['y'] as num?)?.toDouble() ?? 0;
        final bw = (b['width'] as num?)?.toDouble() ?? 0; final bh = (b['height'] as num?)?.toDouble() ?? 0;
        if (ax < bx + bw && ax + aw > bx && ay < by + bh && ay + ah > by) {
          list.add(DesignIssue(type: 'overlap', message: 'Text layers overlap', x: ax, y: ay, width: aw, height: ah, layerName: a['characters']?.toString() ?? ''));
          break;
        }
      }
    }
    issues.value = list;
  }

  void _startPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!isConnected || _disposed) return;
      _socket!.emit('ping', {'ts': DateTime.now().millisecondsSinceEpoch});
    });
    _socket!.off('pong');
    _socket!.on('pong', (data) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final serverTs = (data is Map) ? data['ts'] : data;
      if (serverTs is int) {
        final ms = now - serverTs;
        _latencySum += ms;
        _latencySamples++;
        final avg = _latencySum ~/ _latencySamples;
        latencyMs.value = avg;
        connectionQuality.value = avg < 50 ? ConnectionQuality.good : avg < 150 ? ConnectionQuality.fair : ConnectionQuality.poor;
      }
    });
  }

  void requestNavigate(String direction) {
    if (!isConnected) return;
    _socket!.emit('navigate-frame', {
      'type': 'navigate-frame', 'direction': direction,
      'roomId': roomId, 'roomSecret': roomSecret,
    });
  }

  void requestManualSync() {
    if (!isConnected) return;
    final config = SeeloConfig();
    _socket!.emit('request-resize', {
      'type': 'resize-frame', 'name': 'Seelo Mobile',
      'width': config.screenWidth, 'height': config.screenHeight,
      'roomId': roomId, 'roomSecret': roomSecret,
    });
  }

  void disconnect() {
    _designTimeout?.cancel();
    _pingTimer?.cancel();
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    connecting = false;
    currentImageData = null;
    currentMetadata = null;
    _lastFrameId = null;
    serverLabel = 'Not connected';
    connectionQuality.value = ConnectionQuality.disconnected;
    latencyMs.value = 0;
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const OnboardingScreen()),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Text(
          'Seelo',
          style: TextStyle(color: AppPalette.white, fontWeight: FontWeight.w800, fontSize: 40, letterSpacing: 1),
        ),
      ),
    );
  }
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _controller = PageController();
  int _index = 0;

  static const slides = [
    (title: 'Live Figma Preview', body: 'See your Figma frames live on phone with low-latency local sync.'),
    (title: 'Quick Pairing', body: 'Scan desktop QR to connect instantly over same Wi-Fi.'),
    (title: 'Swipe And Review', body: 'Swipe left-right for pages and scroll vertically for long screens.'),
  ];

  void _finish() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => HomeScreen(controller: SeeloConnectionController())),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: slides.length,
                  onPageChanged: (value) => setState(() => _index = value),
                  itemBuilder: (_, i) {
                    final slide = slides[i];
                    return Container(
                      margin: const EdgeInsets.symmetric(vertical: 12),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppPalette.card,
                        border: Border.all(color: AppPalette.border),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(slide.title, textAlign: TextAlign.center, style: const TextStyle(color: AppPalette.text, fontSize: 28, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 16),
                          Text(slide.body, textAlign: TextAlign.center, style: const TextStyle(color: AppPalette.dim, fontSize: 15, height: 1.4)),
                        ],
                      ),
                    );
                  },
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(slides.length, (i) => Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: i == _index ? 18 : 8, height: 8,
                  decoration: BoxDecoration(
                    color: i == _index ? Colors.white : const Color(0xFF4A4A4A),
                    borderRadius: BorderRadius.circular(999),
                  ),
                )),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white, foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    if (_index < slides.length - 1) {
                      _controller.nextPage(duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
                    } else {
                      _finish();
                    }
                  },
                  child: Text(_index < slides.length - 1 ? 'Next' : 'Get Started'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.controller});

  final SeeloConnectionController controller;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _linkController = TextEditingController();
  String _status = 'Idle';
  String _error = '';

  @override
  void dispose() {
    _linkController.dispose();
    widget.controller.dispose();
    super.dispose();
  }

  void _openPreview() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PreviewScreen(controller: widget.controller)),
    );
  }

  void _scanAndConnect() {
    Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => const QrScanScreen()),
    ).then((payload) {
      if (!mounted || payload == null) return;
      setState(() => _error = '');
      widget.controller.connectWithPayload(
        payload: payload,
        onConnected: _openPreview,
        onError: (msg) { if (mounted) setState(() => _error = msg); },
        onStatus: (msg) { if (mounted) setState(() => _status = msg); },
      );
    });
  }

  void _manualConnect() {
    final text = _linkController.text.trim();
    if (text.isEmpty) return;

    Uri? uri;
    try {
      uri = Uri.parse(text.startsWith('http') ? text : 'http://$text');
    } catch (_) {}

    if (uri == null || uri.host.isEmpty) {
      setState(() => _error = 'Invalid server address. Use ip:port or http://ip:port');
      return;
    }

    setState(() => _error = '');
    widget.controller.connectWithPayload(
      payload: {
        'ip': uri.host,
        'port': uri.port.toString(),
        'roomId': SeeloConfig().defaultRoomId,
      },
      onConnected: _openPreview,
      onError: (msg) { if (mounted) setState(() => _error = msg); },
      onStatus: (msg) { if (mounted) setState(() => _status = msg); },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Seelo', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          ValueListenableBuilder<ConnectionQuality>(
            valueListenable: widget.controller.connectionQuality,
            builder: (_, q, __) {
              final dotColor = q == ConnectionQuality.good ? const Color(0xFF22C55E)
                : q == ConnectionQuality.fair ? const Color(0xFFEAB308)
                : q == ConnectionQuality.poor ? const Color(0xFFEF4444)
                : AppPalette.dim;
              return Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Tooltip(
                  message: q == ConnectionQuality.disconnected ? 'Disconnected' : '${widget.controller.serverLabel}',
                  child: Container(
                    width: 10, height: 10, margin: const EdgeInsets.only(right: 4),
                    decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white70),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Manual Connect', style: _h),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _linkController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Server address (e.g. 192.168.1.5:3000)',
                      hintStyle: const TextStyle(color: AppPalette.dim),
                      filled: true, fillColor: AppPalette.cardSoft,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppPalette.border)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppPalette.border)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white70)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white, foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _manualConnect,
                      child: const Text('Connect'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Quick Pairing', style: _h),
                  const SizedBox(height: 8),
                  const Text('Scan desktop QR to connect instantly.', style: TextStyle(color: AppPalette.dim)),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white, foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _scanAndConnect,
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text('Open QR Scanner'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  ValueListenableBuilder<ConnectionQuality>(
                    valueListenable: widget.controller.connectionQuality,
                    builder: (_, q, __) {
                      final dotColor = q == ConnectionQuality.good ? const Color(0xFF22C55E)
                        : q == ConnectionQuality.fair ? const Color(0xFFEAB308)
                        : q == ConnectionQuality.poor ? const Color(0xFFEF4444)
                        : AppPalette.dim;
                      return Row(
                        children: [
                          Container(width: 8, height: 8, margin: const EdgeInsets.only(right: 6),
                            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle)),
                          Text('Status: $_status', style: const TextStyle(color: AppPalette.text, fontSize: 13)),
                          if (widget.controller.connecting)
                            const Padding(padding: EdgeInsets.only(left: 8),
                              child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70))),
                        ],
                      );
                    },
                  ),
                  if (_error.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.withOpacity(0.3)),
                        ),
                        child: Text(_error, style: const TextStyle(color: Color(0xFFF5A0A0), fontSize: 13)),
                      ),
                    ),
                ],
              ),
            ),
            // Saved devices
            ValueListenableBuilder<List<SavedDevice>>(
              valueListenable: widget.controller.savedDevices,
              builder: (_, devices, __) {
                if (devices.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: _card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text('Saved Devices', style: _h),
                            const Spacer(),
                            GestureDetector(
                              onTap: () {
                                final list = List<SavedDevice>.from(devices);
                                list.clear();
                                widget.controller.savedDevices.value = list;
                              },
                              child: const Text('Clear', style: TextStyle(color: AppPalette.dim, fontSize: 12)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ...List.generate(devices.length, (i) {
                          final d = devices[i];
                          return InkWell(
                            onTap: () {
                              widget.controller.connectToSaved(d);
                              _openPreview();
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Row(
                                children: [
                                  const Icon(Icons.computer, color: AppPalette.dim, size: 18),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(d.displayLabel, style: const TextStyle(color: AppPalette.text, fontSize: 13, fontWeight: FontWeight.w500)),
                                        Text(d.roomId, style: const TextStyle(color: AppPalette.dim, fontSize: 11)),
                                      ],
                                    ),
                                  ),
                                  const Icon(Icons.chevron_right, color: AppPalette.dim, size: 18),
                                ],
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _widthC;
  late TextEditingController _heightC;
  late TextEditingController _roomC;
  late TextEditingController _portC;

  @override
  void initState() {
    super.initState();
    final c = SeeloConfig();
    _widthC = TextEditingController(text: c.screenWidth.toString());
    _heightC = TextEditingController(text: c.screenHeight.toString());
    _roomC = TextEditingController(text: c.defaultRoomId);
    _portC = TextEditingController(text: c.defaultPort.toString());
  }

  @override
  void dispose() {
    _widthC.dispose();
    _heightC.dispose();
    _roomC.dispose();
    _portC.dispose();
    super.dispose();
  }

  void _save() {
    final c = SeeloConfig();
    c.screenWidth = int.tryParse(_widthC.text) ?? c.screenWidth;
    c.screenHeight = int.tryParse(_heightC.text) ?? c.screenHeight;
    c.defaultRoomId = _roomC.text.trim().isEmpty ? c.defaultRoomId : _roomC.text.trim();
    c.defaultPort = int.tryParse(_portC.text) ?? c.defaultPort;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Settings saved'), duration: Duration(seconds: 1)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Preview Size', style: _h),
                  const SizedBox(height: 4),
                  const Text('Default screen dimensions for preview.', style: TextStyle(color: AppPalette.dim, fontSize: 13)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _widthC,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(color: Colors.white),
                          decoration: _inputDeco('Width (px)'),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Text('\u00D7', style: TextStyle(color: AppPalette.dim, fontSize: 18)),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _heightC,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(color: Colors.white),
                          decoration: _inputDeco('Height (px)'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Connection', style: _h),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _roomC,
                    style: const TextStyle(color: Colors.white),
                    decoration: _inputDeco('Default Room ID'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _portC,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white),
                    decoration: _inputDeco('Default Port'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white, foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _save,
                child: const Text('Save Settings'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

InputDecoration _inputDeco(String hint) {
  return InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: AppPalette.dim),
    filled: true,
    fillColor: AppPalette.cardSoft,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppPalette.border)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppPalette.border)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white70)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
  );
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.controller});

  final SeeloConnectionController controller;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  String _error = '';

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _quickLoginQr() {
    Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => const QrScanScreen()),
    ).then((payload) {
      if (!mounted || payload == null) return;
      widget.controller.connectWithPayload(
        payload: payload,
        onConnected: () {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => PreviewScreen(controller: widget.controller)),
          );
        },
        onError: (msg) { if (mounted) setState(() => _error = msg); },
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Account Login', style: _h),
                  const SizedBox(height: 12),
                  _input(_email, 'Email'),
                  const SizedBox(height: 10),
                  _input(_password, 'Password', obscure: true),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white, foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () {
                        setState(() => _error = 'Email login flow can be wired to backend next.');
                      },
                      child: const Text('Login'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Quick Login via Desktop QR', style: _h),
                  const SizedBox(height: 8),
                  const Text('Scan QR from desktop app and login instantly.', style: TextStyle(color: AppPalette.dim)),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: AppPalette.border),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _quickLoginQr,
                      icon: const Icon(Icons.qr_code),
                      label: const Text('Scan For Quick Login'),
                    ),
                  ),
                  if (_error.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(_error, style: const TextStyle(color: Color(0xFFD3D3D3))),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _input(TextEditingController c, String hint, {bool obscure = false}) {
    return TextField(
      controller: c,
      obscureText: obscure,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppPalette.dim),
        filled: true,
        fillColor: AppPalette.cardSoft,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppPalette.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppPalette.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white70)),
      ),
    );
  }
}

class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            onDetect: (capture) {
              if (_busy) return;
              final raw = capture.barcodes.first.rawValue;
              if (raw == null) return;
              try {
                final map = jsonDecode(raw) as Map<String, dynamic>;
                _busy = true;
                Navigator.of(context).pop(map);
              } catch (_) {
                setState(() => _busy = true);
                Future.delayed(const Duration(milliseconds: 800), () {
                  if (!mounted) return;
                  setState(() => _busy = false);
                });
              }
            },
          ),
          Container(
            color: Colors.black45,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 260, height: 260,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white, width: 2),
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text('Scan desktop QR', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white60)),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Back'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum DisplayMode { fitToScreen, pixelPerfect }

class PreviewScreen extends StatefulWidget {
  const PreviewScreen({super.key, required this.controller});

  final SeeloConnectionController controller;

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> with WidgetsBindingObserver {
  StreamSubscription<AccelerometerEvent>? _shakeSub;
  DateTime? _lastShake;
  bool _showingPopup = false;
  bool _showSystemUi = false;
  bool _showIssues = true;
  bool _showSafeArea = false;
  bool _showGrid = false;
  bool _showToolbar = true;
  bool _wasInBackground = false;
  Timer? _toolbarTimer;
  DisplayMode _displayMode = DisplayMode.fitToScreen;
  DevicePreset _selectedPreset = builtInPresets[0];
  final TransformationController _transformationController = TransformationController();
  final GlobalKey _imageKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _applySystemUiMode();
    _shakeSub = accelerometerEventStream().listen(_handleShake);
    _startToolbarTimer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _wasInBackground = true;
    } else if (state == AppLifecycleState.resumed && _wasInBackground) {
      _wasInBackground = false;
      // Check connection; auto-reconnect overlay will show if needed
      if (!widget.controller.isConnected) {
        setState(() {});
      }
    }
  }

  void _startToolbarTimer() {
    _toolbarTimer?.cancel();
    _toolbarTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _showToolbar = false);
    });
  }

  void _toggleToolbar() {
    setState(() => _showToolbar = !_showToolbar);
    if (_showToolbar) _startToolbarTimer();
  }

  void _applySystemUiMode() {
    if (_showSystemUi) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ));
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: []);
      SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
      ));
    }
  }

  void _handleShake(AccelerometerEvent event) {
    final magnitude = sqrt((event.x * event.x) + (event.y * event.y) + (event.z * event.z));
    if (magnitude < 25) return;

    final now = DateTime.now();
    if (_lastShake != null && now.difference(_lastShake!).inMilliseconds < 1400) return;
    _lastShake = now;

    if (_showingPopup || !mounted) return;
    _showSettings();
  }

  void _showSettings() {
    _showingPopup = true;
    showDialog<void>(
      context: context,
      builder: (ctx) {
        bool localShowUi = _showSystemUi;
        DisplayMode localMode = _displayMode;
        return AlertDialog(
          backgroundColor: AppPalette.card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Preview Settings', style: TextStyle(color: AppPalette.text)),
          content: StatefulBuilder(
            builder: (context, setInner) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Customize your immersive experience.', style: TextStyle(color: AppPalette.dim)),
                  const SizedBox(height: 20),
                  _settingToggle('Show System UI', 'Display status/nav bars', localShowUi, (v) {
                    setInner(() => localShowUi = v);
                    setState(() => _showSystemUi = v);
                    _applySystemUiMode();
                  }),
                  const SizedBox(height: 16),
                  const Text('Overlays', style: TextStyle(color: AppPalette.text, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  _settingToggle('Issue Highlighting', 'Show overflow/overlap warnings', _showIssues, (v) {
                    setState(() => _showIssues = v);
                  }),
                  const SizedBox(height: 8),
                  _settingToggle('Safe Area', 'Visualize safe zone boundaries', _showSafeArea, (v) {
                    setState(() => _showSafeArea = v);
                  }),
                  const SizedBox(height: 8),
                  _settingToggle('Pixel Grid', '8×8 px alignment grid', _showGrid, (v) {
                    setState(() => _showGrid = v);
                  }),
                  const SizedBox(height: 16),
                  const Text('Display Mode', style: TextStyle(color: AppPalette.text, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  _modeChip('Fit to Screen', 'Stretch image to fill screen width', DisplayMode.fitToScreen, localMode, setInner),
                  const SizedBox(height: 6),
                  _modeChip('Pixel Perfect', '1:1 native resolution, no stretching', DisplayMode.pixelPerfect, localMode, setInner),
                  const SizedBox(height: 16),
                  const Text('Device Preset', style: TextStyle(color: AppPalette.text, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 160),
                    child: SingleChildScrollView(
                      child: Column(
                        children: List.generate(builtInPresets.length, (i) {
                          final preset = builtInPresets[i];
                          final active = _selectedPreset.name == preset.name;
                          return InkWell(
                            onTap: () => setState(() => _selectedPreset = preset),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              margin: const EdgeInsets.only(bottom: 4),
                              decoration: BoxDecoration(
                                color: active ? Colors.white.withOpacity(0.1) : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                                border: active ? Border.all(color: Colors.white24) : null,
                              ),
                              child: Row(
                                children: [
                                  Icon(active ? Icons.check_circle : Icons.phone_android, size: 16,
                                      color: active ? const Color(0xFF22C55E) : AppPalette.dim),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(preset.label, style: TextStyle(color: active ? Colors.white : AppPalette.dim, fontSize: 13)),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close', style: TextStyle(color: Colors.white70)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white, foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(this.context).pop();
              },
              child: const Text('Exit Preview'),
            ),
          ],
        );
      },
    ).then((_) => _showingPopup = false);
  }

  void _showHistory() {
    final history = widget.controller.sessionHistory;
    _showingPopup = true;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppPalette.card,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppPalette.dim, borderRadius: BorderRadius.circular(2))),
              ),
              const SizedBox(height: 16),
              Text('Session History', style: const TextStyle(color: AppPalette.text, fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('${history.length} session${history.length != 1 ? 's' : ''}', style: const TextStyle(color: AppPalette.dim, fontSize: 13)),
              const SizedBox(height: 16),
              if (history.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: Text('No sessions yet', style: TextStyle(color: AppPalette.dim))),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: history.length,
                    separatorBuilder: (_, __) => const Divider(color: AppPalette.border, height: 1),
                    itemBuilder: (_, i) {
                      final entry = history[i];
                      final icon = entry.isCloud ? Icons.cloud : Icons.desktop_windows;
                      return ListTile(
                        dense: true,
                        leading: Icon(icon, color: entry.isCloud ? const Color(0xFF22C55E) : AppPalette.dim, size: 20),
                        title: Text(entry.label, style: const TextStyle(color: AppPalette.text, fontSize: 14)),
                        subtitle: Text(_formatTime(entry.time), style: const TextStyle(color: AppPalette.dim, fontSize: 11)),
                        contentPadding: EdgeInsets.zero,
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    ).then((_) => _showingPopup = false);
  }

  String _formatTime(DateTime t) {
    final now = DateTime.now();
    final diff = now.difference(t);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  Widget _modeChip(String title, String subtitle, DisplayMode mode, DisplayMode current, void Function(void Function()) setInner) {
    final active = mode == current;
    return InkWell(
      onTap: () {
        setInner(() {});
        setState(() => _displayMode = mode);
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: active ? Colors.white.withOpacity(0.1) : Colors.transparent,
          border: Border.all(color: active ? Colors.white : AppPalette.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(
              mode == DisplayMode.fitToScreen ? Icons.fit_screen : Icons.one_x_mobiledata,
              color: active ? Colors.white : AppPalette.dim,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(color: active ? Colors.white : AppPalette.text, fontWeight: FontWeight.w600, fontSize: 13)),
                  Text(subtitle, style: TextStyle(color: AppPalette.dim, fontSize: 11)),
                ],
              ),
            ),
            if (active)
              Container(
                width: 10, height: 10,
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              ),
          ],
        ),
      ),
    );
  }

  Widget _settingToggle(String title, String sub, bool val, ValueChanged<bool> onChanged) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(color: AppPalette.text, fontWeight: FontWeight.w600)),
              Text(sub, style: const TextStyle(color: AppPalette.dim, fontSize: 12)),
            ],
          ),
        ),
        Switch(value: val, onChanged: onChanged, activeColor: Colors.white),
      ],
    );
  }

  void _showLayerInspector(Map<String, dynamic> layer, Offset localPosition) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final chars = layer['characters']?.toString() ?? '';
        final fontFamily = layer['fontFamily']?.toString() ?? 'Unknown';
        final fontStyle = layer['fontStyle']?.toString() ?? 'Regular';
        final fontSize = layer['fontSize'] ?? 16;
        final color = layer['color']?.toString() ?? '#ffffff';
        final textAlign = layer['textAlign']?.toString() ?? 'LEFT';
        final letterSpacing = layer['letterSpacing'] ?? 0;
        final lineHeight = layer['lineHeight'] ?? 0;
        final opacity = layer['opacity'] ?? 1.0;

        return AlertDialog(
          backgroundColor: AppPalette.card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Layer Inspector', style: TextStyle(color: AppPalette.text, fontSize: 16)),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _inspectorRow('Text', chars),
                const Divider(color: AppPalette.border),
                _inspectorRow('Font', '$fontFamily $fontStyle'),
                _inspectorRow('Size', '${fontSize}px'),
                _inspectorRow('Color', color),
                _inspectorRow('Align', textAlign),
                if (letterSpacing != 0) _inspectorRow('Letter Spacing', '${letterSpacing}px'),
                if (lineHeight != 0) _inspectorRow('Line Height', '${lineHeight}px'),
                _inspectorRow('Opacity', '${(opacity * 100).round()}%'),
                if (layer['x'] != null && layer['y'] != null)
                  _inspectorRow('Position', 'x:${(layer['x'] as num).round()} y:${(layer['y'] as num).round()}'),
                if (layer['width'] != null && layer['height'] != null)
                  _inspectorRow('Size', '${(layer['width'] as num).round()}\u00D7${(layer['height'] as num).round()}'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close', style: TextStyle(color: Colors.white70)),
            ),
          ],
        );
      },
    );
  }

  Widget _inspectorRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(label, style: const TextStyle(color: AppPalette.dim, fontSize: 12)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(color: AppPalette.text, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Map<String, dynamic>? _hitTestTextLayer(Offset imageLocalPos, FrameMetadata meta) {
    for (final layer in meta.textLayers.reversed) {
      final lx = (layer['x'] as num?)?.toDouble() ?? 0;
      final ly = (layer['y'] as num?)?.toDouble() ?? 0;
      final lw = (layer['width'] as num?)?.toDouble() ?? 0;
      final lh = (layer['height'] as num?)?.toDouble() ?? 0;
      if (lx <= imageLocalPos.dx && imageLocalPos.dx <= lx + lw &&
          ly <= imageLocalPos.dy && imageLocalPos.dy <= ly + lh) {
        if ((layer['characters']?.toString() ?? '').trim().isNotEmpty) {
          return layer;
        }
      }
    }
    return null;
  }

  Widget _buildIssueOverlay(FrameMetadata meta, double renderW, double renderH) {
    final issues = widget.controller.issues.value;
    if (issues.isEmpty) return const SizedBox.shrink();
    final scaleX = renderW / meta.frameWidth;
    final scaleY = renderH / meta.frameHeight;
    return ValueListenableBuilder<List<DesignIssue>>(
      valueListenable: widget.controller.issues,
      builder: (_, list, __) {
        return Stack(
          children: list.map((issue) {
            final color = issue.type == 'overflow' ? const Color(0x44FF4757) : const Color(0x44FFA502);
            final borderColor = issue.type == 'overflow' ? const Color(0xAAFF4757) : const Color(0xAAFFA502);
            return Positioned(
              left: issue.x * scaleX,
              top: issue.y * scaleY,
              width: issue.width * scaleX,
              height: issue.height * scaleY,
              child: Container(
                decoration: BoxDecoration(
                  color: color,
                  border: Border.all(color: borderColor, width: 1.5),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildSafeAreaOverlay(FrameMetadata meta, double renderW, double renderH) {
    const topInset = 0.08;  // 8% of frame height for top safe area
    const bottomInset = 0.05; // 5% of frame height for bottom safe area
    final sh = renderH;
    final sw = renderW;
    return Stack(
      children: [
        Positioned(
          top: 0, left: 0, width: sw, height: sh * topInset,
          child: Container(
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: const Color(0xAA22C55E), width: 2)),
              color: const Color(0x2222C55E),
            ),
            child: const Center(child: Text('SAFE', style: TextStyle(color: Color(0xAA22C55E), fontSize: 9, fontWeight: FontWeight.w700))),
          ),
        ),
        Positioned(
          bottom: 0, left: 0, width: sw, height: sh * bottomInset,
          child: Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: const Color(0xAA22C55E), width: 2)),
              color: const Color(0x2222C55E),
            ),
            child: const Center(child: Text('SAFE', style: TextStyle(color: Color(0xAA22C55E), fontSize: 9, fontWeight: FontWeight.w700))),
          ),
        ),
      ],
    );
  }

  Widget _buildGridOverlay(FrameMetadata meta, double renderW, double renderH) {
    const cellSize = 8; // 8x8 px grid cells in design coordinates
    if (meta.frameWidth <= 0 || meta.frameHeight <= 0) return const SizedBox.shrink();
    final cols = (meta.frameWidth / cellSize).ceil();
    final rows = (meta.frameHeight / cellSize).ceil();
    final scaleX = renderW / meta.frameWidth;
    final scaleY = renderH / meta.frameHeight;
    return CustomPaint(
      size: Size(renderW, renderH),
      painter: _GridPainter(cols, rows, cellSize * scaleX, cellSize * scaleY),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _shakeSub?.cancel();
    _toolbarTimer?.cancel();
    _transformationController.dispose();
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: const [SystemUiOverlay.top, SystemUiOverlay.bottom],
    );
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
      ),
      child: MediaQuery(
        data: _showSystemUi
            ? MediaQuery.of(context).copyWith(viewInsets: EdgeInsets.zero)
            : MediaQuery.of(context).copyWith(
                padding: EdgeInsets.zero,
                viewPadding: EdgeInsets.zero,
                viewInsets: EdgeInsets.zero,
              ),
        child: Material(
          color: Colors.black,
          child: ValueListenableBuilder<int>(
            valueListenable: widget.controller.imageVersion,
            builder: (context, _, __) {
              final imageData = widget.controller.currentImageData;
              final meta = widget.controller.currentMetadata;

              Widget content;
              if (imageData == null || meta == null) {
                content = const Center(
                  child: Text(
                    'Waiting for preview...\nSync from plugin to load frame',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppPalette.dim),
                  ),
                );
              } else {
                Uint8List? decodedImage;
                try {
                  decodedImage = base64Decode(imageData.split(',').last);
                } catch (_) {
                  content = const Center(
                    child: Text('Failed to decode image', style: TextStyle(color: AppPalette.dim)),
                  );
                  return const SizedBox.shrink();
                }

                final double imageNaturalWidth = meta.imagePixelsWidth;
                final double imageNaturalHeight = meta.imagePixelsHeight;

                if (_displayMode == DisplayMode.pixelPerfect) {
                  // Pixel-perfect: 1 image pixel = 1 device pixel
                  // Convert to logical pixels by dividing by devicePixelRatio
                  final dpr = MediaQuery.of(context).devicePixelRatio;
                  final double renderWidth = imageNaturalWidth / dpr;
                  final double renderHeight = imageNaturalHeight / dpr;

                  content = GestureDetector(
                    onTapUp: (details) {
                      // Convert tap position to frame-local coordinates
                      final RenderBox? box = _imageKey.currentContext?.findRenderObject() as RenderBox?;
                      if (box == null) return;
                      final localPos = box.globalToLocal(details.globalPosition);
                      final scaleX = meta.frameWidth / renderWidth;
                      final scaleY = meta.frameHeight / renderHeight;
                      final frameLocalPos = Offset(localPos.dx * scaleX, localPos.dy * scaleY);

                      final hitLayer = _hitTestTextLayer(frameLocalPos, meta);
                      if (hitLayer != null) {
                        _showLayerInspector(hitLayer, localPos);
                      }
                    },
                    child: InteractiveViewer(
                      transformationController: _transformationController,
                      minScale: 0.5,
                      maxScale: 8.0,
                      constrained: false,
                      child: Container(
                        color: const Color(0xFF0C0C0C),
                        child: Stack(
                          children: [
                            Image.memory(
                              key: _imageKey,
                              decodedImage,
                              width: renderWidth,
                              height: renderHeight,
                              fit: BoxFit.fill,
                              filterQuality: FilterQuality.high,
                              gaplessPlayback: true,
                            ),
                            // Frame info badge
                            Positioned(
                              top: 12,
                              left: 12,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.7),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '${meta.frameWidth.toInt()}\u00D7${meta.frameHeight.toInt()}px (${meta.exportScale.toInt()}\u00D7)',
                                  style: const TextStyle(color: Colors.white70, fontSize: 10),
                                ),
                              ),
                            ),
                            // Hint for inspector
                            Positioned(
                              top: 12,
                              right: 12,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.7),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text('Tap text to inspect', style: TextStyle(color: Colors.white38, fontSize: 10)),
                              ),
                            ),
                            if (_showIssues) _buildIssueOverlay(meta, renderWidth, renderHeight),
                            if (_showSafeArea) _buildSafeAreaOverlay(meta, renderWidth, renderHeight),
                            if (_showGrid) _buildGridOverlay(meta, renderWidth, renderHeight),
                          ],
                        ),
                      ),
                    ),
                  );
                } else {
                  // Fit to screen mode
                  content = GestureDetector(
                    onTapUp: (details) {
                      if (meta.textLayers.isEmpty) return;
                      final RenderBox? box = _imageKey.currentContext?.findRenderObject() as RenderBox?;
                      if (box == null) return;
                      final localPos = box.globalToLocal(details.globalPosition);
                      final scaleX = meta.frameWidth / screenWidth;
                      final scaleY = meta.frameHeight / (screenWidth * (meta.frameHeight / meta.frameWidth));
                      final frameLocalPos = Offset(localPos.dx * scaleX, localPos.dy * scaleY);

                      final hitLayer = _hitTestTextLayer(frameLocalPos, meta);
                      if (hitLayer != null) {
                        _showLayerInspector(hitLayer, localPos);
                      }
                    },
                    child: InteractiveViewer(
                      transformationController: _transformationController,
                      minScale: 1.0,
                      maxScale: 4.0,
                      child: SingleChildScrollView(
                        padding: EdgeInsets.zero,
                        physics: const ClampingScrollPhysics(),
                        child: Stack(
                          children: [
                            Image.memory(
                              key: _imageKey,
                              decodedImage,
                              width: screenWidth,
                              fit: BoxFit.fitWidth,
                              filterQuality: FilterQuality.high,
                              gaplessPlayback: true,
                            ),
                            if (_showIssues) _buildIssueOverlay(meta, screenWidth, screenWidth * (meta.frameHeight / meta.frameWidth)),
                            if (_showSafeArea) _buildSafeAreaOverlay(meta, screenWidth, screenWidth * (meta.frameHeight / meta.frameWidth)),
                            if (_showGrid) _buildGridOverlay(meta, screenWidth, screenWidth * (meta.frameHeight / meta.frameWidth)),
                          ],
                        ),
                      ),
                    ),
                  );
                }
              }

              return Stack(
                children: [
                  GestureDetector(
                    onTap: _toggleToolbar,
                    onDoubleTap: () {
                      _transformationController.value = Matrix4.identity();
                      widget.controller.requestManualSync();
                    },
                    onHorizontalDragEnd: (details) {
                      final v = details.primaryVelocity ?? 0;
                      if (v > 80) {
                        widget.controller.requestNavigate('prev');
                      } else if (v < -80) {
                        widget.controller.requestNavigate('next');
                      }
                    },
                    child: Container(
                      color: Colors.black,
                      child: _showSystemUi ? SafeArea(child: content) : content,
                    ),
                  ),
                  // Top-left badges: frame info + viewer count
                  if (imageData != null && meta != null)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          GestureDetector(
                            onTap: _toggleToolbar,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(color: Colors.black.withOpacity(0.6), borderRadius: BorderRadius.circular(6)),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('${meta.frameWidth.toInt()}\u00D7${meta.frameHeight.toInt()}', style: const TextStyle(color: Colors.white54, fontSize: 10)),
                                  const SizedBox(width: 6),
                                  Text(_selectedPreset.name, style: const TextStyle(color: Colors.white38, fontSize: 9)),
                                ],
                              ),
                            ),
                          ),
                          if (widget.controller.serverLabel == 'Cloud')
                            ValueListenableBuilder<int>(
                              valueListenable: widget.controller.viewerCount,
                              builder: (_, count, __) {
                                if (count <= 0) return const SizedBox.shrink();
                                return Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(color: const Color(0x9922C55E), borderRadius: BorderRadius.circular(6)),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.people_alt_rounded, size: 12, color: Colors.white),
                                        const SizedBox(width: 4),
                                        Text('$count', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                  // Issue badge
                  if (imageData != null && meta != null)
                    Positioned(
                      bottom: 12,
                      left: 12,
                      child: ValueListenableBuilder<List<DesignIssue>>(
                        valueListenable: widget.controller.issues,
                        builder: (_, issues, __) {
                          if (issues.isEmpty) return const SizedBox.shrink();
                          return GestureDetector(
                            onTap: () => setState(() => _showIssues = !_showIssues),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                              decoration: BoxDecoration(
                                color: issues.any((i) => i.type == 'overflow') ? const Color(0xCCFF4757) : const Color(0xCCFFA502),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.warning_amber_rounded, size: 14, color: Colors.white),
                                  const SizedBox(width: 6),
                                  Text('${issues.length}', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  // Connection quality indicator (top right)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: ValueListenableBuilder<ConnectionQuality>(
                      valueListenable: widget.controller.connectionQuality,
                      builder: (_, q, __) {
                        final (color, label) = switch (q) {
                          ConnectionQuality.good => (const Color(0xFF22C55E), 'Good'),
                          ConnectionQuality.fair => (const Color(0xFFEAB308), 'Fair'),
                          ConnectionQuality.poor => (const Color(0xFFEF4444), 'Poor'),
                          ConnectionQuality.disconnected => (AppPalette.dim, 'Disconnected'),
                        };
                        return GestureDetector(
                          onTap: _toggleToolbar,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(color: Colors.black.withOpacity(0.6), borderRadius: BorderRadius.circular(6)),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                                const SizedBox(width: 4),
                                Text(label, style: const TextStyle(color: Colors.white54, fontSize: 9)),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  // Reconnecting overlay
                  ValueListenableBuilder<ConnectionQuality>(
                    valueListenable: widget.controller.connectionQuality,
                    builder: (_, q, __) {
                      if (q == ConnectionQuality.good || q == ConnectionQuality.fair) return const SizedBox.shrink();
                      return Positioned(
                        top: 0, left: 0, right: 0, bottom: 0,
                        child: GestureDetector(
                          onTap: _toggleToolbar,
                          child: Container(
                            color: Colors.black54,
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(width: 32, height: 32, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70)),
                                  const SizedBox(height: 12),
                                  Text(
                                    q == ConnectionQuality.disconnected ? 'Reconnecting...' : 'Weak connection',
                                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                                  ),
                                  ValueListenableBuilder<int>(
                                    valueListenable: widget.controller.latencyMs,
                                    builder: (_, lat, __) => lat > 0
                                      ? Text('${lat}ms latency', style: const TextStyle(color: Colors.white38, fontSize: 12))
                                      : const SizedBox.shrink(),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  // Bottom toolbar
                  AnimatedOpacity(
                    opacity: _showToolbar ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 250),
                    child: Visibility(
                      visible: _showToolbar,
                      child: SafeArea(
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 40),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.8),
                                borderRadius: BorderRadius.circular(99),
                                border: Border.all(color: Colors.white24, width: 0.5),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Quality dot
                                  ValueListenableBuilder<ConnectionQuality>(
                                    valueListenable: widget.controller.connectionQuality,
                                    builder: (_, q, __) {
                                      final c = q == ConnectionQuality.good ? const Color(0xFF22C55E)
                                        : q == ConnectionQuality.fair ? const Color(0xFFEAB308)
                                        : q == ConnectionQuality.poor ? const Color(0xFFEF4444)
                                        : AppPalette.dim;
                                      return Container(
                                        width: 8, height: 8, margin: const EdgeInsets.symmetric(horizontal: 8),
                                        decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                                      );
                                    },
                                  ),
                                  if (widget.controller.serverLabel == 'Cloud')
                                    ValueListenableBuilder<int>(
                                      valueListenable: widget.controller.viewerCount,
                                      builder: (_, count, __) {
                                        final label = count > 1 ? '$count viewers' : count == 1 ? '1 viewer' : '';
                                        if (label.isEmpty) return const SizedBox.shrink();
                                        return Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 4),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: const Color(0x3322C55E),
                                              borderRadius: BorderRadius.circular(12),
                                              border: Border.all(color: const Color(0x5522C55E)),
                                            ),
                                            child: Text(label, style: const TextStyle(color: Color(0xCC22C55E), fontSize: 10, fontWeight: FontWeight.w600)),
                                          ),
                                        );
                                      },
                                    ),
                                  _toolBtn(Icons.close, () => Navigator.of(context).pop()),
                                  const SizedBox(width: 8),
                                  _toolBtn(Icons.refresh, () { widget.controller.requestManualSync(); _startToolbarTimer(); }),
                                  const SizedBox(width: 8),
                                  _toolBtn(_displayMode == DisplayMode.pixelPerfect ? Icons.fit_screen : Icons.one_x_mobiledata, () {
                                    setState(() => _displayMode = _displayMode == DisplayMode.fitToScreen ? DisplayMode.pixelPerfect : DisplayMode.fitToScreen);
                                    _transformationController.value = Matrix4.identity();
                                    _startToolbarTimer();
                                  }),
                                  const SizedBox(width: 8),
                                  _toolBtn(Icons.history, () { _showHistory(); _startToolbarTimer(); }),
                                  const SizedBox(width: 8),
                                  _toolBtn(Icons.settings, () { _showSettings(); _startToolbarTimer(); }),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _toolBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44, height: 44,
        decoration: const BoxDecoration(color: AppPalette.card, shape: BoxShape.circle),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  final int cols;
  final int rows;
  final double cellW;
  final double cellH;

  _GridPainter(this.cols, this.rows, this.cellW, this.cellH);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x3322C55E)
      ..strokeWidth = 0.5;
    for (int i = 0; i <= cols; i++) {
      final x = i * cellW;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (int i = 0; i <= rows; i++) {
      final y = i * cellH;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter old) =>
      old.cols != cols || old.rows != rows || old.cellW != cellW || old.cellH != cellH;
}

Widget _card({required Widget child}) {
  return Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppPalette.card,
      border: Border.all(color: AppPalette.border),
      borderRadius: BorderRadius.circular(16),
    ),
    child: child,
  );
}

const _h = TextStyle(color: AppPalette.text, fontSize: 18, fontWeight: FontWeight.w700);
