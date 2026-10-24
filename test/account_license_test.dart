import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whatsapp_bot/services/license_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LicenseService.init();
  });

  test('Normalize Indian phone numbers correctly', () {
    expect(LicenseService.normalizePhone('+91 96109 93628'), '9610993628');
    expect(LicenseService.normalizePhone('919610993628'), '9610993628');
    expect(LicenseService.normalizePhone('9610993628'), '9610993628');
    expect(LicenseService.normalizePhone(null), '');
  });

  test('9610993628 gets 1-Day Trial seed and is persistent across logins', () async {
    // 1. Initial login with 9610993628
    final status1 = await LicenseService.switchAccount('9610993628');
    expect(status1.isLicensed, isTrue);
    expect(status1.isExpired, isFalse);
    expect(status1.phone, '9610993628');
    expect(status1.planId, 'trial_1day');
    expect(status1.licenseType, contains('1-Day Paid Trial'));
    expect(LicenseService.isLicensed, isTrue);
    expect(LicenseService.expiryLabel, contains('remaining'));

    // 2. User logs out
    final guestStatus = await LicenseService.switchAccount(null);
    expect(guestStatus.isLicensed, isFalse);
    expect(LicenseService.isLicensed, isFalse);
    expect(LicenseService.currentPhone, '');

    // 3. User logs back in with 9610993628 - License restored, NOT asked for premium again!
    final status2 = await LicenseService.switchAccount('9610993628');
    expect(status2.isLicensed, isTrue);
    expect(status2.isExpired, isFalse);
    expect(LicenseService.isLicensed, isTrue);
    expect(LicenseService.expiryLabel, contains('remaining'));
  });

  test('Another number login is 100% isolated and has no premium', () async {
    // 1. Login with 9610993628 (licensed)
    await LicenseService.switchAccount('9610993628');
    expect(LicenseService.isLicensed, isTrue);

    // 2. Scan and login with a different number 9876543210
    final otherStatus = await LicenseService.switchAccount('9876543210');
    expect(otherStatus.isLicensed, isFalse);
    expect(otherStatus.isExpired, isFalse);
    expect(otherStatus.hasPreviousLicense, isFalse);
    expect(otherStatus.phone, '9876543210');
    expect(LicenseService.isLicensed, isFalse);
    expect(LicenseService.freeSentCount, 0);

    // 3. Activate key specifically for 9876543210
    final activated = await LicenseService.activateKey('MONTHLY-PRO-299', forPhone: '9876543210');
    expect(activated, isTrue);
    expect(LicenseService.isLicensed, isTrue);
    expect(LicenseService.licenseType, contains('Monthly Pro'));

    // 4. Switch back to 9610993628 -> It retains its own 1-Day Trial, not Monthly Pro!
    final originalStatus = await LicenseService.switchAccount('9610993628');
    expect(originalStatus.planId, 'trial_1day');
  });

  test('Expired pass triggers shouldShowExpiredPopup and shows exact last date/time', () async {
    // 1. Login with 9610993628
    await LicenseService.switchAccount('9610993628');

    // 2. Simulate expiration (e.g. 1-day passed)
    final expiredStatus = await LicenseService.simulateExpireAccount('9610993628');
    expect(expiredStatus.isLicensed, isFalse);
    expect(expiredStatus.isExpired, isTrue);
    expect(expiredStatus.shouldShowExpiredPopup, isTrue);
    expect(expiredStatus.formattedExpiryDateTime, isNotEmpty);
    expect(LicenseService.isExpired, isTrue);
    expect(LicenseService.expiryLabel, contains('Expired on'));

    // 3. Mark popup as shown so it does not annoy user on every refresh
    await LicenseService.markExpiredPopupShown('9610993628');
    final rechecked = await LicenseService.switchAccount('9610993628');
    expect(rechecked.shouldShowExpiredPopup, isFalse);
    expect(rechecked.isExpired, isTrue);
  });
}
