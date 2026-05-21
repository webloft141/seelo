import 'package:flutter/material.dart';

enum Plan { starter, pro }

enum PremiumFeature {
  multiDevice,
  customPresets,
  sessionHistory,
  overlayCompare,
  rulers,
  measurement,
  smartSuggestions,
  deviceFrame,
  landscapeMode,
  screenshotExport,
  overlayMode,
  gridOverlay,
  safeAreaOverlay,
  issueHighlighting,
}

extension PremiumFeatureMeta on PremiumFeature {
  String get label {
    switch (this) {
      case PremiumFeature.multiDevice: return 'Multi-device Preview';
      case PremiumFeature.customPresets: return 'Custom Presets';
      case PremiumFeature.sessionHistory: return 'Session History';
      case PremiumFeature.overlayCompare: return 'Overlay Compare';
      case PremiumFeature.rulers: return 'Rulers';
      case PremiumFeature.measurement: return 'Measurement Tool';
      case PremiumFeature.smartSuggestions: return 'Smart Suggestions';
      case PremiumFeature.deviceFrame: return 'Device Frame';
      case PremiumFeature.landscapeMode: return 'Landscape Mode';
      case PremiumFeature.screenshotExport: return 'Screenshot Export';
      case PremiumFeature.overlayMode: return 'Overlay Mode';
      case PremiumFeature.gridOverlay: return 'Pixel Grid';
      case PremiumFeature.safeAreaOverlay: return 'Safe Area Overlay';
      case PremiumFeature.issueHighlighting: return 'Issue Highlighting';
    }
  }

  Plan get plan {
    switch (this) {
      case PremiumFeature.issueHighlighting:
      case PremiumFeature.gridOverlay:
      case PremiumFeature.safeAreaOverlay:
        return Plan.starter;
      default:
        return Plan.pro;
    }
  }
}

class PremiumManager {
  static Plan _currentPlan = Plan.starter;

  static Plan get plan => _currentPlan;

  static void setPlan(Plan p) => _currentPlan = p;

  static bool hasAccess(PremiumFeature feature) {
    if (_currentPlan == Plan.pro) return true;
    return feature.plan == Plan.starter;
  }
}

class PremiumGate extends StatelessWidget {
  final PremiumFeature feature;
  final Widget child;

  const PremiumGate({super.key, required this.feature, required this.child});

  @override
  Widget build(BuildContext context) {
    if (PremiumManager.hasAccess(feature)) return child;
    return ProLocked(
      feature: feature,
      child: child,
    );
  }
}

class ProLocked extends StatelessWidget {
  final PremiumFeature feature;
  final Widget child;

  const ProLocked({super.key, required this.feature, required this.child});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => showUpgrade(context),
      child: Stack(
        children: [
          Opacity(opacity: 0.3, child: AbsorbPointer(child: child)),
          Positioned.fill(
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xCC1C1C1E),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF22C55E).withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock, size: 16, color: Color(0xFF22C55E)),
                    const SizedBox(width: 8),
                    const Text('PRO', style: TextStyle(color: Color(0xFF22C55E), fontSize: 11, fontWeight: FontWeight.w700)),
                    const SizedBox(width: 4),
                    Text(feature.label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void showUpgrade(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 24),
            const Icon(Icons.auto_awesome, size: 48, color: Color(0xFF22C55E)),
            const SizedBox(height: 16),
            const Text('Pro Feature', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text('"${feature.label}" is available in Pro Early Access\nUpgrade to unlock all premium features.',
                textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF888888), fontSize: 14)),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF22C55E),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('See Plans', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Maybe later', style: TextStyle(color: Color(0xFF888888))),
            ),
          ],
        ),
      ),
    );
  }
}
