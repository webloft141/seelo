part of 'main.dart';

class ConnectedDevicesScreen extends StatefulWidget {
  const ConnectedDevicesScreen({super.key, required this.controller});
  final SeeloConnectionController controller;

  @override
  State<ConnectedDevicesScreen> createState() => _ConnectedDevicesScreenState();
}

class _ConnectedDevicesScreenState extends State<ConnectedDevicesScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFFFF),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFFFFF),
        foregroundColor: const Color(0xFF1A1C1C),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Connected Devices',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1A1C1C),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildCurrentConnection(),
          const SizedBox(height: 24),
          _buildSavedDevices(),
        ],
      ),
    );
  }

  Widget _buildCurrentConnection() {
    return ValueListenableBuilder<ConnectionQuality>(
      valueListenable: widget.controller.connectionQuality,
      builder: (_, quality, _) {
        final connected = quality != ConnectionQuality.disconnected;
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF9F9F9),
            border: Border.all(color: const Color(0xFFEEEEEE)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: connected
                          ? const Color(0xFF22C55E)
                          : const Color(0xFFBA1A1A),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    connected ? 'Connected' : 'Disconnected',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: connected
                          ? const Color(0xFF1A1C1C)
                          : const Color(0xFFBA1A1A),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    connected ? 'STABLE' : 'OFFLINE',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF626262),
                    ),
                  ),
                ],
              ),
              if (connected) ...[
                const SizedBox(height: 16),
                _infoRow('Server', widget.controller.serverLabel),
                const SizedBox(height: 8),
                ValueListenableBuilder<int>(
                  valueListenable: widget.controller.latencyMs,
                  builder: (_, ms, _) => _infoRow('Latency', '${ms}ms'),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _infoRow(String label, String value) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 13, color: Color(0xFF626262)),
        ),
        const SizedBox(width: 12),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1A1C1C),
          ),
        ),
      ],
    );
  }

  Widget _buildSavedDevices() {
    return ValueListenableBuilder<List<SavedDevice>>(
      valueListenable: widget.controller.savedDevices,
      builder: (_, devices, _) {
        if (devices.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFEEEEEE)),
            ),
            child: const Center(
              child: Text(
                'No saved devices yet',
                style: TextStyle(fontSize: 14, color: Color(0xFF848484)),
              ),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Previously Connected',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A1C1C),
              ),
            ),
            const SizedBox(height: 12),
            ...devices.map(
              (d) => Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF9F9F9),
                  border: Border.all(color: const Color(0xFFEEEEEE)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.computer,
                      size: 20,
                      color: Color(0xFF1A1C1C),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
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
                            'Last used: ${_formatTime(d.lastUsed)}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF848484),
                            ),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        widget.controller.connectToSaved(d);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFF1A1C1C)),
                        ),
                        child: const Text(
                          'CONNECT',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1A1C1C),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
