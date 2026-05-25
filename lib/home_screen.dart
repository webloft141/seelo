part of 'main.dart';

class SeeloHomeScreen extends StatefulWidget {
  const SeeloHomeScreen({super.key, required this.controller});
  final SeeloConnectionController controller;
  @override
  State<SeeloHomeScreen> createState() => _SeeloHomeScreenState();
}

class _SeeloHomeScreenState extends State<SeeloHomeScreen>
    with TickerProviderStateMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final TextEditingController _deviceIdController = TextEditingController();
  final TextEditingController _accessTokenController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String _status = 'Idle';
  String _error = '';
  late AnimationController _scanAnimController;
  late Animation<double> _scanAnimation;

  @override
  void initState() {
    super.initState();
    _scanAnimController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
    _scanAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _scanAnimController, curve: Curves.linear),
    );
  }

  @override
  void dispose() {
    _deviceIdController.dispose();
    _accessTokenController.dispose();
    _scrollController.dispose();
    _scanAnimController.dispose();
    super.dispose();
  }

  void _showProfileOrLogin() {
    if (safeCurrentUser() != null) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ProfileScreen()),
      );
    } else {
      showAuthSheet(context);
    }
  }

  void _openPreview() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PreviewScreen(controller: widget.controller),
      ),
    );
  }

  void _scanAndConnect() {
    HapticFeedback.mediumImpact();
    Navigator.of(context)
        .push<Map<String, dynamic>>(
          MaterialPageRoute(builder: (_) => const QuickPairingScreen()),
        )
        .then((payload) {
          if (!mounted) return;
          if (payload == null) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Bluetooth scan cancelled'), duration: Duration(seconds: 2)),
            );
            return;
          }
          if (payload['mode'] == 'manual') {
            setState(() => _error = '');
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Manual setup selected'), duration: Duration(seconds: 2)),
            );
            return;
          }
          setState(() => _error = '');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Connecting to device...'), duration: Duration(seconds: 2)),
          );
          widget.controller.connectWithPayload(
            payload: payload,
            onConnected: _openPreview,
            onError: (msg) {
              if (mounted) {
                setState(() => _error = msg);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Connection failed: $msg'), duration: const Duration(seconds: 3)),
                );
              }
            },
            onStatus: (msg) {
              if (mounted) setState(() => _status = msg);
            },
          );
        });
  }

  void _establishConnection() {
    HapticFeedback.mediumImpact();
    final deviceId = _deviceIdController.text.trim();
    final token = _accessTokenController.text.trim();
    if (deviceId.isEmpty || token.isEmpty) {
      setState(() => _error = 'Enter Device ID and Access Token');
      return;
    }
    setState(() {
      _status = 'Connecting...';
      _error = '';
    });
    widget.controller.connectWithPayload(
      payload: {
        'ip': deviceId.contains(':') ? deviceId.split(':')[0] : deviceId,
        'port': deviceId.contains(':') ? deviceId.split(':')[1] : '3000',
        'roomId': 'seelo-desktop',
        'roomSecret': token,
      },
      onConnected: () {
        if (mounted) setState(() => _status = 'Connected');
        _openPreview();
      },
      onError: (msg) {
        if (mounted) {
          setState(() {
            _error = msg;
            _status = 'Failed';
          });
        }
      },
      onStatus: (msg) {
        if (mounted) setState(() => _status = msg);
      },
    );
  }

  void _navigateToDevices() {
    final isPro =
        PremiumManager.plan == Plan.pro || PremiumManager.plan == Plan.team;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DeviceManagerScreen(
          isPro: isPro,
          currentViewers: widget.controller.viewerCount.value,
          maxViewers: isPro ? 5 : 1,
        ),
      ),
    );
  }

  void _navigateToHistory() {
    final history = widget.controller.sessionHistory;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFFFFFFFF),
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
                'Session History',
                style: TextStyle(
                  color: Color(0xFF1A1C1C),
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${history.length} session${history.length != 1 ? 's' : ''}',
                style: const TextStyle(color: Color(0xFF626262), fontSize: 14),
              ),
              const SizedBox(height: 16),
              if (history.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: Text(
                      'No sessions yet',
                      style: TextStyle(color: Color(0xFF626262)),
                    ),
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: history.length,
                    separatorBuilder: (_, _) =>
                        const Divider(color: Color(0xFFEEEEEE), height: 1),
                    itemBuilder: (_, i) {
                      final entry = history[i];
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          entry.isCloud ? Icons.cloud : Icons.desktop_windows,
                          color: entry.isCloud
                              ? const Color(0xFF000000)
                              : const Color(0xFF626262),
                          size: 20,
                        ),
                        title: Text(
                          entry.label,
                          style: const TextStyle(
                            color: Color(0xFF1A1C1C),
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          _formatTime(entry.time),
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
    );
  }

  String _formatTime(DateTime t) {
    final now = DateTime.now();
    final diff = now.difference(t);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  void _navigateToSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(controller: widget.controller),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.of(context).size.shortestSide >= 600;

    return ValueListenableBuilder<bool>(
      valueListenable: SeeloConfig.compactMode,
      builder: (_, compact, _) {
        final g = compact ? 12.0 : 24.0;
        final sg = compact ? 8.0 : 16.0;
        final lg = compact ? 20.0 : 32.0;
        return Scaffold(
          key: _scaffoldKey,
          backgroundColor: const Color(0xFFF9F9F9),
          drawer: _buildSidebarDrawer(),
          body: SafeArea(
            child: Column(
              children: [
                _buildTopBar(),
                if (!SeeloConfig.firebaseAvailable) _buildCloudNotice(),
                Expanded(
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    padding: EdgeInsets.fromLTRB(16, 0, 16, sg * 1.5),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(height: sg * 1.5),
                        _buildHeader(),
                        SizedBox(height: sg * 1.25),
                        if (isTablet)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 7,
                                child: _buildQuickPairing(compact: compact),
                              ),
                              SizedBox(width: g),
                              Expanded(
                                flex: 5,
                                child: Column(
                                  children: [
                                    _buildManualConnect(compact: compact),
                                    SizedBox(height: sg),
                                    _buildStatusCard(compact: compact),
                                  ],
                                ),
                              ),
                            ],
                          )
                        else
                          Column(
                            children: [
                              _buildQuickPairing(compact: compact),
                              SizedBox(height: sg),
                              _buildManualConnect(compact: compact),
                              SizedBox(height: sg),
                              _buildStatusCard(compact: compact),
                            ],
                          ),
                        SizedBox(height: lg),
                        _buildRecentDevices(),
                        SizedBox(height: sg),
                      ],
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

  Widget _buildTopBar() {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: Color(0xFFF9F9F9),
        border: Border(bottom: BorderSide(color: Color(0xFFEEEEEE))),
      ),
      child: Row(
        children: [
          Builder(
            builder: (innerContext) => IconButton(
              onPressed: () {
                HapticFeedback.selectionClick();
                Scaffold.of(innerContext).openDrawer();
              },
              icon: const Icon(Icons.menu, color: Color(0xFF000000)),
              splashRadius: 20,
              tooltip: 'Open navigation',
            ),
          ),
          const SizedBox(width: 24),
          const Text(
            'SEELO',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
              color: Color(0xFF000000),
            ),
          ),
          const Spacer(),
          const Icon(Icons.signal_cellular_alt, color: Color(0xFF000000)),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.person_outline, color: Color(0xFF000000)),
            onPressed: _showProfileOrLogin,
            splashRadius: 20,
            tooltip: 'Profile',
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Connect',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.02,
            height: 1.16,
            color: Color(0xFF1A1C1C),
          ),
        ),
      ],
    );
  }

  Widget _buildCloudNotice() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF6E6),
        border: Border.all(color: const Color(0xFFFFD28C)),
      ),
      child: const Text(
        'Cloud/account features are unavailable on this build. Local preview still works.',
        style: TextStyle(
          color: Color(0xFF8A5A00),
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildQuickPairing({bool compact = false}) {
    final pad = compact ? 12.0 : 16.0;
    return Container(
      padding: EdgeInsets.all(pad),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Quick Pairing',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1A1C1C),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Bluetooth LE Discovery',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF626262),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.bluetooth_searching_rounded,
                color: Color(0xFF000000),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildBleVisual(),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildButton(
                  label: 'START SCAN',
                  primary: true,
                  onTap: _scanAndConnect,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildButton(
                  label: 'SCAN QR',
                  primary: false,
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    Navigator.of(context)
                        .push<Map<String, dynamic>>(
                          MaterialPageRoute(
                            builder: (_) => const _QrScanSheet(),
                          ),
                        )
                        .then((payload) {
                          if (!mounted || payload == null) return;
                          setState(() => _error = '');
                          widget.controller.connectWithPayload(
                            payload: payload,
                            onConnected: _openPreview,
                            onError: (msg) {
                              if (mounted) setState(() => _error = msg);
                            },
                            onStatus: (msg) {
                              if (mounted) setState(() => _status = msg);
                            },
                          );
                        });
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBleVisual() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.maxWidth;
        final height = size * 0.56;
        return Container(
          width: size,
          height: height,
          decoration: BoxDecoration(
            color: const Color(0xFFFFFFFF),
            border: Border.all(color: const Color(0xFF000000), width: 2),
          ),
          clipBehavior: Clip.hardEdge,
          child: Stack(
            children: [
              AnimatedBuilder(
                animation: _scanAnimation,
                builder: (context, child) {
                  return CustomPaint(
                    size: Size(size, height),
                    painter: _RadarPainter(_scanAnimation.value),
                  );
                },
              ),
              Positioned(
                top: 12,
                left: 12,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    border: Border(
                      top: BorderSide(color: Color(0xFF000000), width: 2),
                      left: BorderSide(color: Color(0xFF000000), width: 2),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 12,
                right: 12,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    border: Border(
                      top: BorderSide(color: Color(0xFF000000), width: 2),
                      right: BorderSide(color: Color(0xFF000000), width: 2),
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 12,
                left: 12,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: Color(0xFF000000), width: 2),
                      left: BorderSide(color: Color(0xFF000000), width: 2),
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 12,
                right: 12,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: Color(0xFF000000), width: 2),
                      right: BorderSide(color: Color(0xFF000000), width: 2),
                    ),
                  ),
                ),
              ),
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  color: Colors.white.withValues(alpha: 0.9),
                  child: const Text(
                    'DISCOVER DEVICES NEARBY',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                      color: Color(0xFF000000),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildButton({
    required String label,
    required bool primary,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: primary ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
          border: Border.all(color: const Color(0xFF000000)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: primary ? const Color(0xFFFFFFFF) : const Color(0xFF000000),
          ),
        ),
      ),
    );
  }

  Widget _buildManualConnect({bool compact = false}) {
    final pad = compact ? 12.0 : 16.0;
    return Container(
      padding: EdgeInsets.all(pad),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Manual Connect',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1A1C1C),
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'Enter IP:Port and access token.',
            style: TextStyle(fontSize: 13, color: Color(0xFF626262)),
          ),
          const SizedBox(height: 24),
          _buildLabel('Device ID'),
          const SizedBox(height: 4),
          TextField(
            controller: _deviceIdController,
            style: const TextStyle(fontSize: 16, color: Color(0xFF1A1C1C)),
            decoration: InputDecoration(
              hintText: 'e.g. 192.168.1.5:3000',
              hintStyle: const TextStyle(color: Color(0xFF848484)),
              filled: true,
              fillColor: const Color(0xFFFFFFFF),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(0),
                borderSide: const BorderSide(color: Color(0xFFEEEEEE)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(0),
                borderSide: const BorderSide(color: Color(0xFFEEEEEE)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(0),
                borderSide: const BorderSide(color: Color(0xFF000000)),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
            ),
          ),
          const SizedBox(height: 16),
          _buildLabel('Access Token'),
          const SizedBox(height: 4),
          TextField(
            controller: _accessTokenController,
            obscureText: true,
            style: const TextStyle(fontSize: 16, color: Color(0xFF1A1C1C)),
            decoration: InputDecoration(
              hintText: '••••••••',
              hintStyle: const TextStyle(color: Color(0xFF848484)),
              filled: true,
              fillColor: const Color(0xFFFFFFFF),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(0),
                borderSide: const BorderSide(color: Color(0xFFEEEEEE)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(0),
                borderSide: const BorderSide(color: Color(0xFFEEEEEE)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(0),
                borderSide: const BorderSide(color: Color(0xFF000000)),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
            ),
          ),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: _establishConnection,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF000000),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'ESTABLISH CONNECTION',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFFFFFFF),
                ),
              ),
            ),
          ),
          if (_error.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF0F0),
                border: Border.all(color: const Color(0xFFFFCCCC)),
              ),
              child: Text(
                _error,
                style: const TextStyle(color: Color(0xFFBA1A1A), fontSize: 13),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: Color(0xFF1A1C1C),
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildStatusCard({bool compact = false}) {
    final pad = compact ? 14.0 : 24.0;
    return Container(
      padding: EdgeInsets.all(pad),
      decoration: BoxDecoration(
        color: const Color(0xFFEEEEEE),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Color(0xFF000000),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'CURRENT STATUS',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A1C1C),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.controller.isConnected
                          ? 'CONNECTED'
                          : widget.controller.connecting
                          ? 'CONNECTING...'
                          : _status.toUpperCase() == 'IDLE'
                          ? 'WAITING'
                          : _status.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF1A1C1C),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.controller.isConnected
                          ? 'Connected to ${widget.controller.serverLabel}'
                          : widget.controller.connecting
                          ? 'Establishing handshake...'
                          : 'System ready for handshaking...',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF626262),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.sensors, size: 40, color: Color(0xFF848484)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRecentDevices() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.only(bottom: 4),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFF000000))),
          ),
          child: const Text(
            'Recent Devices',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1A1C1C),
            ),
          ),
        ),
        const SizedBox(height: 24),
        ValueListenableBuilder<List<SavedDevice>>(
          valueListenable: widget.controller.savedDevices,
          builder: (_, devices, _) {
            if (devices.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFFFF),
                  border: Border.all(color: const Color(0xFFEEEEEE)),
                ),
                child: const Center(
                  child: Text(
                    'No saved devices. Connect a device to see it here.',
                    style: TextStyle(color: Color(0xFF626262), fontSize: 14),
                  ),
                ),
              );
            }
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: MediaQuery.of(context).size.width > 600 ? 4 : 2,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 3.2,
              ),
              itemCount: min(devices.length, 8),
              itemBuilder: (_, i) {
                final d = devices[i];
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    widget.controller.connectToSaved(d);
                    _openPreview();
                  },
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFFFF),
                      border: Border.all(color: const Color(0xFFEEEEEE)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          color: const Color(0xFFEEEEEE),
                          child: const Icon(
                            Icons.router,
                            color: Color(0xFF000000),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                d.displayLabel,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1A1C1C),
                                ),
                              ),
                              Text(
                                _formatTime(d.lastUsed),
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Color(0xFF626262),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.arrow_forward,
                          color: Color(0xFF626262),
                          size: 18,
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildSidebarDrawer() {
    return Drawer(
      backgroundColor: const Color(0xFFF9F9F9),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Text(
                'Navigation',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1C1C),
                ),
              ),
            ),
            const Divider(height: 1, color: Color(0xFFEEEEEE)),
            _drawerItem(
              icon: Icons.share,
              label: 'Connect',
              onTap: () {
                Navigator.of(context).pop();
                _scrollController.animateTo(
                  0,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                );
                setState(() => _error = '');
              },
            ),
            _drawerItem(
              icon: Icons.devices,
              label: 'Connected Devices',
              onTap: () {
                Navigator.of(context).pop();
                _navigateToDevices();
              },
            ),
            _drawerItem(
              icon: Icons.history,
              label: 'History',
              onTap: () {
                Navigator.of(context).pop();
                _navigateToHistory();
              },
            ),
            _drawerItem(
              icon: Icons.workspace_premium,
              label: 'Plans',
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const SubscriptionScreen(),
                  ),
                );
              },
            ),
            _drawerItem(
              icon: Icons.settings,
              label: 'Settings',
              onTap: () {
                Navigator.of(context).pop();
                _navigateToSettings();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _drawerItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: const Color(0xFF1A1C1C)),
      title: Text(
        label,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: Color(0xFF1A1C1C),
        ),
      ),
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
    );
  }
}

class _RadarPainter extends CustomPainter {
  final double progress;
  _RadarPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = min(size.width, size.height) / 2 - 20;

    // Pulse circles
    for (int i = 0; i < 4; i++) {
      final phase = (progress + i * 0.25) % 1.0;
      final radius = maxRadius * phase;
      final paint = Paint()
        ..color = const Color(0xFF000000).withValues(alpha: 0.12 * (1 - phase))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      canvas.drawCircle(center, radius, paint);
    }

    // Scan line
    final sweepAngle = progress * 2 * 3.14159;
    final scanPaint = Paint()
      ..color = const Color(0xFF000000).withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;
    final rect = Rect.fromCircle(center: center, radius: maxRadius);
    canvas.drawArc(rect, -3.14159 / 2, sweepAngle, true, scanPaint);

    // Center dot
    canvas.drawCircle(center, 4, Paint()..color = const Color(0xFF000000));
  }

  @override
  bool shouldRepaint(_RadarPainter old) => old.progress != progress;
}

// Full-screen QR scanner sheet
class _QrScanSheet extends StatefulWidget {
  const _QrScanSheet();
  @override
  State<_QrScanSheet> createState() => _QrScanSheetState();
}

class _QrScanSheetState extends State<_QrScanSheet> {
  bool _busy = false;
  final MobileScannerController _scannerController = MobileScannerController();

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F9F9),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF9F9F9),
        foregroundColor: const Color(0xFF1A1C1C),
        elevation: 0,
        title: const Text('Scan QR Code'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _scannerController,
            onDetect: (capture) {
              if (_busy) return;
              final raw = capture.barcodes.first.rawValue;
              if (raw == null) return;
              try {
                final map = jsonDecode(raw) as Map<String, dynamic>;
                _busy = true;
                _scannerController.stop().catchError((e, st) {
                  logError(e, st);
                });
                if (mounted) {
                  Navigator.of(context).pop(map);
                }
              } catch (e, st) {
                logError(e, st);
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
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      top: 0,
                      left: 0,
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: const BoxDecoration(
                          border: Border(
                            top: BorderSide(color: Colors.white, width: 3),
                            left: BorderSide(color: Colors.white, width: 3),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 0,
                      right: 0,
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: const BoxDecoration(
                          border: Border(
                            top: BorderSide(color: Colors.white, width: 3),
                            right: BorderSide(color: Colors.white, width: 3),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      left: 0,
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: const BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: Colors.white, width: 3),
                            left: BorderSide(color: Colors.white, width: 3),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: const BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: Colors.white, width: 3),
                            right: BorderSide(color: Colors.white, width: 3),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 80,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Align QR code within the frame',
                  style: TextStyle(
                    color: Color(0xFF1A1C1C),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
