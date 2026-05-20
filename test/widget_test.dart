import 'package:flutter_test/flutter_test.dart';

import 'package:seelo/main.dart';

void main() {
  testWidgets('Seelo app renders splash screen', (WidgetTester tester) async {
    await tester.pumpWidget(const SeeloApp());
    expect(find.text('Seelo'), findsOneWidget);
  });

  testWidgets('SeeloConfig singleton works', (WidgetTester tester) async {
    final config = SeeloConfig();
    expect(config.screenWidth, 412);
    expect(config.screenHeight, 915);
    expect(config.defaultRoomId, 'seelo-desktop');
    expect(config.defaultPort, 3000);
  });
}
