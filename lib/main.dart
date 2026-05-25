import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:share_plus/share_plus.dart';
import 'auth_screen.dart';
import 'auth_safe.dart';
import 'logger.dart';
import 'premium.dart';
import 'device_manager_screen.dart';
import 'subscription_screen.dart';
import 'profile_screen.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:flutter/services.dart';
import 'quick_pairing_screen.dart';

part 'home_screen.dart';
part 'settings_screen.dart';
part 'connected_devices_screen.dart';

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
    'ip': ip,
    'port': port.toString(),
    'roomId': roomId,
    'roomSecret': roomSecret,
  };
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
    ui.PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
    // Sync plan on auth changes (fires on app start if already logged in)
    FirebaseAuth.instance.authStateChanges().listen((_) {
      PremiumManager.syncFromServer().catchError((_) {});
    });
  } catch (e, st) {
    SeeloConfig.firebaseAvailable = false;
    logError(e, st);
  }
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
  static bool firebaseAvailable = true;

  static final ValueNotifier<bool> darkMode = ValueNotifier(false);
  static final ValueNotifier<bool> compactMode = ValueNotifier(false);
  static final ValueNotifier<bool> showDebugErrorBoxes = ValueNotifier(true);
  static double gap({double normal = 24, double compact = 12}) =>
      compactMode.value ? compact : normal;
  static double smGap({double normal = 16, double compact = 8}) =>
      compactMode.value ? compact : normal;
  static double cardPad({double normal = 24, double compact = 16}) =>
      compactMode.value ? compact : normal;

  static final SeeloConfig _instance = SeeloConfig._();
  factory SeeloConfig() => _instance;
  SeeloConfig._();
}

class SeeloApp extends StatefulWidget {
  const SeeloApp({super.key});

  @override
  State<SeeloApp> createState() => _SeeloAppState();
}

class _SeeloAppState extends State<SeeloApp> {
  StreamSubscription? _authSub;
  AuthService? _authService;

  @override
  void initState() {
    super.initState();
    if (!SeeloConfig.firebaseAvailable) return;
    try {
      _authService = AuthService();
      _authSub = _authService!.authState.listen(
        (_) => setState(() {}),
      );
    } catch (e, st) {
      logError(e, st);
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: SeeloConfig.showDebugErrorBoxes,
      builder: (_, showDebugErrors, _) {
        // Lets users hide noisy red error widgets during preview in debug builds.
        if (kDebugMode && !showDebugErrors) {
          ErrorWidget.builder = (FlutterErrorDetails details) => Container(
            color: const Color(0xFFF9F9F9),
            alignment: Alignment.center,
            padding: const EdgeInsets.all(16),
            child: const Text(
              'A preview error was hidden. Enable "Debug Error Boxes" in Settings to view details.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF626262),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          );
        } else {
          ErrorWidget.builder = (FlutterErrorDetails details) =>
              ErrorWidget.withDetails(message: details.exceptionAsString());
        }
        return ValueListenableBuilder<bool>(
          valueListenable: SeeloConfig.darkMode,
          builder: (_, isDark, _) {
            return MaterialApp(
              title: 'Seelo',
              debugShowCheckedModeBanner: false,
              home: SeeloConfig.firebaseAvailable && safeCurrentUser() == null
                  ? const AuthScreen()
                  : const SplashScreen(),
              theme: ThemeData(
                scaffoldBackgroundColor: const Color(0xFFF9F9F9),
                appBarTheme: const AppBarTheme(
                  backgroundColor: Color(0xFFF9F9F9),
                  surfaceTintColor: Colors.transparent,
                  elevation: 0,
                  foregroundColor: Color(0xFF1A1C1C),
                ),
                colorScheme: const ColorScheme.light(
                  primary: Color(0xFF000000),
                  onPrimary: Color(0xFFFFFFFF),
                  surface: Color(0xFFF9F9F9),
                  onSurface: Color(0xFF1A1C1C),
                ),
              ),
              darkTheme: ThemeData(
                scaffoldBackgroundColor: const Color(0xFF0C0C0C),
                appBarTheme: const AppBarTheme(
                  backgroundColor: Color(0xFF0C0C0C),
                  surfaceTintColor: Colors.transparent,
                  elevation: 0,
                  foregroundColor: Color(0xFFF3F3F3),
                ),
                colorScheme: const ColorScheme.dark(
                  primary: Color(0xFFFFFFFF),
                  onPrimary: Color(0xFF000000),
                  surface: Color(0xFF0C0C0C),
                  onSurface: Color(0xFFF3F3F3),
                ),
              ),
              themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
            );
          },
        );
      },
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
  final String suggestion;
  final double x, y, width, height;
  final String? layerName;
  DesignIssue({
    required this.type,
    required this.message,
    this.suggestion = '',
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.layerName,
  });
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

  String get label =>
      '$name (${screenWidth.toInt()}\u00D7${screenHeight.toInt()})';
}

const builtInPresets = [
  DevicePreset(
    name: 'iPhone 15 Pro Max',
    screenWidth: 430,
    screenHeight: 932,
    dpr: 3.0,
    exportScale: 3.0,
  ),
  DevicePreset(
    name: 'iPhone 15 Pro',
    screenWidth: 393,
    screenHeight: 852,
    dpr: 3.0,
    exportScale: 3.0,
  ),
  DevicePreset(
    name: 'iPhone 15',
    screenWidth: 393,
    screenHeight: 852,
    dpr: 2.94,
    exportScale: 3.0,
  ),
  DevicePreset(
    name: 'iPhone SE',
    screenWidth: 375,
    screenHeight: 667,
    dpr: 2.0,
    exportScale: 2.0,
  ),
  DevicePreset(
    name: 'Pixel 8 Pro',
    screenWidth: 412,
    screenHeight: 915,
    dpr: 3.5,
    exportScale: 3.0,
  ),
  DevicePreset(
    name: 'Pixel 8',
    screenWidth: 392,
    screenHeight: 852,
    dpr: 2.63,
    exportScale: 3.0,
  ),
  DevicePreset(
    name: 'Galaxy S24',
    screenWidth: 412,
    screenHeight: 915,
    dpr: 3.0,
    exportScale: 3.0,
  ),
  DevicePreset(
    name: 'Galaxy S24 Ultra',
    screenWidth: 412,
    screenHeight: 915,
    dpr: 3.69,
    exportScale: 3.0,
  ),
  DevicePreset(
    name: 'iPad Pro 12.9"',
    screenWidth: 1024,
    screenHeight: 1366,
    dpr: 2.0,
    exportScale: 2.0,
  ),
  DevicePreset(
    name: 'iPad Air 11"',
    screenWidth: 820,
    screenHeight: 1180,
    dpr: 2.0,
    exportScale: 2.0,
  ),
  DevicePreset(
    name: 'Desktop HD',
    screenWidth: 1440,
    screenHeight: 900,
    dpr: 1.0,
    exportScale: 1.0,
  ),
  DevicePreset(
    name: 'Desktop FHD',
    screenWidth: 1920,
    screenHeight: 1080,
    dpr: 1.0,
    exportScale: 1.0,
  ),
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
  String? previousImageData;
  FrameMetadata? previousMetadata;
  String? _lastFrameId;

  final ValueNotifier<int> imageVersion = ValueNotifier<int>(0);
  final ValueNotifier<FrameMetadata?> metadataNotifier =
      ValueNotifier<FrameMetadata?>(null);
  final ValueNotifier<ConnectionQuality> connectionQuality = ValueNotifier(
    ConnectionQuality.disconnected,
  );
  final ValueNotifier<int> latencyMs = ValueNotifier(0);
  final ValueNotifier<List<SavedDevice>> savedDevices = ValueNotifier([]);
  final ValueNotifier<List<DesignIssue>> issues = ValueNotifier([]);
  final ValueNotifier<int> viewerCount = ValueNotifier(0);
  final ValueNotifier<String?> lastError = ValueNotifier<String?>(null);
  final ValueNotifier<List<Map<String, dynamic>>> frameGallery = ValueNotifier(
    [],
  );
  final ValueNotifier<List<Map<String, dynamic>>> notes = ValueNotifier([]);
  final List<SessionEntry> sessionHistory = [];
  final List<DevicePreset> customPresets = [];

  Timer? _designTimeout;
  Timer? _pingTimer;
  void Function(int max, int current)? _onRoomFull;
  int _reconnectCount = 0;
  double _latencyEma = 0;

  static const int _maxSavedDevices = 5;

  void _saveDevice(String ip, int port) {
    final devices = List<SavedDevice>.from(savedDevices.value);
    devices.removeWhere((d) => d.ip == ip && d.port == port);
    devices.insert(
      0,
      SavedDevice(
        ip: ip,
        port: port,
        roomId: roomId,
        roomSecret: roomSecret,
        lastUsed: DateTime.now(),
      ),
    );
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

  void connectWithPayload({
    required Map<String, dynamic> payload,
    VoidCallback? onConnected,
    void Function(String message)? onError,
    void Function(String message)? onStatus,
  }) {
    _connectWithPayloadInternal(
      payload,
      onConnected: onConnected,
      onError: onError,
      onStatus: onStatus,
    );
  }

  void _connectToRelay(
    String relayUrl,
    String sessionId, {
    VoidCallback? onConnected,
    void Function(String message)? onError,
    void Function(String message)? onStatus,
  }) {
    lastError.value = null;
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
          .setTransports(['websocket', 'polling'])
          .enableReconnection()
          .setReconnectionAttempts(config.reconnectAttempts)
          .setReconnectionDelay(config.reconnectDelay)
          .setReconnectionDelayMax(3000)
          .setTimeout(20000)
          .build(),
    );
    _socket = socket;

    socket.onConnect((_) async {
      if (_disposed) return;
      connecting = false;
      _reconnectCount = 0;
      connectionQuality.value = ConnectionQuality.good;
      viewerCount.value = 0;
      sessionHistory.insert(
        0,
        SessionEntry(
          'Cloud: ${sessionId.length > 8 ? sessionId.substring(0, 8) : sessionId}...',
          DateTime.now(),
          isCloud: true,
        ),
      );
      final payload = <String, dynamic>{
        'sessionId': sessionId,
        'role': 'viewer',
      };
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          payload['uid'] = user.uid;
          payload['idToken'] = await user.getIdToken();
        }
      } catch (e, st) {
        logError(e, st);
      }
      socket.emit('join-session', payload);
      onConnected?.call();
      onStatus?.call('Cloud connected');
    });

    socket.on('cloud-design', (payload) {
      if (_disposed) return;
      try {
        final design = payload is Map ? payload : null;
        if (design is Map) {
          if (design['frameGallery'] is List) {
            frameGallery.value = List<Map<String, dynamic>>.from(
              (design['frameGallery'] as List).map(
                (e) => Map<String, dynamic>.from(e as Map),
              ),
            );
          }
          final imageData = design['imageData'];
          final newId = design['id']?.toString();
          if (imageData is String && imageData.startsWith('data:image')) {
            previousImageData = currentImageData;
            previousMetadata = currentMetadata;
            _lastFrameId = newId;
            currentImageData = imageData;
            currentMetadata = FrameMetadata(
              id: newId,
              projectId: design['projectId']?.toString(),
              frameWidth: (design['width'] ?? 0).toDouble(),
              frameHeight: (design['height'] ?? 0).toDouble(),
              exportScale: (design['exportScale'] ?? 2).toDouble(),
              backgroundColor: design['backgroundColor']?.toString(),
              textLayers: (design['textLayers'] is List
                  ? List<Map<String, dynamic>>.from(
                      design['textLayers'].map(
                        (e) => Map<String, dynamic>.from(e),
                      ),
                    )
                  : []),
              videoLayers: (design['videoLayers'] is List
                  ? List<Map<String, dynamic>>.from(
                      design['videoLayers'].map(
                        (e) => Map<String, dynamic>.from(e),
                      ),
                    )
                  : []),
              imageData: imageData,
            );
            metadataNotifier.value = currentMetadata;
            imageVersion.value++;
          }
        }
      } catch (e, st) {
        logError(e, st);
      }
      _designTimeout?.cancel();
      onStatus?.call('Preview synced');
    });

    socket.on('viewer-count', (count) {
      if (_disposed) return;
      viewerCount.value = (count is num) ? count.toInt() : 0;
    });

    socket.on('room-full', (data) {
      if (_disposed) return;
      final max = data is Map ? (data['max'] ?? 1) : 1;
      final current = data is Map ? (data['current'] ?? 0) : 0;
      final msg = 'Device limit reached ($current/$max)';
      lastError.value = msg;
      onError?.call(msg);
      onStatus?.call('Max $max device(s)');
      socket.disconnect();
      _onRoomFull?.call(max, current);
    });

    socket.on('device-replaced', (data) {
      if (_disposed) return;
      final msg = data is Map
          ? (data['message'] ?? 'Connected from another device')
          : 'Connected from another device';
      lastError.value = msg;
      onError?.call(msg);
      onStatus?.call('Replaced by new device');
      socket.disconnect();
    });

    socket.on('rate-limited', (data) {
      if (_disposed) return;
      final msg = data is Map ? (data['message'] ?? 'Slow down') : 'Slow down';
      onStatus?.call(msg);
    });

    socket.on('frame-list', (data) {
      if (_disposed) return;
      if (data is Map && data['frames'] is List) {
        frameGallery.value = List<Map<String, dynamic>>.from(
          data['frames'].map((e) => Map<String, dynamic>.from(e)),
        );
      } else if (data is List) {
        frameGallery.value = List<Map<String, dynamic>>.from(
          data.map((e) => Map<String, dynamic>.from(e)),
        );
      }
    });

    socket.on('note-added', (data) {
      if (_disposed) return;
      if (data is Map && data['note'] is Map) {
        final list = List<Map<String, dynamic>>.from(notes.value);
        list.add(Map<String, dynamic>.from(data['note']));
        notes.value = list;
      }
    });

    socket.on('existing-notes', (data) {
      if (_disposed) return;
      if (data is Map && data['notes'] is List) {
        notes.value = List<Map<String, dynamic>>.from(
          data['notes'].map((e) => Map<String, dynamic>.from(e)),
        );
      }
    });

    socket.on('note-deleted', (data) {
      if (_disposed) return;
      if (data is Map && data['noteId'] != null) {
        notes.value = notes.value
            .where((n) => n['id']?.toString() != data['noteId'].toString())
            .toList();
      }
    });

    socket.on('server-shutdown', (_) {
      if (_disposed) return;
      onStatus?.call('Server restarting...');
      socket.disconnect();
    });

    socket.onConnectError((err) {
      if (_disposed) return;
      connecting = false;
      _reconnectCount++;
      connectionQuality.value = ConnectionQuality.poor;
      logMessage('Seelo cloud connectError: $err');
      onError?.call('Cloud connection error: $err');
      onStatus?.call('Retrying ($_reconnectCount)');
    });

    socket.onDisconnect((_) {
      if (_disposed) return;
      connectionQuality.value = ConnectionQuality.disconnected;
      onStatus?.call('Disconnected');
    });

    socket.onReconnect((_) async {
      if (_disposed) return;
      connectionQuality.value = ConnectionQuality.good;
      final payload = <String, dynamic>{
        'sessionId': sessionId,
        'role': 'viewer',
      };
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          payload['uid'] = user.uid;
          payload['idToken'] = await user.getIdToken();
        }
      } catch (e, st) {
        logError(e, st);
      }
      socket.emit('join-session', payload);
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

  void _connectWithPayloadInternal(
    Map<String, dynamic> payload, {
    VoidCallback? onConnected,
    void Function(String message)? onError,
    void Function(String message)? onStatus,
  }) {
    final relay = (payload['relay'] ?? '').toString().trim();
    if (relay.isNotEmpty) {
      _connectToRelay(
        relay,
        (payload['sessionId'] ?? '').toString(),
        onConnected: onConnected,
        onError: onError,
        onStatus: onStatus,
      );
      return;
    }
    final ip = (payload['ip'] ?? '').toString().trim();
    final port =
        int.tryParse(
          (payload['port'] ?? SeeloConfig().defaultPort).toString(),
        ) ??
        SeeloConfig().defaultPort;
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

    Future<void> joinAndRequestSync() async {
      final payload = <String, dynamic>{'sessionId': roomId, 'role': 'viewer'};
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          payload['uid'] = user.uid;
          payload['idToken'] = await user.getIdToken();
        }
      } catch (e, st) {
        logError(e, st);
      }
      socket.emit('join-session', payload);
    }

    socket.onConnect((_) async {
      if (_disposed) return;
      serverLabel = '$ip:$port';
      _reconnectCount = 0;
      _latencyEma = 0;
      connectionQuality.value = ConnectionQuality.good;
      _saveDevice(ip, port);
      sessionHistory.insert(
        0,
        SessionEntry('Desktop: $ip:$port', DateTime.now()),
      );
      await joinAndRequestSync();
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
          if (design['frameGallery'] is List) {
            frameGallery.value = List<Map<String, dynamic>>.from(
              (design['frameGallery'] as List).map(
                (e) => Map<String, dynamic>.from(e as Map),
              ),
            );
          }
          final imageData = design['imageData'];
          final newId = design['id']?.toString();
          // Frame dedup: skip re-render if same frame ID
          if (newId != null &&
              newId == _lastFrameId &&
              imageData != null &&
              imageData == currentImageData) {
            return;
          }
          if (imageData is String && imageData.startsWith('data:image')) {
            previousImageData = currentImageData;
            previousMetadata = currentMetadata;
            _lastFrameId = newId;
            currentImageData = imageData;
            currentMetadata = FrameMetadata(
              id: newId,
              projectId: design['projectId']?.toString(),
              frameWidth: (design['width'] ?? 0).toDouble(),
              frameHeight: (design['height'] ?? 0).toDouble(),
              exportScale: (design['exportScale'] ?? 2).toDouble(),
              backgroundColor: design['backgroundColor']?.toString(),
              textLayers: (design['textLayers'] is List
                  ? List<Map<String, dynamic>>.from(
                      design['textLayers'].map(
                        (e) => Map<String, dynamic>.from(e),
                      ),
                    )
                  : []),
              videoLayers: (design['videoLayers'] is List
                  ? List<Map<String, dynamic>>.from(
                      design['videoLayers'].map(
                        (e) => Map<String, dynamic>.from(e),
                      ),
                    )
                  : []),
              imageData: imageData,
            );
            metadataNotifier.value = currentMetadata;
            imageVersion.value++;
            _detectIssues();
          }
        }
      } catch (e, st) {
        logError(e, st);
      }
      _designTimeout?.cancel();
      onStatus?.call('Preview synced');
    });

    socket.on('error-msg', (payload) {
      if (_disposed) return;
      final msg = payload is Map
          ? (payload['message'] ?? 'Server error').toString()
          : 'Server error';
      onError?.call(msg);
    });

    socket.on('frame-list', (data) {
      if (_disposed) return;
      if (data is Map && data['frames'] is List) {
        frameGallery.value = List<Map<String, dynamic>>.from(
          data['frames'].map((e) => Map<String, dynamic>.from(e)),
        );
      } else if (data is List) {
        frameGallery.value = List<Map<String, dynamic>>.from(
          data.map((e) => Map<String, dynamic>.from(e)),
        );
      }
    });

    socket.on('note-added', (data) {
      if (_disposed) return;
      if (data is Map && data['note'] is Map) {
        final list = List<Map<String, dynamic>>.from(notes.value);
        list.add(Map<String, dynamic>.from(data['note']));
        notes.value = list;
      }
    });

    socket.on('existing-notes', (data) {
      if (_disposed) return;
      if (data is Map && data['notes'] is List) {
        notes.value = List<Map<String, dynamic>>.from(
          data['notes'].map((e) => Map<String, dynamic>.from(e)),
        );
      }
    });

    socket.on('note-deleted', (data) {
      if (_disposed) return;
      if (data is Map && data['noteId'] != null) {
        notes.value = notes.value
            .where((n) => n['id']?.toString() != data['noteId'].toString())
            .toList();
      }
    });

    socket.on('server-shutdown', (_) {
      if (_disposed) return;
      onStatus?.call('Server restarting...');
      socket.disconnect();
    });

    socket.onConnectError((err) {
      if (_disposed) return;
      connecting = false;
      _reconnectCount++;
      connectionQuality.value = ConnectionQuality.poor;
      logMessage('Seelo desktop connectError: $err');
      onError?.call('Desktop connection error: $err');
      onStatus?.call('Retrying ($_reconnectCount)');
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
    if (meta == null) {
      issues.value = list;
      return;
    }
    final fw = meta.frameWidth;
    final fh = meta.frameHeight;
    for (final layer in meta.textLayers) {
      final lx = (layer['x'] as num?)?.toDouble() ?? 0;
      final ly = (layer['y'] as num?)?.toDouble() ?? 0;
      final lw = (layer['width'] as num?)?.toDouble() ?? 0;
      final lh = (layer['height'] as num?)?.toDouble() ?? 0;
      final name = layer['characters']?.toString() ?? '';
      if (lw > fw && fw > 0) {
        list.add(
          DesignIssue(
            type: 'overflow',
            message: 'Text wider than frame: "$name"',
            suggestion:
                'Reduce font size or wrap text to fit within $fw\xD7$fh frame',
            x: lx,
            y: ly,
            width: lw,
            height: lh,
            layerName: name,
          ),
        );
      }
      if (lx + lw > fw && fw > 0) {
        list.add(
          DesignIssue(
            type: 'overflow',
            message: 'Text extends past right edge',
            suggestion:
                'Move text layer left or reduce width to fit within frame boundary',
            x: lx,
            y: ly,
            width: lw,
            height: lh,
            layerName: name,
          ),
        );
      }
      if (ly + lh > fh && fh > 0) {
        list.add(
          DesignIssue(
            type: 'overflow',
            message: 'Text extends past bottom edge',
            suggestion:
                'Move text layer up or reduce height to stay within frame',
            x: lx,
            y: ly,
            width: lw,
            height: lh,
            layerName: name,
          ),
        );
      }
    }
    for (int i = 0; i < meta.textLayers.length; i++) {
      for (int j = i + 1; j < meta.textLayers.length; j++) {
        final a = meta.textLayers[i];
        final b = meta.textLayers[j];
        final ax = (a['x'] as num?)?.toDouble() ?? 0;
        final ay = (a['y'] as num?)?.toDouble() ?? 0;
        final aw = (a['width'] as num?)?.toDouble() ?? 0;
        final ah = (a['height'] as num?)?.toDouble() ?? 0;
        final bx = (b['x'] as num?)?.toDouble() ?? 0;
        final by = (b['y'] as num?)?.toDouble() ?? 0;
        final bw = (b['width'] as num?)?.toDouble() ?? 0;
        final bh = (b['height'] as num?)?.toDouble() ?? 0;
        if (ax < bx + bw && ax + aw > bx && ay < by + bh && ay + ah > by) {
          list.add(
            DesignIssue(
              type: 'overlap',
              message: 'Text layers overlap',
              suggestion:
                  'Reposition layers to avoid overlap, or use auto-layout',
              x: ax,
              y: ay,
              width: aw,
              height: ah,
              layerName: a['characters']?.toString() ?? '',
            ),
          );
          break;
        }
      }
    }
    // Unsafe spacing check — check if text is too close to safe zone
    for (final layer in meta.textLayers) {
      final lx = (layer['x'] as num?)?.toDouble() ?? 0;
      final ly = (layer['y'] as num?)?.toDouble() ?? 0;
      final lw = (layer['width'] as num?)?.toDouble() ?? 0;
      final lh = (layer['height'] as num?)?.toDouble() ?? 0;
      final name = layer['characters']?.toString() ?? '';
      final unsafeTop = fh * 0.08;
      final unsafeBottom = fh * 0.92;
      if (ly < unsafeTop && ly + lh > 0) {
        list.add(
          DesignIssue(
            type: 'spacing',
            message: 'Text in top unsafe area',
            suggestion:
                'Move text below ${unsafeTop.toInt()}px to avoid notch overlap',
            x: lx,
            y: ly,
            width: lw,
            height: lh,
            layerName: name,
          ),
        );
      }
      if (ly + lh > unsafeBottom) {
        list.add(
          DesignIssue(
            type: 'spacing',
            message: 'Text in bottom unsafe area',
            suggestion:
                'Move text above ${unsafeBottom.toInt()}px to avoid home indicator',
            x: lx,
            y: ly,
            width: lw,
            height: lh,
            layerName: name,
          ),
        );
      }
    }
    issues.value = list;
  }

  void _startPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!isConnected || _disposed) return;
      _socket!.emit('latency-probe', {
        'ts': DateTime.now().millisecondsSinceEpoch,
      });
    });
    _socket!.off('latency-ack');
    _socket!.on('latency-ack', (data) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final serverTs = (data is Map) ? data['ts'] : data;
      if (serverTs is! num) return;
      final ms = now - serverTs.toInt();
      if (ms < 0 || ms > 3000) return; // ignore clock glitches or stale replies
      if (_latencyEma == 0) {
        _latencyEma = ms.toDouble();
      } else {
        _latencyEma = (_latencyEma * 0.75) + (ms * 0.25);
      }
      final smooth = _latencyEma.round();
      latencyMs.value = smooth;
      connectionQuality.value = smooth < 40
          ? ConnectionQuality.good
          : smooth < 120
          ? ConnectionQuality.fair
          : ConnectionQuality.poor;
    });
    _socket!.off('pong');
    _socket!.on('pong', (data) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final serverTs = (data is Map) ? data['ts'] : data;
      if (serverTs is! num) return;
      final ms = now - serverTs.toInt();
      if (ms < 0 || ms > 3000) return;
      if (_latencyEma == 0) {
        _latencyEma = ms.toDouble();
      } else {
        _latencyEma = (_latencyEma * 0.75) + (ms * 0.25);
      }
      final smooth = _latencyEma.round();
      latencyMs.value = smooth;
      connectionQuality.value = smooth < 40
          ? ConnectionQuality.good
          : smooth < 120
          ? ConnectionQuality.fair
          : ConnectionQuality.poor;
    });
  }

  void requestNavigate(String direction) {
    if (!isConnected) return;
    _socket!.emit('navigate-frame', {
      'type': 'navigate-frame',
      'direction': direction,
      'roomId': roomId,
      'roomSecret': roomSecret,
    });
  }

  void requestManualSync() {
    if (!isConnected) return;
    final config = SeeloConfig();
    _socket!.emit('request-resize', {
      'type': 'resize-frame',
      'name': 'Seelo Mobile',
      'width': config.screenWidth,
      'height': config.screenHeight,
      'roomId': roomId,
      'roomSecret': roomSecret,
    });
  }

  void requestFrameSelect(String frameId) {
    if (!isConnected) return;
    _socket!.emit('frame-select', {'frameId': frameId, 'sessionId': roomId});
  }

  void addNote(Map<String, dynamic> note) {
    if (!isConnected) return;
    _socket!.emit('add-note', {'note': note, 'sessionId': roomId});
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
    frameGallery.value = [];
    notes.value = [];
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
      final nav = Navigator.of(context);
      if (safeCurrentUser() != null) {
        nav.pushReplacement(
          MaterialPageRoute(builder: (_) => const OnboardingScreen()),
        );
      } else if (SeeloConfig.firebaseAvailable) {
        nav.pushReplacement(
          MaterialPageRoute(builder: (_) => const AuthScreen()),
        );
      } else {
        nav.pushReplacement(
          MaterialPageRoute(builder: (_) => const OnboardingScreen()),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Text(
          'Seelo',
          style: TextStyle(
            color: AppPalette.white,
            fontWeight: FontWeight.w800,
            fontSize: 40,
            letterSpacing: 1,
          ),
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

  static const _slides = [
    _SlideData(
      icon: Icons.design_services_outlined,
      title: 'Live Figma Preview',
      body:
          'Experience your Figma frames live on your phone with real-time local sync.',
    ),
    _SlideData(
      icon: Icons.bluetooth_searching_rounded,
      title: 'Quick Pairing',
      body: 'Bluetooth discovery for instant connection to your desktop app.',
    ),
    _SlideData(
      icon: Icons.swipe_rounded,
      title: 'Swipe And Review',
      body: 'Navigate pages left-right and scroll vertically for long screens.',
    ),
  ];

  void _finish() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) =>
            SeeloHomeScreen(controller: SeeloConnectionController()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F9F9),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              // Step progress
              Text(
                'STEP ${_index + 1} OF ${_slides.length}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.5,
                  color: Color(0xFF626262),
                ),
              ),
              const SizedBox(height: 12),
              // Progress bar
              Container(
                height: 2,
                decoration: const BoxDecoration(color: Color(0xFFEEEEEE)),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    height: 2,
                    width:
                        (MediaQuery.of(context).size.width - 48) *
                        ((_index + 1) / _slides.length),
                    color: const Color(0xFF000000),
                  ),
                ),
              ),
              const SizedBox(height: 48),
              // Slides
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: _slides.length,
                  onPageChanged: (v) => setState(() => _index = v),
                  itemBuilder: (_, i) {
                    final s = _slides[i];
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 88,
                          height: 88,
                          decoration: BoxDecoration(
                            color: const Color(0xFF000000),
                          ),
                          child: Icon(
                            s.icon,
                            color: const Color(0xFFFFFFFF),
                            size: 40,
                          ),
                        ),
                        const SizedBox(height: 40),
                        Text(
                          s.title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1A1C1C),
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            s.body,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 15,
                              color: Color(0xFF626262),
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              // Pagination dots
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  _slides.length,
                  (i) => Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == _index ? 24 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: i == _index
                          ? const Color(0xFF000000)
                          : const Color(0xFFEEEEEE),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              // Button
              GestureDetector(
                onTap: () {
                  HapticFeedback.mediumImpact();
                  if (_index < _slides.length - 1) {
                    _controller.nextPage(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                    );
                  } else {
                    _finish();
                  }
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF000000),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _index < _slides.length - 1 ? 'NEXT' : 'GET STARTED',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                      color: Color(0xFFFFFFFF),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SlideData {
  final IconData icon;
  final String title;
  final String body;
  const _SlideData({
    required this.icon,
    required this.title,
    required this.body,
  });
}

enum DisplayMode { fitToScreen, pixelPerfect }

class PreviewScreen extends StatefulWidget {
  const PreviewScreen({super.key, required this.controller});

  final SeeloConnectionController controller;

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen>
    with WidgetsBindingObserver {
  StreamSubscription<AccelerometerEvent>? _shakeSub;
  DateTime? _lastShake;
  bool _showingPopup = false;
  bool _showSystemUi = false;
  bool _showIssues = true;
  bool _showSafeArea = false;
  bool _showGrid = false;
  bool _showRulers = false;
  bool _showDeviceFrame = false;
  bool _overlayMode = false;
  bool _overlayCompare = false;
  double _overlayCompareSliderPos = 0.5;
  final double _overlayOpacity = 0.5;
  bool _showToolbar = true;
  bool _isLandscape = false;
  bool _measureMode = false;
  List<Offset> _measurePoints = [];
  bool _wasInBackground = false;
  Timer? _toolbarTimer;
  DisplayMode _displayMode = DisplayMode.pixelPerfect;
  DevicePreset _selectedPreset = builtInPresets[0];
  final TransformationController _transformationController =
      TransformationController();
  final GlobalKey _imageKey = GlobalKey();
  final GlobalKey _screenshotKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _applySystemUiMode();
    _shakeSub = accelerometerEventStream().listen(_handleShake);
    _startToolbarTimer();
    widget.controller.lastError.addListener(_onConnectionError);
  }

  void _onConnectionError() {
    final err = widget.controller.lastError.value;
    if (err == null || !mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1B23),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.link_off_rounded,
                color: Color(0xFFEF4444),
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'Disconnected',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              err,
              style: const TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF2D2E3A),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 14,
                    color: Color(0xFF64748B),
                  ),
                  SizedBox(width: 6),
                  Text(
                    'Free plan: 1 active device',
                    style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              widget.controller.lastError.value = null;
              Navigator.of(ctx).pop();
              Navigator.of(context).pop();
            },
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF94A3B8),
            ),
            child: const Text('Go Back'),
          ),
        ],
      ),
    );
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
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
        ),
      );
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: []);
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: Colors.transparent,
        ),
      );
    }
  }

  void _handleShake(AccelerometerEvent event) {
    final magnitude = sqrt(
      (event.x * event.x) + (event.y * event.y) + (event.z * event.z),
    );
    if (magnitude < 25) return;

    final now = DateTime.now();
    if (_lastShake != null &&
        now.difference(_lastShake!).inMilliseconds < 1400) {
      return;
    }
    _lastShake = now;

    if (_showingPopup || !mounted) return;
    _showSettings();
  }

  void _showSettings() {
    HapticFeedback.mediumImpact();
    _showingPopup = true;
    showDialog<void>(
      context: context,
      builder: (ctx) {
        bool localShowUi = _showSystemUi;
        DisplayMode localMode = _displayMode;
        bool localIssues = _showIssues;
        bool localSafeArea = _showSafeArea;
        bool localGrid = _showGrid;
        bool localRulers = _showRulers;
        bool localDeviceFrame = _showDeviceFrame;
        bool localOverlayCompare = _overlayCompare;
        final isTabletSettings = MediaQuery.of(ctx).size.shortestSide >= 600;
        return AlertDialog(
          backgroundColor: AppPalette.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          insetPadding: isTabletSettings
              ? EdgeInsets.symmetric(
                  horizontal: MediaQuery.of(ctx).size.width * 0.15,
                  vertical: 40,
                )
              : null,
          title: const Text(
            'Preview Settings',
            style: TextStyle(color: AppPalette.text),
          ),
          content: StatefulBuilder(
            builder: (context, setInner) {
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Customize your immersive experience.',
                      style: TextStyle(color: AppPalette.dim),
                    ),
                    const SizedBox(height: 20),
                    _settingToggle(
                      'Show System UI',
                      'Display status/nav bars',
                      localShowUi,
                      (v) {
                        setInner(() => localShowUi = v);
                        setState(() {
                          _showSystemUi = v;
                          _applySystemUiMode();
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Overlays',
                      style: TextStyle(
                        color: AppPalette.text,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    PremiumGate(
                      feature: PremiumFeature.issueHighlighting,
                      child: _settingToggle(
                        'Issue Highlighting',
                        'Show overflow/overlap warnings',
                        localIssues,
                        (v) {
                          setInner(() => localIssues = v);
                          setState(() => _showIssues = v);
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    _settingToggle(
                      'Safe Area',
                      'Visualize safe zone boundaries',
                      localSafeArea,
                      (v) {
                        setInner(() => localSafeArea = v);
                        setState(() => _showSafeArea = v);
                      },
                    ),
                    const SizedBox(height: 8),
                    _settingToggle(
                      'Pixel Grid',
                      '8×8 px alignment grid',
                      localGrid,
                      (v) {
                        setInner(() => localGrid = v);
                        setState(() => _showGrid = v);
                      },
                    ),
                    const SizedBox(height: 8),
                    PremiumGate(
                      feature: PremiumFeature.rulers,
                      child: _settingToggle(
                        'Rulers',
                        'Show measurement rulers',
                        localRulers,
                        (v) {
                          setInner(() => localRulers = v);
                          setState(() => _showRulers = v);
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    PremiumGate(
                      feature: PremiumFeature.deviceFrame,
                      child: _settingToggle(
                        'Device Frame',
                        'Show bezel + notch overlay',
                        localDeviceFrame,
                        (v) {
                          setInner(() => localDeviceFrame = v);
                          setState(() => _showDeviceFrame = v);
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    PremiumGate(
                      feature: PremiumFeature.overlayCompare,
                      child: _settingToggle(
                        'Overlay Compare',
                        'Slide to compare with previous design',
                        localOverlayCompare,
                        (v) {
                          setInner(() => localOverlayCompare = v);
                          setState(() => _overlayCompare = v);
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Display Mode',
                      style: TextStyle(
                        color: AppPalette.text,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _modeChip(
                      'Fit to Screen',
                      'Stretch image to fill screen width',
                      DisplayMode.fitToScreen,
                      localMode,
                      setInner,
                      (m) => setInner(() {
                        localMode = m;
                      }),
                    ),
                    const SizedBox(height: 6),
                    _modeChip(
                      'Pixel Perfect',
                      '1:1 native resolution, no stretching',
                      DisplayMode.pixelPerfect,
                      localMode,
                      setInner,
                      (m) => setInner(() {
                        localMode = m;
                      }),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Device Preset',
                      style: TextStyle(
                        color: AppPalette.text,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 180),
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            // Custom presets
                            ...widget.controller.customPresets.map((preset) {
                              final active =
                                  _selectedPreset.name == preset.name;
                              return InkWell(
                                onTap: () =>
                                    setState(() => _selectedPreset = preset),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  margin: const EdgeInsets.only(bottom: 4),
                                  decoration: BoxDecoration(
                                    color: active
                                        ? const Color(0x3322C55E)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(8),
                                    border: active
                                        ? Border.all(
                                            color: const Color(0x5522C55E),
                                          )
                                        : null,
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.star,
                                        size: 16,
                                        color: active
                                            ? const Color(0xFF22C55E)
                                            : const Color(0xAA22C55E),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          preset.label,
                                          style: TextStyle(
                                            color: active
                                                ? Colors.white
                                                : const Color(0xCC22C55E),
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                      GestureDetector(
                                        onTap: () => setState(
                                          () => widget.controller.customPresets
                                              .remove(preset),
                                        ),
                                        child: const Icon(
                                          Icons.close,
                                          size: 14,
                                          color: AppPalette.dim,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }),
                            if (widget.controller.customPresets.isNotEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 4),
                                child: Divider(
                                  color: AppPalette.border,
                                  height: 1,
                                ),
                              ),
                            // Built-in presets
                            ...builtInPresets.map((preset) {
                              final active =
                                  _selectedPreset.name == preset.name;
                              return InkWell(
                                onTap: () =>
                                    setState(() => _selectedPreset = preset),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  margin: const EdgeInsets.only(bottom: 4),
                                  decoration: BoxDecoration(
                                    color: active
                                        ? Colors.white.withValues(alpha: 0.1)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(8),
                                    border: active
                                        ? Border.all(color: Colors.white24)
                                        : null,
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        active
                                            ? Icons.check_circle
                                            : Icons.phone_android,
                                        size: 16,
                                        color: active
                                            ? const Color(0xFF22C55E)
                                            : AppPalette.dim,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          preset.label,
                                          style: TextStyle(
                                            color: active
                                                ? Colors.white
                                                : AppPalette.dim,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    ),
                    Builder(
                      builder: (_) {
                        final m = widget.controller.currentMetadata;
                        if (m == null) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: SizedBox(
                            width: double.infinity,
                            child: TextButton.icon(
                              onPressed: () {
                                final p = DevicePreset(
                                  name:
                                      '${m.frameWidth.toInt()}x${m.frameHeight.toInt()}',
                                  screenWidth: m.frameWidth,
                                  screenHeight: m.frameHeight,
                                );
                                if (widget.controller.customPresets.any(
                                  (x) => x.name == p.name,
                                )) {
                                  return;
                                }
                                widget.controller.customPresets.insert(0, p);
                                setState(() => _selectedPreset = p);
                              },
                              icon: const Icon(Icons.add, size: 16),
                              label: const Text(
                                'Save Current as Preset',
                                style: TextStyle(fontSize: 12),
                              ),
                              style: TextButton.styleFrom(
                                foregroundColor: AppPalette.dim,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Close',
                style: TextStyle(color: Colors.white70),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () {
                HapticFeedback.lightImpact();
                Navigator.of(context).pop();
                Navigator.of(context).pop();
              },
              child: const Text('Exit Preview'),
            ),
          ],
        );
      },
    ).then((_) => _showingPopup = false);
  }

  void _showHistory() {
    HapticFeedback.selectionClick();
    final history = widget.controller.sessionHistory;
    _showingPopup = true;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppPalette.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppPalette.dim,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Session History',
                style: const TextStyle(
                  color: AppPalette.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${history.length} session${history.length != 1 ? 's' : ''}',
                style: const TextStyle(color: AppPalette.dim, fontSize: 13),
              ),
              const SizedBox(height: 16),
              if (history.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: Text(
                      'No sessions yet',
                      style: TextStyle(color: AppPalette.dim),
                    ),
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: history.length,
                    separatorBuilder: (_, _) =>
                        const Divider(color: AppPalette.border, height: 1),
                    itemBuilder: (_, i) {
                      final entry = history[i];
                      final icon = entry.isCloud
                          ? Icons.cloud
                          : Icons.desktop_windows;
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          icon,
                          color: entry.isCloud
                              ? const Color(0xFF22C55E)
                              : AppPalette.dim,
                          size: 20,
                        ),
                        title: Text(
                          entry.label,
                          style: const TextStyle(
                            color: AppPalette.text,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          _formatTime(entry.time),
                          style: const TextStyle(
                            color: AppPalette.dim,
                            fontSize: 11,
                          ),
                        ),
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

  void _showNotes() {
    HapticFeedback.selectionClick();
    _showingPopup = true;
    final notes = widget.controller.notes.value;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFFF9F9F9),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFF626262),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Notes',
                style: TextStyle(
                  color: Color(0xFF1A1C1C),
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${notes.length} note${notes.length != 1 ? 's' : ''}',
                style: const TextStyle(color: Color(0xFF626262), fontSize: 13),
              ),
              const SizedBox(height: 16),
              if (notes.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: Text(
                      'No notes yet',
                      style: TextStyle(color: Color(0xFF626262)),
                    ),
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: notes.length,
                    separatorBuilder: (_, _) =>
                        const Divider(color: Color(0xFFEEEEEE), height: 1),
                    itemBuilder: (_, i) {
                      final n = notes[i];
                      return ListTile(
                        dense: true,
                        leading: const Icon(
                          Icons.note,
                          color: Color(0xFF000000),
                          size: 20,
                        ),
                        title: Text(
                          n['text']?.toString() ?? '',
                          style: const TextStyle(
                            color: Color(0xFF1A1C1C),
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          n['author']?.toString() ?? '',
                          style: const TextStyle(
                            color: Color(0xFF626262),
                            fontSize: 11,
                          ),
                        ),
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

  void _showGallery() {
    HapticFeedback.selectionClick();
    _showingPopup = true;
    final frames = widget.controller.frameGallery.value;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFFF9F9F9),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFF626262),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Frame Gallery',
                style: TextStyle(
                  color: Color(0xFF1A1C1C),
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${frames.length} frame${frames.length != 1 ? 's' : ''}',
                style: const TextStyle(color: Color(0xFF626262), fontSize: 13),
              ),
              const SizedBox(height: 16),
              if (frames.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: Text(
                      'No frames available',
                      style: TextStyle(color: Color(0xFF626262)),
                    ),
                  ),
                )
              else
                Expanded(
                  child: GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                    itemCount: frames.length,
                    itemBuilder: (_, i) {
                      final f = frames[i];
                      final thumb = f['preview']?.toString() ?? f['thumbnail']?.toString() ?? '';
                      return GestureDetector(
                        onTap: () {
                          final id = f['id']?.toString();
                          if (id != null) {
                            widget.controller.requestFrameSelect(id);
                          }
                          Navigator.of(ctx).pop();
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFFEEEEEE),
                            border: Border.all(color: const Color(0xFF000000)),
                          ),
                          child: thumb.isNotEmpty
                              ? ClipRect(
                                  child: Image.memory(
                                    base64Decode(thumb.split(',').last),
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => const Icon(
                                      Icons.image,
                                      color: Color(0xFF626262),
                                    ),
                                  ),
                                )
                              : const Icon(
                                  Icons.image,
                                  color: Color(0xFF626262),
                                ),
                        ),
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

  void _showSuggestions(List<DesignIssue> issues) {
    _showingPopup = true;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppPalette.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppPalette.dim,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Icon(
                    Icons.auto_awesome,
                    size: 18,
                    color: Color(0xFF22C55E),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Smart Suggestions',
                    style: const TextStyle(
                      color: AppPalette.text,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${issues.length} issue${issues.length != 1 ? 's' : ''} found',
                style: const TextStyle(color: AppPalette.dim, fontSize: 13),
              ),
              const SizedBox(height: 16),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: issues.length,
                  separatorBuilder: (_, _) =>
                      const Divider(color: AppPalette.border, height: 1),
                  itemBuilder: (_, i) {
                    final issue = issues[i];
                    final icon = issue.type == 'overflow'
                        ? Icons.arrow_outward
                        : issue.type == 'spacing'
                        ? Icons.space_bar
                        : Icons.layers;
                    final color = issue.type == 'overflow'
                        ? const Color(0xFFFF4757)
                        : issue.type == 'spacing'
                        ? const Color(0xFFFFA502)
                        : const Color(0xFF22C55E);
                    return SizedBox(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(icon, size: 16, color: color),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  issue.message,
                                  style: const TextStyle(
                                    color: AppPalette.text,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Padding(
                            padding: const EdgeInsets.only(left: 24),
                            child: Text(
                              issue.suggestion,
                              style: const TextStyle(
                                color: AppPalette.dim,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
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

  Future<void> _takeScreenshot() async {
    HapticFeedback.mediumImpact();
    try {
      final boundary =
          _screenshotKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(
        pixelRatio: MediaQuery.of(context).devicePixelRatio,
      );
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final bytes = byteData.buffer.asUint8List();
      final dir = Directory.systemTemp;
      final file = File(
        '${dir.path}/seelo_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(bytes);
      if (mounted) {
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(file.path)],
            text: 'Seelo Preview Screenshot',
          ),
        );
      }
    } catch (e, st) {
      logError(e, st);
    }
  }

  Widget _modeChip(
    String title,
    String subtitle,
    DisplayMode mode,
    DisplayMode current,
    void Function(void Function()) setInner,
    void Function(DisplayMode) onChanged,
  ) {
    final active = mode == current;
    return InkWell(
      onTap: () {
        onChanged(mode);
        setState(() => _displayMode = mode);
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: active
              ? Colors.white.withValues(alpha: 0.1)
              : Colors.transparent,
          border: Border.all(color: active ? Colors.white : AppPalette.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(
              mode == DisplayMode.fitToScreen
                  ? Icons.fit_screen
                  : Icons.one_x_mobiledata,
              color: active ? Colors.white : AppPalette.dim,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: active ? Colors.white : AppPalette.text,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(color: AppPalette.dim, fontSize: 11),
                  ),
                ],
              ),
            ),
            if (active)
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _settingToggle(
    String title,
    String sub,
    bool val,
    ValueChanged<bool> onChanged,
  ) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AppPalette.text,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                sub,
                style: const TextStyle(color: AppPalette.dim, fontSize: 12),
              ),
            ],
          ),
        ),
        Switch(
          value: val,
          onChanged: onChanged,
          activeThumbColor: Colors.white,
        ),
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            'Layer Inspector',
            style: TextStyle(color: AppPalette.text, fontSize: 16),
          ),
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
                if (letterSpacing != 0)
                  _inspectorRow('Letter Spacing', '${letterSpacing}px'),
                if (lineHeight != 0)
                  _inspectorRow('Line Height', '${lineHeight}px'),
                _inspectorRow('Opacity', '${(opacity * 100).round()}%'),
                if (layer['x'] != null && layer['y'] != null)
                  _inspectorRow(
                    'Position',
                    'x:${(layer['x'] as num?)?.round() ?? 0} y:${(layer['y'] as num?)?.round() ?? 0}',
                  ),
                if (layer['width'] != null && layer['height'] != null)
                  _inspectorRow(
                    'Size',
                    '${(layer['width'] as num?)?.round() ?? 0}\u00D7${(layer['height'] as num?)?.round() ?? 0}',
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text(
                'Close',
                style: TextStyle(color: Colors.white70),
              ),
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
            child: Text(
              label,
              style: const TextStyle(color: AppPalette.dim, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: AppPalette.text, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Map<String, dynamic>? _hitTestTextLayer(
    Offset imageLocalPos,
    FrameMetadata meta,
  ) {
    for (final layer in meta.textLayers.reversed) {
      final lx = (layer['x'] as num?)?.toDouble() ?? 0;
      final ly = (layer['y'] as num?)?.toDouble() ?? 0;
      final lw = (layer['width'] as num?)?.toDouble() ?? 0;
      final lh = (layer['height'] as num?)?.toDouble() ?? 0;
      if (lx <= imageLocalPos.dx &&
          imageLocalPos.dx <= lx + lw &&
          ly <= imageLocalPos.dy &&
          imageLocalPos.dy <= ly + lh) {
        if ((layer['characters']?.toString() ?? '').trim().isNotEmpty) {
          return layer;
        }
      }
    }
    return null;
  }

  Widget _buildIssueOverlay(
    FrameMetadata meta,
    double renderW,
    double renderH,
  ) {
    final issues = widget.controller.issues.value;
    if (issues.isEmpty) return const SizedBox.shrink();
    final scaleX = renderW / meta.frameWidth;
    final scaleY = renderH / meta.frameHeight;
    return ValueListenableBuilder<List<DesignIssue>>(
      valueListenable: widget.controller.issues,
      builder: (_, list, _) {
        return Stack(
          children: list.map((issue) {
            final color = issue.type == 'overflow'
                ? const Color(0x44FF4757)
                : const Color(0x44FFA502);
            final borderColor = issue.type == 'overflow'
                ? const Color(0xAAFF4757)
                : const Color(0xAAFFA502);
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

  Widget _buildSafeAreaOverlay(
    FrameMetadata meta,
    double renderW,
    double renderH,
  ) {
    final isDesktop = _selectedPreset.screenWidth >= 1440;
    final isTablet = _selectedPreset.screenWidth >= 820 && !isDesktop;
    double topInset, bottomInset;
    if (isDesktop) {
      topInset = 0.0;
      bottomInset = 0.0;
    } else if (isTablet) {
      topInset = 0.02;
      bottomInset = 0.02;
    } else {
      // Mobile: notch + home indicator
      topInset = 0.06;
      bottomInset = 0.04;
    }
    final sh = renderH;
    final sw = renderW;
    if (isDesktop) return const SizedBox.shrink();
    return Stack(
      children: [
        Positioned(
          top: 0,
          left: 0,
          width: sw,
          height: sh * topInset,
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: const Color(0xAA22C55E), width: 2),
              ),
              color: const Color(0x2222C55E),
            ),
            child: const Center(
              child: Text(
                'SAFE',
                style: TextStyle(
                  color: Color(0xAA22C55E),
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 0,
          left: 0,
          width: sw,
          height: sh * bottomInset,
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: const Color(0xAA22C55E), width: 2),
              ),
              color: const Color(0x2222C55E),
            ),
            child: const Center(
              child: Text(
                'SAFE',
                style: TextStyle(
                  color: Color(0xAA22C55E),
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGridOverlay(FrameMetadata meta, double renderW, double renderH) {
    const cellSize = 8; // 8x8 px grid cells in design coordinates
    if (meta.frameWidth <= 0 || meta.frameHeight <= 0) {
      return const SizedBox.shrink();
    }
    final cols = (meta.frameWidth / cellSize).ceil();
    final rows = (meta.frameHeight / cellSize).ceil();
    final scaleX = renderW / meta.frameWidth;
    final scaleY = renderH / meta.frameHeight;
    return CustomPaint(
      size: Size(renderW, renderH),
      painter: _GridPainter(cols, rows, cellSize * scaleX, cellSize * scaleY),
    );
  }

  Widget _buildRulers(FrameMetadata meta, double renderW, double renderH) {
    final scaleX = renderW / meta.frameWidth;
    return CustomPaint(
      size: Size(renderW, renderH),
      painter: _RulerPainter(scale: scaleX, offsetX: 0, offsetY: 0),
    );
  }

  Widget _buildDeviceFrame(FrameMetadata meta, double renderW, double renderH) {
    final isTablet = _selectedPreset.screenWidth >= 820;
    final isDesktop = _selectedPreset.screenWidth >= 1440;
    final cornerRadius = isTablet
        ? 32.0
        : isDesktop
        ? 8.0
        : 24.0;
    final notchWidth = isDesktop
        ? 0.0
        : isTablet
        ? 0.0
        : 80.0;
    final notchHeight = isDesktop
        ? 0.0
        : isTablet
        ? 0.0
        : 6.0;
    final notchTop = isDesktop
        ? 0.0
        : isTablet
        ? 0.0
        : 0.0;
    return IgnorePointer(
      child: Stack(
        children: [
          // Rounded corners
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(cornerRadius),
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0x88FFFFFF), width: 2),
                  borderRadius: BorderRadius.circular(cornerRadius),
                ),
              ),
            ),
          ),
          // Notch indicator (mobile only)
          if (notchWidth > 0)
            Positioned(
              top: notchTop,
              left: renderW / 2 - notchWidth / 2,
              width: notchWidth,
              height: notchHeight,
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xCC1C1C1E),
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(3),
                  ),
                ),
              ),
            ),
          // Bottom home indicator (mobile only)
          if (!isDesktop)
            Positioned(
              bottom: isTablet ? 6 : 4,
              left: renderW / 2 - 25,
              width: 50,
              height: isTablet ? 5 : 4,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMeasurementOverlay(
    FrameMetadata meta,
    double renderW,
    double renderH,
  ) {
    if (_measurePoints.length < 2) {
      if (_measurePoints.length == 1) {
        return CustomPaint(
          size: Size(renderW, renderH),
          painter: _MeasurePainter(points: _measurePoints, scaled: false),
        );
      }
      return const SizedBox.shrink();
    }
    final scaleX = renderW / meta.frameWidth;
    final scaleY = renderH / meta.frameHeight;
    final p0 = Offset(
      _measurePoints[0].dx * scaleX,
      _measurePoints[0].dy * scaleY,
    );
    final p1 = Offset(
      _measurePoints[1].dx * scaleX,
      _measurePoints[1].dy * scaleY,
    );
    final dist = (_measurePoints[0] - _measurePoints[1]).distance;
    return Stack(
      children: [
        CustomPaint(
          size: Size(renderW, renderH),
          painter: _MeasurePainter(points: [p0, p1], scaled: true),
        ),
        Positioned(
          left: (p0.dx + p1.dx) / 2 - 30,
          top: (p0.dy + p1.dy) / 2 - 10,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.white24),
            ),
            child: Text(
              '${dist.toStringAsFixed(1)}px',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        if (_measurePoints.length == 2)
          Positioned(
            bottom: 120,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: () => setState(() {
                  _measurePoints.clear();
                  _measureMode = false;
                }),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: const Text(
                    'Clear Measurement',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildOverlayCompareSlider(
    double renderW,
    double renderH,
    String previousImageData,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalW = constraints.maxWidth > 0
            ? constraints.maxWidth
            : renderW;
        return GestureDetector(
          onHorizontalDragUpdate: (details) {
            setState(() {
              _overlayCompareSliderPos = (details.localPosition.dx / totalW)
                  .clamp(0.05, 0.95);
            });
          },
          child: SizedBox(
            width: totalW,
            height: renderH,
            child: Stack(
              children: [
                ClipRect(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    widthFactor: _overlayCompareSliderPos,
                    child: Opacity(
                      opacity: 0.5,
                      child: Image.memory(
                        base64Decode(previousImageData.split(',').last),
                        width: totalW,
                        height: renderH,
                        fit: BoxFit.fitWidth,
                        filterQuality: FilterQuality.high,
                        gaplessPlayback: true,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: totalW * _overlayCompareSliderPos - 12,
                  top: 0,
                  bottom: 0,
                  width: 24,
                  child: GestureDetector(
                    onHorizontalDragUpdate: (details) {
                      setState(() {
                        _overlayCompareSliderPos =
                            ((totalW * _overlayCompareSliderPos +
                                        details.delta.dx) /
                                    totalW)
                                .clamp(0.05, 0.95);
                      });
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.5),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.chevron_left,
                            size: 14,
                            color: Colors.black87,
                          ),
                          Icon(
                            Icons.chevron_right,
                            size: 14,
                            color: Colors.black87,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    widget.controller.lastError.removeListener(_onConnectionError);
    WidgetsBinding.instance.removeObserver(this);
    _shakeSub?.cancel();
    _toolbarTimer?.cancel();
    _transformationController.dispose();
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: const [SystemUiOverlay.top, SystemUiOverlay.bottom],
    );
    widget.controller.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final screenWidth = _isLandscape ? size.height : size.width;

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
            builder: (context, _, _) {
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
                  } catch (e, st) {
                    logError(e, st);
                    content = const Center(
                      child: Text(
                        'Failed to decode image',
                        style: TextStyle(color: AppPalette.dim),
                      ),
                  );
                  return const SizedBox.shrink();
                }

                final double imageNaturalWidth = meta.imagePixelsWidth;
                final double imageNaturalHeight = meta.imagePixelsHeight;

                if (_displayMode == DisplayMode.pixelPerfect &&
                    imageNaturalWidth > 0 &&
                    imageNaturalHeight > 0) {
                  // Exact-size: use Figma frame logical dimensions directly
                  final double renderWidth = meta.frameWidth;
                  final double renderHeight = meta.frameHeight;

                  content = GestureDetector(
                    onTapUp: (details) {
                      if (_measureMode) {
                        final RenderBox? box =
                            _imageKey.currentContext?.findRenderObject()
                                as RenderBox?;
                        if (box == null) return;
                        final localPos = box.globalToLocal(
                          details.globalPosition,
                        );
                        final scaleX = meta.frameWidth / renderWidth;
                        final scaleY = meta.frameHeight / renderHeight;
                        final f = Offset(
                          localPos.dx * scaleX,
                          localPos.dy * scaleY,
                        );
                        setState(() {
                          _measurePoints = [..._measurePoints, f];
                          if (_measurePoints.length > 2) {
                            _measurePoints = _measurePoints.sublist(1);
                          }
                        });
                        return;
                      }
                      // Convert tap position to frame-local coordinates
                      final RenderBox? box =
                          _imageKey.currentContext?.findRenderObject()
                              as RenderBox?;
                      if (box == null) return;
                      final localPos = box.globalToLocal(
                        details.globalPosition,
                      );
                      final scaleX = meta.frameWidth / renderWidth;
                      final scaleY = meta.frameHeight / renderHeight;
                      final frameLocalPos = Offset(
                        localPos.dx * scaleX,
                        localPos.dy * scaleY,
                      );

                      final hitLayer = _hitTestTextLayer(frameLocalPos, meta);
                      if (hitLayer != null) {
                        HapticFeedback.selectionClick();
                        _showLayerInspector(hitLayer, localPos);
                      }
                    },
                    child: InteractiveViewer(
                      transformationController: _transformationController,
                      minScale: 0.5,
                      maxScale: 8.0,
                      constrained: false,
                      child: SizedBox(
                        width: renderWidth,
                        height: renderHeight,
                        child: Container(
                          color: const Color(0xFF0C0C0C),
                          child: Stack(
                            children: [
                              if (PremiumManager.hasAccess(
                                    PremiumFeature.overlayMode,
                                  ) &&
                                  _overlayMode &&
                                  widget.controller.previousImageData != null)
                                Opacity(
                                  opacity: _overlayOpacity,
                                  child: Image.memory(
                                    base64Decode(
                                      widget.controller.previousImageData!
                                          .split(',')
                                          .last,
                                    ),
                                    width: renderWidth,
                                    height: renderHeight,
                                    fit: BoxFit.fill,
                                    filterQuality: FilterQuality.high,
                                    gaplessPlayback: true,
                                  ),
                                ),
                              Image.memory(
                                key: _imageKey,
                                decodedImage,
                                width: renderWidth,
                                height: renderHeight,
                                fit: BoxFit.fill,
                                filterQuality: FilterQuality.high,
                                gaplessPlayback: true,
                              ),
                              if (_showIssues &&
                                  PremiumManager.hasAccess(
                                    PremiumFeature.issueHighlighting,
                                  ))
                                _buildIssueOverlay(
                                  meta,
                                  renderWidth,
                                  renderHeight,
                                ),
                              if (_showSafeArea)
                                _buildSafeAreaOverlay(
                                  meta,
                                  renderWidth,
                                  renderHeight,
                                ),
                              if (_showGrid)
                                _buildGridOverlay(
                                  meta,
                                  renderWidth,
                                  renderHeight,
                                ),
                              if (PremiumManager.hasAccess(
                                    PremiumFeature.rulers,
                                  ) &&
                                  _showRulers)
                                _buildRulers(meta, renderWidth, renderHeight),
                              if (PremiumManager.hasAccess(
                                    PremiumFeature.measurement,
                                  ) &&
                                  _measureMode)
                                _buildMeasurementOverlay(
                                  meta,
                                  renderWidth,
                                  renderHeight,
                                ),
                              if (PremiumManager.hasAccess(
                                    PremiumFeature.deviceFrame,
                                  ) &&
                                  _showDeviceFrame)
                                _buildDeviceFrame(
                                  meta,
                                  renderWidth,
                                  renderHeight,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                } else {
                  content = GestureDetector(
                    onTapUp: (details) {
                      if (PremiumManager.hasAccess(
                            PremiumFeature.measurement,
                          ) &&
                          _measureMode) {
                        final RenderBox? box =
                            _imageKey.currentContext?.findRenderObject()
                                as RenderBox?;
                        if (box == null) return;
                        final localPos = box.globalToLocal(
                          details.globalPosition,
                        );
                        final scaleX = meta.frameWidth / screenWidth;
                        final scaleY =
                            meta.frameHeight /
                            (screenWidth *
                                (meta.frameHeight / meta.frameWidth));
                        final f = Offset(
                          localPos.dx * scaleX,
                          localPos.dy * scaleY,
                        );
                        setState(() {
                          _measurePoints = [..._measurePoints, f];
                          if (_measurePoints.length > 2) {
                            _measurePoints = _measurePoints.sublist(1);
                          }
                        });
                        return;
                      }
                      if (meta.textLayers.isEmpty) return;
                      final RenderBox? box =
                          _imageKey.currentContext?.findRenderObject()
                              as RenderBox?;
                      if (box == null) return;
                      final localPos = box.globalToLocal(
                        details.globalPosition,
                      );
                      final scaleX = meta.frameWidth / screenWidth;
                      final scaleY =
                          meta.frameHeight /
                          (screenWidth * (meta.frameHeight / meta.frameWidth));
                      final frameLocalPos = Offset(
                        localPos.dx * scaleX,
                        localPos.dy * scaleY,
                      );

                      final hitLayer = _hitTestTextLayer(frameLocalPos, meta);
                      if (hitLayer != null) {
                        HapticFeedback.selectionClick();
                        _showLayerInspector(hitLayer, localPos);
                      }
                    },
                    child: InteractiveViewer(
                      transformationController: _transformationController,
                      minScale: 1.0,
                      maxScale: 4.0,
                      panEnabled: false,
                      child: SingleChildScrollView(
                        padding: EdgeInsets.zero,
                        physics: const ClampingScrollPhysics(),
                        child: SizedBox(
                          width: screenWidth,
                          height:
                              screenWidth *
                              (meta.frameHeight / meta.frameWidth),
                          child: Stack(
                            children: [
                              if (PremiumManager.hasAccess(
                                    PremiumFeature.overlayMode,
                                  ) &&
                                  _overlayMode &&
                                  widget.controller.previousImageData != null &&
                                  _overlayCompare)
                                _buildOverlayCompareSlider(
                                  screenWidth,
                                  screenWidth *
                                      (meta.frameHeight / meta.frameWidth),
                                  widget.controller.previousImageData!,
                                )
                              else if (PremiumManager.hasAccess(
                                    PremiumFeature.overlayMode,
                                  ) &&
                                  _overlayMode &&
                                  widget.controller.previousImageData != null)
                                Opacity(
                                  opacity: _overlayOpacity,
                                  child: Image.memory(
                                    base64Decode(
                                      widget.controller.previousImageData!
                                          .split(',')
                                          .last,
                                    ),
                                    width: screenWidth,
                                    fit: BoxFit.fitWidth,
                                    filterQuality: FilterQuality.high,
                                    gaplessPlayback: true,
                                  ),
                                ),
                              Image.memory(
                                key: _imageKey,
                                decodedImage,
                                width: screenWidth,
                                fit: BoxFit.fitWidth,
                                filterQuality: FilterQuality.high,
                                gaplessPlayback: true,
                              ),
                              if (_showIssues &&
                                  PremiumManager.hasAccess(
                                    PremiumFeature.issueHighlighting,
                                  ))
                                _buildIssueOverlay(
                                  meta,
                                  screenWidth,
                                  screenWidth *
                                      (meta.frameHeight / meta.frameWidth),
                                ),
                              if (_showSafeArea)
                                _buildSafeAreaOverlay(
                                  meta,
                                  screenWidth,
                                  screenWidth *
                                      (meta.frameHeight / meta.frameWidth),
                                ),
                              if (_showGrid)
                                _buildGridOverlay(
                                  meta,
                                  screenWidth,
                                  screenWidth *
                                      (meta.frameHeight / meta.frameWidth),
                                ),
                              if (PremiumManager.hasAccess(
                                    PremiumFeature.rulers,
                                  ) &&
                                  _showRulers)
                                _buildRulers(
                                  meta,
                                  screenWidth,
                                  screenWidth *
                                      (meta.frameHeight / meta.frameWidth),
                                ),
                              if (PremiumManager.hasAccess(
                                    PremiumFeature.measurement,
                                  ) &&
                                  _measureMode)
                                _buildMeasurementOverlay(
                                  meta,
                                  screenWidth,
                                  screenWidth *
                                      (meta.frameHeight / meta.frameWidth),
                                ),
                              if (PremiumManager.hasAccess(
                                    PremiumFeature.deviceFrame,
                                  ) &&
                                  _showDeviceFrame)
                                _buildDeviceFrame(
                                  meta,
                                  screenWidth,
                                  screenWidth *
                                      (meta.frameHeight / meta.frameWidth),
                                ),
                            ],
                          ),
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
                    child: RepaintBoundary(
                      key: _screenshotKey,
                      child: Container(
                        color: Colors.black,
                        child: _showSystemUi
                            ? SafeArea(child: content)
                            : content,
                      ),
                    ),
                  ),
                  // Top-left badges: frame info + viewer count
                  if (imageData != null && meta != null)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: AnimatedOpacity(
                        opacity: _showToolbar ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 250),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            GestureDetector(
                              onTap: _toggleToolbar,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.6),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Flexible(
                                      child: Text(
                                        '${meta.frameWidth.toInt()}\u00D7${meta.frameHeight.toInt()}',
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white54,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        _selectedPreset.name,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white38,
                                          fontSize: 9,
                                        ),
                                      ),
                                    ),
                                    if (_isLandscape) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 5,
                                          vertical: 1,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0x33FFA502),
                                          borderRadius: BorderRadius.circular(
                                            3,
                                          ),
                                          border: Border.all(
                                            color: const Color(0x55FFA502),
                                          ),
                                        ),
                                        child: const Text(
                                          'LAND',
                                          style: TextStyle(
                                            color: Color(0xCCFFA502),
                                            fontSize: 8,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                            if (widget.controller.serverLabel == 'Cloud')
                              ValueListenableBuilder<int>(
                                valueListenable: widget.controller.viewerCount,
                                builder: (_, count, _) {
                                  if (count <= 0) {
                                    return const SizedBox.shrink();
                                  }
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0x9922C55E),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.people_alt_rounded,
                                            size: 12,
                                            color: Colors.white,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            '$count',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                          ],
                        ),
                      ),
                    ),
                  // Issue badge + suggestions (Pro feature)
                  if (imageData != null &&
                      meta != null &&
                      PremiumManager.hasAccess(
                        PremiumFeature.smartSuggestions,
                      ))
                    Positioned(
                      top: 56,
                      right: 12,
                      child: ValueListenableBuilder<List<DesignIssue>>(
                        valueListenable: widget.controller.issues,
                        builder: (_, issues, _) {
                          if (issues.isEmpty) return const SizedBox.shrink();
                          return GestureDetector(
                            onTap: () => _showSuggestions(issues),
                            onLongPress: () =>
                                setState(() => _showIssues = !_showIssues),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.75),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.white24),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.warning_amber_rounded,
                                    size: 14,
                                    color:
                                        issues.any((i) => i.type == 'overflow')
                                        ? const Color(0xFFFF6B6B)
                                        : const Color(0xFFFFC75F),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '${issues.length} issues',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
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
                    child: AnimatedOpacity(
                      opacity: _showToolbar ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 250),
                      child: ValueListenableBuilder<ConnectionQuality>(
                        valueListenable: widget.controller.connectionQuality,
                        builder: (_, q, _) {
                          final (color, label) = switch (q) {
                            ConnectionQuality.good => (
                              const Color(0xFF22C55E),
                              'Good',
                            ),
                            ConnectionQuality.fair => (
                              const Color(0xFFEAB308),
                              'Fair',
                            ),
                            ConnectionQuality.poor => (
                              const Color(0xFFEF4444),
                              'Poor',
                            ),
                            ConnectionQuality.disconnected => (
                              AppPalette.dim,
                              'Disconnected',
                            ),
                          };
                          return GestureDetector(
                            onTap: _toggleToolbar,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.6),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      color: color,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    label,
                                    style: const TextStyle(
                                      color: Colors.white54,
                                      fontSize: 9,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  // Reconnecting overlay
                  ValueListenableBuilder<ConnectionQuality>(
                    valueListenable: widget.controller.connectionQuality,
                    builder: (_, q, _) {
                      if (q == ConnectionQuality.good ||
                          q == ConnectionQuality.fair) {
                        return const SizedBox.shrink();
                      }
                      return Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: GestureDetector(
                          onTap: _toggleToolbar,
                          child: Container(
                            color: Colors.black54,
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(
                                    width: 32,
                                    height: 32,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white70,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    q == ConnectionQuality.disconnected
                                        ? 'Reconnecting...'
                                        : 'Weak connection',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 14,
                                    ),
                                  ),
                                  ValueListenableBuilder<int>(
                                    valueListenable:
                                        widget.controller.latencyMs,
                                    builder: (_, lat, _) => lat > 0
                                        ? Text(
                                            '${lat}ms latency',
                                            style: const TextStyle(
                                              color: Colors.white38,
                                              fontSize: 12,
                                            ),
                                          )
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
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.8),
                                borderRadius: BorderRadius.circular(99),
                                border: Border.all(
                                  color: Colors.white24,
                                  width: 0.5,
                                ),
                              ),
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // Quality dot
                                    ValueListenableBuilder<ConnectionQuality>(
                                      valueListenable:
                                          widget.controller.connectionQuality,
                                      builder: (_, q, _) {
                                        final c = q == ConnectionQuality.good
                                            ? const Color(0xFF22C55E)
                                            : q == ConnectionQuality.fair
                                            ? const Color(0xFFEAB308)
                                            : q == ConnectionQuality.poor
                                            ? const Color(0xFFEF4444)
                                            : AppPalette.dim;
                                        return Container(
                                          width: 8,
                                          height: 8,
                                          margin: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                          ),
                                          decoration: BoxDecoration(
                                            color: c,
                                            shape: BoxShape.circle,
                                          ),
                                        );
                                      },
                                    ),
                                    if (widget.controller.serverLabel ==
                                        'Cloud')
                                      ValueListenableBuilder<int>(
                                        valueListenable:
                                            widget.controller.viewerCount,
                                        builder: (_, count, _) {
                                          final label = count > 1
                                              ? '$count viewers'
                                              : count == 1
                                              ? '1 viewer'
                                              : '';
                                          if (label.isEmpty) {
                                            return const SizedBox.shrink();
                                          }
                                          return Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 4,
                                            ),
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 4,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: const Color(0x3322C55E),
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                border: Border.all(
                                                  color: const Color(
                                                    0x5522C55E,
                                                  ),
                                                ),
                                              ),
                                              child: Text(
                                                label,
                                                style: const TextStyle(
                                                  color: Color(0xCC22C55E),
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    _toolBtn(
                                      Icons.close,
                                      () => Navigator.of(context).pop(),
                                    ),
                                    const SizedBox(width: 8),
                                    _toolBtn(Icons.refresh, () {
                                      widget.controller.requestManualSync();
                                      _startToolbarTimer();
                                    }),
                                    const SizedBox(width: 8),
                                    _toolBtn(
                                      _displayMode == DisplayMode.pixelPerfect
                                          ? Icons.fit_screen
                                          : Icons.one_x_mobiledata,
                                      () {
                                        setState(
                                          () => _displayMode =
                                              _displayMode ==
                                                  DisplayMode.fitToScreen
                                              ? DisplayMode.pixelPerfect
                                              : DisplayMode.fitToScreen,
                                        );
                                        _transformationController.value =
                                            Matrix4.identity();
                                        _startToolbarTimer();
                                      },
                                    ),
                                    const SizedBox(width: 8),
                                    if (PremiumManager.hasAccess(
                                      PremiumFeature.landscapeMode,
                                    ))
                                      _toolBtn(
                                        _isLandscape
                                            ? Icons.screen_rotation
                                            : Icons.rotate_left,
                                        () {
                                          setState(
                                            () => _isLandscape = !_isLandscape,
                                          );
                                          _startToolbarTimer();
                                        },
                                      )
                                    else
                                      _toolBtn(
                                        Icons.lock_outline,
                                        () => ProLocked(
                                          feature: PremiumFeature.landscapeMode,
                                          child: const SizedBox(),
                                        ).showUpgrade(context),
                                      ),
                                    const SizedBox(width: 8),
                                    _toolBtn(Icons.note_rounded, () {
                                      _showNotes();
                                      _startToolbarTimer();
                                    }),
                                    const SizedBox(width: 8),
                                    _toolBtn(Icons.photo_library_rounded, () {
                                      _showGallery();
                                      _startToolbarTimer();
                                    }),
                                    const SizedBox(width: 8),
                                    if (PremiumManager.hasAccess(
                                      PremiumFeature.measurement,
                                    ))
                                      _toolBtn(
                                        _measureMode
                                            ? Icons.horizontal_rule
                                            : Icons.straighten,
                                        () {
                                          setState(() {
                                            _measureMode = !_measureMode;
                                            _measurePoints.clear();
                                          });
                                          _startToolbarTimer();
                                        },
                                      )
                                    else
                                      _toolBtn(
                                        Icons.lock_outline,
                                        () => ProLocked(
                                          feature: PremiumFeature.measurement,
                                          child: const SizedBox(),
                                        ).showUpgrade(context),
                                      ),
                                    const SizedBox(width: 8),
                                    if (PremiumManager.hasAccess(
                                      PremiumFeature.overlayMode,
                                    ))
                                      _toolBtn(
                                        _overlayMode
                                            ? Icons.layers_clear
                                            : Icons.layers,
                                        () {
                                          setState(
                                            () => _overlayMode = !_overlayMode,
                                          );
                                          _startToolbarTimer();
                                        },
                                      )
                                    else
                                      _toolBtn(
                                        Icons.lock_outline,
                                        () => ProLocked(
                                          feature: PremiumFeature.overlayMode,
                                          child: const SizedBox(),
                                        ).showUpgrade(context),
                                      ),
                                    const SizedBox(width: 8),
                                    if (PremiumManager.hasAccess(
                                      PremiumFeature.screenshotExport,
                                    ))
                                      _toolBtn(Icons.download_rounded, () {
                                        _takeScreenshot();
                                        _startToolbarTimer();
                                      })
                                    else
                                      _toolBtn(
                                        Icons.lock_outline,
                                        () => ProLocked(
                                          feature:
                                              PremiumFeature.screenshotExport,
                                          child: const SizedBox(),
                                        ).showUpgrade(context),
                                      ),
                                    const SizedBox(width: 8),
                                    ValueListenableBuilder<int>(
                                      valueListenable:
                                          widget.controller.viewerCount,
                                      builder: (_, count, w) {
                                        return PremiumGate(
                                          feature: PremiumFeature.multiDevice,
                                          child: GestureDetector(
                                            onTap: () {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (_) =>
                                                      DeviceManagerScreen(
                                                        isPro:
                                                            PremiumManager
                                                                .plan !=
                                                            Plan.free,
                                                        currentViewers: count,
                                                        maxViewers:
                                                            PremiumManager
                                                                    .plan ==
                                                                Plan.team
                                                            ? 999
                                                            : PremiumManager
                                                                      .plan ==
                                                                  Plan.pro
                                                            ? 5
                                                            : 1,
                                                      ),
                                                ),
                                              );
                                              _startToolbarTimer();
                                            },
                                            child: Container(
                                              width: _toolBtnSize,
                                              height: _toolBtnSize,
                                              decoration: const BoxDecoration(
                                                color: AppPalette.card,
                                                shape: BoxShape.circle,
                                              ),
                                              child: Stack(
                                                clipBehavior: Clip.none,
                                                children: [
                                                  Center(
                                                    child: Icon(
                                                      Icons.devices,
                                                      color: Colors.white,
                                                      size: _toolIconSize,
                                                    ),
                                                  ),
                                                  if (count > 0)
                                                    Positioned(
                                                      right: -2,
                                                      top: -2,
                                                      child: Container(
                                                        padding:
                                                            const EdgeInsets.all(
                                                              4,
                                                            ),
                                                        decoration:
                                                            const BoxDecoration(
                                                              color: Color(
                                                                0xFF22C55E,
                                                              ),
                                                              shape: BoxShape
                                                                  .circle,
                                                            ),
                                                        child: Text(
                                                          '$count',
                                                          style:
                                                              const TextStyle(
                                                                color: Colors
                                                                    .black,
                                                                fontSize: 9,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700,
                                                              ),
                                                        ),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                    const SizedBox(width: 8),
                                    if (PremiumManager.hasAccess(
                                      PremiumFeature.sessionHistory,
                                    ))
                                      _toolBtn(Icons.history, () {
                                        _showHistory();
                                        _startToolbarTimer();
                                      })
                                    else
                                      _toolBtn(
                                        Icons.lock_outline,
                                        () => ProLocked(
                                          feature:
                                              PremiumFeature.sessionHistory,
                                          child: const SizedBox(),
                                        ).showUpgrade(context),
                                      ),
                                    const SizedBox(width: 8),
                                    _toolBtn(Icons.settings, () {
                                      _showSettings();
                                      _startToolbarTimer();
                                    }),
                                  ],
                                ),
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

  bool _isTabletSized(BuildContext c) =>
      MediaQuery.of(c).size.shortestSide >= 600;

  double get _toolBtnSize => _isTabletSized(context) ? 52 : 44;
  double get _toolIconSize => _isTabletSized(context) ? 24 : 20;

  Widget _toolBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: _toolBtnSize,
        height: _toolBtnSize,
        decoration: const BoxDecoration(
          color: AppPalette.card,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: _toolIconSize),
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
      old.cols != cols ||
      old.rows != rows ||
      old.cellW != cellW ||
      old.cellH != cellH;
}

class _RulerPainter extends CustomPainter {
  final double scale;
  final double offsetX;
  final double offsetY;

  _RulerPainter({this.scale = 1.0, this.offsetX = 0.0, this.offsetY = 0.0});

  @override
  void paint(Canvas canvas, Size size) {
    const rulerSize = 24.0;
    const tickInterval = 10.0;
    const labelInterval = 50.0;

    final bgPaint = Paint()..color = const Color(0xCC1C1C1E);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, rulerSize), bgPaint);
    canvas.drawRect(Rect.fromLTWH(0, 0, rulerSize, size.height), bgPaint);

    final tickPaint = Paint()
      ..color = const Color(0xAAFFFFFF)
      ..strokeWidth = 1.0;
    final guidePaint = Paint()
      ..color = const Color(0x18FFFFFF)
      ..strokeWidth = 0.5;

    final totalPx = ((size.width + offsetX) / scale).ceil();
    for (double px = 0; px <= totalPx; px += tickInterval) {
      final x = px * scale - offsetX;
      if (x < 0 || x > size.width) continue;
      final isMajor = px % labelInterval == 0;
      canvas.drawLine(Offset(x, 0), Offset(x, isMajor ? 14.0 : 7.0), tickPaint);
      if (isMajor && x + 25 < size.width) {
        final tp = TextPainter(
          text: TextSpan(
            text: '${px.toInt()}',
            style: const TextStyle(color: Color(0xAAFFFFFF), fontSize: 9),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: 40);
        tp.paint(canvas, Offset(x + 3, 14));
        canvas.drawLine(
          Offset(x, rulerSize),
          Offset(x, size.height),
          guidePaint,
        );
      }
    }

    for (
      double py = 0;
      py <= ((size.height + offsetY) / scale).ceil();
      py += tickInterval
    ) {
      final y = py * scale - offsetY;
      if (y < 0 || y > size.height) continue;
      final isMajor = py % labelInterval == 0;
      canvas.drawLine(Offset(0, y), Offset(isMajor ? 14.0 : 7.0, y), tickPaint);
      if (isMajor && y + 25 < size.height) {
        final tp = TextPainter(
          text: TextSpan(
            text: '${py.toInt()}',
            style: const TextStyle(color: Color(0xAAFFFFFF), fontSize: 9),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: 40);
        tp.paint(canvas, Offset(14, y + 3));
        canvas.drawLine(
          Offset(rulerSize, y),
          Offset(size.width, y),
          guidePaint,
        );
      }
    }

    canvas.drawRect(
      const Rect.fromLTWH(0, 0, rulerSize, rulerSize),
      Paint()..color = const Color(0xFF1C1C1E),
    );
  }

  @override
  bool shouldRepaint(covariant _RulerPainter old) =>
      old.scale != scale || old.offsetX != offsetX || old.offsetY != offsetY;
}

class _MeasurePainter extends CustomPainter {
  final List<Offset> points;
  final bool scaled;
  _MeasurePainter({required this.points, this.scaled = false});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final dotPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    for (final p in points) {
      canvas.drawCircle(p, 4, dotPaint);
      canvas.drawCircle(
        p,
        2,
        Paint()
          ..color = const Color(0xFF22C55E)
          ..style = PaintingStyle.fill,
      );
    }
    if (points.length == 2) {
      final linePaint = Paint()
        ..color = Colors.white
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;
      canvas.drawLine(points[0], points[1], linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _MeasurePainter old) => old.points != points;
}
