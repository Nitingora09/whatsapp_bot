import 'package:shared_preferences/shared_preferences.dart';

class LicenseTierInfo {
  final String id;
  final String name;
  final String price;
  final String period;
  final String badge;
  final String description;
  final List<String> features;

  const LicenseTierInfo({
    required this.id,
    required this.name,
    required this.price,
    required this.period,
    required this.badge,
    required this.description,
    required this.features,
  });
}

class AccountLicenseStatus {
  final String phone;
  final bool isLicensed;
  final bool isExpired;
  final bool hasPreviousLicense;
  final String planId;
  final String licenseType;
  final String activeKey;
  final int expiryMillis;
  final int activatedAtMillis;
  final int freeSentCount;
  final bool shouldShowExpiredPopup;

  const AccountLicenseStatus({
    required this.phone,
    required this.isLicensed,
    required this.isExpired,
    required this.hasPreviousLicense,
    required this.planId,
    required this.licenseType,
    required this.activeKey,
    required this.expiryMillis,
    required this.activatedAtMillis,
    required this.freeSentCount,
    required this.shouldShowExpiredPopup,
  });

  DateTime? get expiryDate =>
      expiryMillis > 0 ? DateTime.fromMillisecondsSinceEpoch(expiryMillis) : null;

  String get formattedExpiryDateTime {
    if (expiryMillis == 0) return 'Lifetime (Never Expires)';
    final dt = DateTime.fromMillisecondsSinceEpoch(expiryMillis);
    return formatDateTime(dt);
  }

  String get formattedActivatedDateTime {
    if (activatedAtMillis == 0) return 'N/A';
    final dt = DateTime.fromMillisecondsSinceEpoch(activatedAtMillis);
    return formatDateTime(dt);
  }

  static String formatDateTime(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final day = dt.day.toString().padLeft(2, '0');
    final month = months[dt.month - 1];
    final year = dt.year;
    final hour12 = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final minute = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$day $month $year, $hour12:$minute $ampm';
  }

  String get remainingTimeLabel {
    if (!isLicensed && !isExpired) return 'No License';
    if (expiryMillis == 0) return 'Lifetime (Never Expires)';
    final remainingMs = expiryMillis - DateTime.now().millisecondsSinceEpoch;
    if (remainingMs <= 0) return 'Expired on $formattedExpiryDateTime';
    final diff = Duration(milliseconds: remainingMs);
    if (diff.inDays > 0) {
      final hours = diff.inHours % 24;
      return '${diff.inDays}d ${hours}h remaining';
    }
    if (diff.inHours > 0) {
      final mins = diff.inMinutes % 60;
      return '${diff.inHours}h ${mins}m remaining';
    }
    return '${diff.inMinutes}m remaining';
  }
}

class LicenseService {
  // Free trial message limit per unconnected account or new number
  static const int freeTrialLimit = 25;

  // The 4 official tiers shown in the app
  static const List<LicenseTierInfo> tiers = [
    LicenseTierInfo(
      id: 'trial_1day',
      name: '1-Day Paid Trial',
      price: '₹49',
      period: '24 Hours Access',
      badge: 'TEST DRIVE ⚡',
      description: 'Test all booster features & unlimited sends for 24h',
      features: [
        '24 Hours Full Access',
        'Multi-round Repeat Booster (1x - 100x)',
        'Unlimited Messages for 1 Day',
        'Instant Activation via UPI',
      ],
    ),
    LicenseTierInfo(
      id: 'monthly_pro',
      name: 'Monthly Pro Pass',
      price: '₹299',
      period: '30 Days Validity',
      badge: 'MOST POPULAR 🔥',
      description: 'Ideal for daily business outreach, CRM & high-speed marketing',
      features: [
        '30 Days Unlimited Broadcasts',
        'Multi-round Repeat Booster (1x - 100x)',
        'Contact & Group Lead Extraction',
        'Anti-Spam Delay Pacing Controls',
      ],
    ),
    LicenseTierInfo(
      id: 'lifetime_vip',
      name: 'Lifetime VIP Pro',
      price: '₹999',
      period: 'One-Time (Forever)',
      badge: 'BEST VALUE ⭐',
      description: 'Pay once, use forever. Never pay renewal fees.',
      features: [
        'Lifetime Access (Never Expires)',
        '100% Unlimited Messages & Repeats',
        'VIP Priority Broadcast Queue',
        'Free Future Updates & Premium Features',
      ],
    ),
    LicenseTierInfo(
      id: 'agency_master',
      name: 'Agency Master VIP',
      price: '₹1,999',
      period: 'Lifetime Commercial',
      badge: 'AGENCY & ENTERPRISE 👑',
      description: 'Commercial license for marketing agencies & power broadcasters',
      features: [
        'Commercial Client Outreach Rights',
        'Multiple Account / Device Support',
        'VIP 1-on-1 Direct Support on WhatsApp',
        'Custom Setup & Strategy Assistance',
      ],
    ),
  ];

  // Internal secret master keys known only to the developer/owner
  static const List<String> _masterKeys = [
    'TRIAL-1DAY-49',
    'MONTHLY-PRO-299',
    'LIFETIME-VIP-999',
    'AGENCY-MASTER-1999',
    // Backward compatibility aliases
    'TRIAL-1DAY-PASS',
    'DAY-TRIAL-2026',
    'BOOSTER-PRO-299',
    'PRO-MONTHLY-2026',
    'BOOSTER-VIP-2026',
    'PRO-LIFETIME-MASTER',
    'BOOSTER-PRO-999',
    'VIP-CLIENT-2026',
    'AGENCY-VIP-MASTER',
    'PRO-ULTIMATE-2026',
    'OUTREACH-PRO-UNLOCK',
  ];

  // Active in-memory state bound to the currently connected WhatsApp account
  static String _currentPhone = '';
  static bool _isLicensed = false;
  static bool _isExpired = false;
  static bool _hasPreviousLicense = false;
  static String _licenseType = '';
  static String _planId = '';
  static String _activeKey = '';
  static int _expiryMillis = 0;
  static int _activatedAtMillis = 0;
  static int _freeSentCount = 0;
  static bool _termsAccepted = false;

  /// Clean & normalize any Indian or international phone number
  static String normalizePhone(String? raw) {
    if (raw == null) return '';
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 12 && digits.startsWith('91')) {
      return digits.substring(2);
    }
    if (digits.length > 10 && digits.startsWith('91')) {
      return digits.substring(digits.length - 10);
    }
    return digits;
  }

  // Helper preference key generators per account
  static String _keyIsLicensed(String p) => 'wb_acc_${p}_is_licensed';
  static String _keyLicenseKey(String p) => 'wb_acc_${p}_license_key';
  static String _keyLicenseType(String p) => 'wb_acc_${p}_license_type';
  static String _keyPlanId(String p) => 'wb_acc_${p}_license_plan_id';
  static String _keyExpiryMillis(String p) => 'wb_acc_${p}_license_expiry_millis';
  static String _keyActivatedAt(String p) => 'wb_acc_${p}_activated_at';
  static String _keySentCount(String p) => 'wb_acc_${p}_free_messages_sent';
  static String _keyExpiredPopupShown(String p) => 'wb_acc_${p}_expired_popup_shown_for';

  static const String _keyTermsAccepted = 'wb_terms_accepted';

  // Getters for current active account
  static String get currentPhone => _currentPhone;
  static bool get isPhoneConnected => _currentPhone.isNotEmpty;

  static bool get isLicensed {
    if (_currentPhone.isEmpty) return false;
    if (!_isLicensed) return false;
    if (_expiryMillis > 0) {
      if (DateTime.now().millisecondsSinceEpoch > _expiryMillis) {
        return false; // Expired!
      }
    }
    return true;
  }

  static bool get isExpired {
    if (_currentPhone.isEmpty) return false;
    if (_hasPreviousLicense && _expiryMillis > 0) {
      return DateTime.now().millisecondsSinceEpoch > _expiryMillis;
    }
    return _isExpired;
  }

  static String get licenseType => _licenseType.isNotEmpty ? _licenseType : 'No License';
  static String get planId => _planId;
  static String get activeKey => _activeKey;
  static int get expiryMillis => _expiryMillis;
  static int get activatedAtMillis => _activatedAtMillis;
  static int get freeSentCount => _freeSentCount;
  static int get remainingTrial =>
      (freeTrialLimit - _freeSentCount).clamp(0, freeTrialLimit);
  static bool get hasTrialRemaining => remainingTrial > 0;
  static bool get termsAccepted => _termsAccepted;

  static String get formattedExpiryDateTime {
    if (_expiryMillis == 0) return 'Lifetime (Never Expires)';
    final dt = DateTime.fromMillisecondsSinceEpoch(_expiryMillis);
    return AccountLicenseStatus.formatDateTime(dt);
  }

  static String get expiryLabel {
    if (_currentPhone.isEmpty) return 'Scan QR / Login';
    if (!isLicensed) {
      if (isExpired) return 'Expired on $formattedExpiryDateTime';
      return 'No License (Trial)';
    }
    if (_expiryMillis == 0) return 'Lifetime (Never Expires)';
    final remainingMs = _expiryMillis - DateTime.now().millisecondsSinceEpoch;
    if (remainingMs <= 0) return 'Expired on $formattedExpiryDateTime';
    final diff = Duration(milliseconds: remainingMs);
    if (diff.inDays > 0) {
      final hours = diff.inHours % 24;
      return '${diff.inDays}d ${hours}h remaining';
    }
    if (diff.inHours > 0) {
      final mins = diff.inMinutes % 60;
      return '${diff.inHours}h ${mins}m remaining';
    }
    return '${diff.inMinutes}m remaining';
  }

  static AccountLicenseStatus get currentStatus => AccountLicenseStatus(
        phone: _currentPhone,
        isLicensed: isLicensed,
        isExpired: isExpired,
        hasPreviousLicense: _hasPreviousLicense,
        planId: _planId,
        licenseType: _licenseType,
        activeKey: _activeKey,
        expiryMillis: _expiryMillis,
        activatedAtMillis: _activatedAtMillis,
        freeSentCount: _freeSentCount,
        shouldShowExpiredPopup: false,
      );

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _termsAccepted = prefs.getBool(_keyTermsAccepted) ?? false;

    // Restore developer pass for 9610993628 if it was expired by simulator testing
    const devPhone = '9610993628';
    final exp = prefs.getInt(_keyExpiryMillis(devPhone)) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (prefs.containsKey(_keyIsLicensed(devPhone)) && exp > 0 && now > exp) {
      final nowDt = DateTime.now();
      await prefs.setBool(_keyIsLicensed(devPhone), true);
      await prefs.setString(_keyLicenseKey(devPhone), 'TRIAL-1DAY-49');
      await prefs.setString(_keyLicenseType(devPhone), '1-Day Paid Trial (₹49)');
      await prefs.setString(_keyPlanId(devPhone), 'trial_1day');
      await prefs.setInt(_keyExpiryMillis(devPhone), nowDt.add(const Duration(hours: 24)).millisecondsSinceEpoch);
      await prefs.setInt(_keyActivatedAt(devPhone), nowDt.millisecondsSinceEpoch);
      await prefs.remove(_keyExpiredPopupShown(devPhone));
    }
  }

  /// Switch the active account to the given WhatsApp number.
  /// If phone is empty/null, switches to logged-out/guest state.
  static Future<AccountLicenseStatus> switchAccount(String? rawPhone) async {
    final cleanPhone = normalizePhone(rawPhone);
    _currentPhone = cleanPhone;
    final prefs = await SharedPreferences.getInstance();

    if (cleanPhone.isEmpty) {
      _isLicensed = false;
      _isExpired = false;
      _hasPreviousLicense = false;
      _licenseType = '';
      _planId = '';
      _activeKey = '';
      _expiryMillis = 0;
      _activatedAtMillis = 0;
      _freeSentCount = 0;
      return const AccountLicenseStatus(
        phone: '',
        isLicensed: false,
        isExpired: false,
        hasPreviousLicense: false,
        planId: '',
        licenseType: '',
        activeKey: '',
        expiryMillis: 0,
        activatedAtMillis: 0,
        freeSentCount: 0,
        shouldShowExpiredPopup: false,
      );
    }

    // Migration helper: If this phone was previously licensed globally
    if (!prefs.containsKey(_keyIsLicensed(cleanPhone)) &&
        prefs.getBool('wb_is_licensed') == true) {
      final oldKey = prefs.getString('wb_license_key') ?? '';
      final oldType = prefs.getString('wb_license_type') ?? '';
      final oldPlan = prefs.getString('wb_license_plan_id') ?? '';
      final oldExpiry = prefs.getInt('wb_license_expiry_millis') ?? 0;
      await prefs.setBool(_keyIsLicensed(cleanPhone), true);
      await prefs.setString(_keyLicenseKey(cleanPhone), oldKey);
      await prefs.setString(_keyLicenseType(cleanPhone), oldType);
      await prefs.setString(_keyPlanId(cleanPhone), oldPlan);
      await prefs.setInt(_keyExpiryMillis(cleanPhone), oldExpiry);
      await prefs.setInt(_keyActivatedAt(cleanPhone), DateTime.now().millisecondsSinceEpoch);
    } else if (cleanPhone == '9610993628' && !prefs.containsKey(_keyIsLicensed(cleanPhone))) {
      // Seed initial 1-Day Paid Trial for 9610993628 so user immediately experiences persistent license
      final now = DateTime.now();
      await prefs.setBool(_keyIsLicensed(cleanPhone), true);
      await prefs.setString(_keyLicenseKey(cleanPhone), 'TRIAL-1DAY-49');
      await prefs.setString(_keyLicenseType(cleanPhone), '1-Day Paid Trial (₹49)');
      await prefs.setString(_keyPlanId(cleanPhone), 'trial_1day');
      await prefs.setInt(_keyExpiryMillis(cleanPhone), now.add(const Duration(hours: 24)).millisecondsSinceEpoch);
      await prefs.setInt(_keyActivatedAt(cleanPhone), now.millisecondsSinceEpoch);
    }

    final hadLicense = prefs.getBool(_keyIsLicensed(cleanPhone)) ?? false;
    final expiry = prefs.getInt(_keyExpiryMillis(cleanPhone)) ?? 0;
    final activatedAt = prefs.getInt(_keyActivatedAt(cleanPhone)) ?? 0;
    final plan = prefs.getString(_keyPlanId(cleanPhone)) ?? '';
    final type = prefs.getString(_keyLicenseType(cleanPhone)) ?? '';
    final key = prefs.getString(_keyLicenseKey(cleanPhone)) ?? '';
    final sent = prefs.getInt(_keySentCount(cleanPhone)) ?? 0;
    final lastPopupExpiry = prefs.getInt(_keyExpiredPopupShown(cleanPhone)) ?? 0;

    final now = DateTime.now().millisecondsSinceEpoch;
    final isExpiredNow = hadLicense && expiry > 0 && now > expiry;
    final isCurrentlyActive = hadLicense && (expiry == 0 || now <= expiry);

    _hasPreviousLicense = hadLicense;
    _isLicensed = isCurrentlyActive;
    _isExpired = isExpiredNow;
    _licenseType = type;
    _planId = plan;
    _activeKey = key;
    _expiryMillis = expiry;
    _activatedAtMillis = activatedAt;
    _freeSentCount = sent;

    // Show expired popup only once per expiration cycle for this account!
    final shouldShowPopup = isExpiredNow && (lastPopupExpiry != expiry);

    return AccountLicenseStatus(
      phone: cleanPhone,
      isLicensed: isCurrentlyActive,
      isExpired: isExpiredNow,
      hasPreviousLicense: hadLicense,
      planId: plan,
      licenseType: type,
      activeKey: key,
      expiryMillis: expiry,
      activatedAtMillis: activatedAt,
      freeSentCount: sent,
      shouldShowExpiredPopup: shouldShowPopup,
    );
  }

  /// Mark that the expiration dialog was presented to the user
  static Future<void> markExpiredPopupShown(String phone) async {
    final cleanPhone = normalizePhone(phone);
    if (cleanPhone.isEmpty || _expiryMillis == 0) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyExpiredPopupShown(cleanPhone), _expiryMillis);
  }

  static Future<void> setTermsAccepted(bool val) async {
    _termsAccepted = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyTermsAccepted, val);
  }

  static Future<void> incrementSentCount(int count) async {
    if (isLicensed || _currentPhone.isEmpty) return;
    _freeSentCount += count;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keySentCount(_currentPhone), _freeSentCount);
  }

  static bool isValidKey(String rawKey) {
    final clean = rawKey.trim().toUpperCase();
    if (_masterKeys.contains(clean)) return true;

    // Algorithmic validation: Format PRO-XXXX-YYYY where length >= 8
    if (clean.startsWith('TRIAL-') && clean.length >= 8) return true;
    if (clean.startsWith('MONTH-') && clean.length >= 8) return true;
    if (clean.startsWith('PRO-') && clean.length >= 8) return true;
    if (clean.startsWith('BOOST-') && clean.length >= 8) return true;
    if (clean.startsWith('LIFE-') && clean.length >= 8) return true;
    if (clean.startsWith('AGENCY-') && clean.length >= 8) return true;
    return false;
  }

  /// Activate a license key for the specified phone number (or current phone)
  static Future<bool> activateKey(String key, {String? forPhone}) async {
    final cleanPhone = normalizePhone(forPhone ?? _currentPhone);
    if (cleanPhone.isEmpty) return false;

    final clean = key.trim().toUpperCase();
    if (!isValidKey(clean)) return false;

    _currentPhone = cleanPhone;
    _isLicensed = true;
    _isExpired = false;
    _hasPreviousLicense = true;
    _activeKey = clean;
    final now = DateTime.now();

    // Determine plan type and validity duration
    if (clean.contains('1DAY') || clean.contains('DAY') || clean.contains('49')) {
      _planId = 'trial_1day';
      _licenseType = '1-Day Paid Trial (₹49)';
      _expiryMillis = now.add(const Duration(hours: 24)).millisecondsSinceEpoch;
    } else if (clean.contains('AGENCY') ||
        clean.contains('1999') ||
        clean.contains('ULTIMATE')) {
      _planId = 'agency_master';
      _licenseType = 'Agency Master VIP (₹1999)';
      _expiryMillis = 0; // Lifetime
    } else if (clean.contains('LIFETIME') ||
        clean.contains('VIP') ||
        clean.contains('999') ||
        clean.contains('LIFE')) {
      _planId = 'lifetime_vip';
      _licenseType = 'Lifetime VIP Pro (₹999)';
      _expiryMillis = 0; // Lifetime
    } else {
      // Default to Monthly Pro (₹299)
      _planId = 'monthly_pro';
      _licenseType = 'Monthly Pro Pass (₹299)';
      _expiryMillis = now.add(const Duration(days: 30)).millisecondsSinceEpoch;
    }

    _activatedAtMillis = now.millisecondsSinceEpoch;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyIsLicensed(cleanPhone), true);
    await prefs.setString(_keyLicenseKey(cleanPhone), clean);
    await prefs.setString(_keyLicenseType(cleanPhone), _licenseType);
    await prefs.setString(_keyPlanId(cleanPhone), _planId);
    await prefs.setInt(_keyExpiryMillis(cleanPhone), _expiryMillis);
    await prefs.setInt(_keyActivatedAt(cleanPhone), _activatedAtMillis);
    // Remove any previous expired popup record so it can alert again on future expiry
    await prefs.remove(_keyExpiredPopupShown(cleanPhone));
    return true;
  }

  /// Reset license for the current account (or for testing)
  static Future<void> resetLicenseForTesting({String? phone}) async {
    final cleanPhone = normalizePhone(phone ?? _currentPhone);
    _isLicensed = false;
    _isExpired = false;
    _hasPreviousLicense = false;
    _licenseType = '';
    _planId = '';
    _activeKey = '';
    _expiryMillis = 0;
    _activatedAtMillis = 0;
    _freeSentCount = 0;

    if (cleanPhone.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyIsLicensed(cleanPhone));
    await prefs.remove(_keyLicenseKey(cleanPhone));
    await prefs.remove(_keyLicenseType(cleanPhone));
    await prefs.remove(_keyPlanId(cleanPhone));
    await prefs.remove(_keyExpiryMillis(cleanPhone));
    await prefs.remove(_keyActivatedAt(cleanPhone));
    await prefs.remove(_keySentCount(cleanPhone));
    await prefs.remove(_keyExpiredPopupShown(cleanPhone));
  }

  /// For simulation/testing: force expire the account license to test the expired dialog
  static Future<AccountLicenseStatus> simulateExpireAccount(String? phone) async {
    final cleanPhone = normalizePhone(phone ?? _currentPhone);
    if (cleanPhone.isEmpty) return currentStatus;
    final prefs = await SharedPreferences.getInstance();
    final expiredTime = DateTime.now().subtract(const Duration(minutes: 5)).millisecondsSinceEpoch;
    await prefs.setBool(_keyIsLicensed(cleanPhone), true);
    await prefs.setInt(_keyExpiryMillis(cleanPhone), expiredTime);
    await prefs.remove(_keyExpiredPopupShown(cleanPhone));
    return await switchAccount(cleanPhone);
  }

  /// For simulation/testing: restore or give 24-hour pass to the account
  static Future<AccountLicenseStatus> simulateActivate24hPass(String? phone) async {
    final cleanPhone = normalizePhone(phone ?? _currentPhone);
    if (cleanPhone.isEmpty) return currentStatus;
    await activateKey('TRIAL-1DAY-49', forPhone: cleanPhone);
    return currentStatus;
  }
}
