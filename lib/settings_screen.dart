part of 'main.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.controller});
  final SeeloConnectionController controller;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _darkMode = SeeloConfig.darkMode.value;
  bool _showDebugErrorBoxes = SeeloConfig.showDebugErrorBoxes.value;
  DevicePreset _selectedPreset = builtInPresets[1];
  User? _user;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  late TextEditingController _usernameCtrl;
  late TextEditingController _emailCtrl;

  @override
  void initState() {
    super.initState();
    _user = safeCurrentUser();
    _usernameCtrl = TextEditingController(text: _user?.displayName ?? '');
    _emailCtrl = TextEditingController(text: _user?.email ?? '');
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  void _selectPreset(DevicePreset preset) {
    HapticFeedback.selectionClick();
    setState(() => _selectedPreset = preset);
    final config = SeeloConfig();
    config.screenWidth = preset.screenWidth.toInt();
    config.screenHeight = preset.screenHeight.toInt();
  }

  void _toggleDarkMode(bool v) {
    setState(() => _darkMode = v);
    SeeloConfig.darkMode.value = v;
  }

  void _toggleDebugErrorBoxes(bool v) {
    setState(() => _showDebugErrorBoxes = v);
    SeeloConfig.showDebugErrorBoxes.value = v;
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.shortestSide >= 600;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFFFFFFF),
      drawer: _buildDrawer(),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  isWide ? 64 : 16,
                  96,
                  isWide ? 64 : 16,
                  48,
                ),
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1280),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHeader(),
                        const SizedBox(height: 24),
                        if (isWide)
                          _buildWideLayout()
                        else
                          _buildNarrowLayout(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      height: 64,
      decoration: const BoxDecoration(
        color: Color(0xFFF9F9F9),
        border: Border(bottom: BorderSide(color: Color(0xFFEEEEEE))),
      ),
      child: Row(
        children: [
          const SizedBox(width: 16),
          _iconBtn(
            Icons.menu,
            onTap: () => _scaffoldKey.currentState?.openDrawer(),
          ),
          const SizedBox(width: 12),
          const Text(
            'SEELO',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.03,
              color: Color(0xFF000000),
            ),
          ),
          const Spacer(),
          _iconBtn(Icons.signal_cellular_alt),
          const SizedBox(width: 16),
        ],
      ),
    );
  }

  Widget _iconBtn(IconData icon, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap ?? () {},
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: const BoxDecoration(shape: BoxShape.circle),
        child: Icon(icon, size: 24, color: const Color(0xFF000000)),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Settings',
          style: TextStyle(
            fontSize: 48,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.02,
            color: Color(0xFF1A1C1C),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Manage your workspace and connection parameters.',
          style: TextStyle(fontSize: 16, color: const Color(0xFF848484)),
        ),
      ],
    );
  }

  Widget _buildWideLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 8, child: _buildMainContent()),
        const SizedBox(width: 24),
        Expanded(flex: 4, child: _buildSidebar()),
      ],
    );
  }

  Widget _buildNarrowLayout() {
    return Column(
      children: [
        _buildMainContent(),
        const SizedBox(height: 24),
        _buildSidebar(),
      ],
    );
  }

  Widget _buildMainContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildProfileSection(),
        const SizedBox(height: 24),
        _buildPreviewSize(),
        const SizedBox(height: 24),
        _buildActionBar(),
      ],
    );
  }

  Widget _buildProfileSection() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: Color(0xFFFFFFFF),
        border: Border(bottom: BorderSide(color: Color(0xFFEEEEEE))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Profile Information',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1A1C1C),
            ),
          ),
          const SizedBox(height: 24),
          LayoutBuilder(
            builder: (_, constraints) {
              final twoCol = constraints.maxWidth >= 400;
              if (twoCol) {
                return Row(
                  children: [
                    Expanded(child: _textField('Username', 'alex_design')),
                    const SizedBox(width: 24),
                    Expanded(
                      child: _textField('Email Address', 'alex@seelo.io'),
                    ),
                  ],
                );
              }
              return Column(
                children: [
                  _textField('Username', 'alex_design'),
                  const SizedBox(height: 12),
                  _textField('Email Address', 'alex@seelo.io'),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _textField(String label, String hint) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1A1C1C),
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: label == 'Username' ? _usernameCtrl : _emailCtrl,
          decoration: InputDecoration(
            hintText: hint,
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
              horizontal: 8,
              vertical: 12,
            ),
            isDense: true,
          ),
          style: const TextStyle(fontSize: 16, color: Color(0xFF1A1C1C)),
        ),
      ],
    );
  }

  Widget _buildPreviewSize() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F3F4),
        border: const Border(bottom: BorderSide(color: Color(0xFFEEEEEE))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Preview Size',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1A1C1C),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Adjust the interface scaling for your monitor.',
                      style: TextStyle(
                        fontSize: 14,
                        color: const Color(0xFF626262),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.aspect_ratio, color: const Color(0xFF000000)),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: builtInPresets.map((preset) {
              final active = _selectedPreset.name == preset.name;
              return GestureDetector(
                onTap: () => _selectPreset(preset),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: active
                        ? const Color(0xFF000000)
                        : const Color(0xFFFFFFFF),
                    border: Border.all(
                      color: active
                          ? const Color(0xFF000000)
                          : const Color(0xFFEEEEEE),
                    ),
                  ),
                  child: Text(
                    preset.name,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: active
                          ? const Color(0xFFFFFFFF)
                          : const Color(0xFF1A1C1C),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildActionBar() {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFEEEEEE)),
                ),
                child: const Center(
                  child: Text(
                    'Discard Changes',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1A1C1C),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              onTap: () {
                HapticFeedback.mediumImpact();
                final config = SeeloConfig();
                config.screenWidth = _selectedPreset.screenWidth.toInt();
                config.screenHeight = _selectedPreset.screenHeight.toInt();
                Navigator.pop(context);
              },
              child: Container(
                height: 44,
                color: const Color(0xFF000000),
                child: const Center(
                  child: Text(
                    'SAVE SETTINGS',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                      color: Color(0xFFFFFFFF),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionCard() {
    final user = safeCurrentUser();
    final label = widget.controller.serverLabel;
    final quality = widget.controller.connectionQuality.value;
    final isConnected = quality == ConnectionQuality.good || quality == ConnectionQuality.poor;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isConnected
                      ? const Color(0xFF22C55E)
                      : const Color(0xFF94A3B8),
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Connection',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: Color(0xFF1A1C1C),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            label.isNotEmpty ? label : 'Disconnected',
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF626262),
            ),
          ),
          if (user != null) ...[
            const SizedBox(height: 8),
            Text(
              user.email ?? '',
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFFA6A6A6),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAppearanceCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Appearance',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: Color(0xFF1A1C1C),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Dark Mode',
                style: TextStyle(fontSize: 12, color: Color(0xFF626262)),
              ),
              Switch.adaptive(
                value: _darkMode,
                onChanged: _toggleDarkMode,
              ),
            ],
          ),
          if (kDebugMode) ...[
            const Divider(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Debug Error Boxes',
                  style: TextStyle(fontSize: 12, color: Color(0xFF626262)),
                ),
                Switch.adaptive(
                  value: _showDebugErrorBoxes,
                  onChanged: _toggleDebugErrorBoxes,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    return Column(
      children: [
        _buildConnectionCard(),
        const SizedBox(height: 24),
        _buildAppearanceCard(),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildDrawer() {
    final items = [
      (Icons.share, 'Connect'),
      (Icons.devices, 'Devices'),
      (Icons.history, 'History'),
      (Icons.settings, 'Settings'),
    ];
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 32, 20, 24),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFFEEEEEE))),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'SEELO',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.03,
                      color: Color(0xFF000000),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'v1.0.0',
                    style: TextStyle(
                      fontSize: 12,
                      color: const Color(0xFF848484),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  for (final (icon, label) in items)
                    _drawerItem(icon, label, label == 'Settings'),
                ],
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFFEEEEEE))),
              ),
              child: ValueListenableBuilder<ConnectionQuality>(
                valueListenable: widget.controller.connectionQuality,
                builder: (_, quality, _) {
                  final ok = quality != ConnectionQuality.disconnected;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: ok
                                  ? const Color(0xFF22C55E)
                                  : const Color(0xFFBA1A1A),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            ok ? 'Connected' : 'Disconnected',
                            style: TextStyle(
                              fontSize: 12,
                              color: const Color(0xFF626262),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ValueListenableBuilder<Plan>(
                        valueListenable: PremiumManager.planNotifier,
                        builder: (_, plan, _) => Text(
                          plan == Plan.pro ? 'Pro Plan' : 'Free Plan',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF848484),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _drawerItem(IconData icon, String label, bool active) {
    return GestureDetector(
      onTap: () {
        Navigator.pop(context); // close drawer
        if (label == 'Settings') return;
        if (label == 'Connect') {
          Navigator.pop(context);
        } else if (label == 'Devices') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  ConnectedDevicesScreen(controller: widget.controller),
            ),
          );
        } else if (label == 'History') {
          Navigator.pop(context);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFF3F3F4) : Colors.transparent,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 22,
              color: active ? const Color(0xFF000000) : const Color(0xFF626262),
            ),
            const SizedBox(width: 16),
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                color: active
                    ? const Color(0xFF000000)
                    : const Color(0xFF1A1C1C),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
