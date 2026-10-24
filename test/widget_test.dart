import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whatsapp_bot/main.dart';
import 'package:whatsapp_bot/services/license_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LicenseService.init();
  });

  testWidgets('WhatsAppBotApp smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const WhatsAppBotApp());

    expect(find.text('WhatsApp Booster Pro'), findsOneWidget);
    expect(find.text('Outreach Booster'), findsOneWidget);
    expect(find.text('WhatsApp App (Native)'), findsOneWidget);
    expect(find.text('Meta Cloud API'), findsOneWidget);
  });
}
