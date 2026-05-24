import 'package:flutter_test/flutter_test.dart';
import 'package:seelo/main.dart';

void main() {
  test('SeeloConfig singleton works', () {
    final config = SeeloConfig();
    expect(config.screenWidth, 412);
    expect(config.screenHeight, 915);
    expect(config.defaultRoomId, 'seelo-desktop');
    expect(config.defaultPort, 3000);
  });

  // Widget tests requiring Firebase are skipped by default.
  // To enable them, set up Firebase mocks in setUpAll():
  //   import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
  //   import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
  //   FirebasePlatform.instance = MockFirebasePlatform();
  //
  // testWidgets('Seelo app renders splash screen', (tester) async {
  //   await tester.pumpWidget(const SeeloApp());
  //   expect(find.text('Seelo'), findsOneWidget);
  // });
}