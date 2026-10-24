import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform, Process, File, Directory, ProcessStartMode;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'services/local_gateway_service.dart';
import 'services/license_service.dart';
import 'services/ad_service.dart';
import 'constants/payment_qr_image.dart';

class CustomContactLead {
  final String name;
  final String phone;

  const CustomContactLead({required this.name, required this.phone});
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LicenseService.init();
  runApp(const WhatsAppBotApp());
}

class WhatsAppBotApp extends StatelessWidget {
  const WhatsAppBotApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WhatsApp Outreach Booster Pro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF128C7E),
          primary: const Color(0xFF128C7E),
          secondary: const Color(0xFF25D366),
          brightness: Brightness.light,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.grey.shade50,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF128C7E), width: 2),
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.grey.shade200),
          ),
        ),
      ),
      home: const AutoWebBotPage(),
    );
  }
}

// ============================================================================
// TAB 1: 1-CLICK AUTOMATIC WHATSAPP WEB BOT (Supports Contacts & Groups)
// ============================================================================
class AutoWebBotPage extends StatefulWidget {
  const AutoWebBotPage({super.key});

  @override
  State<AutoWebBotPage> createState() => _AutoWebBotPageState();
}

class _AutoWebBotPageState extends State<AutoWebBotPage> {
  final _serverUrlController =
      TextEditingController(text: 'http://localhost:3000');
  final _gatewayService = LocalGatewayService();

  final _numbersController = TextEditingController();
  final _messageController = TextEditingController(
    text:
        'Namaste {name}! I came across your business and would love to help you build modern web/mobile apps to get more customers. When would be a good time to connect?',
  );

  final _countryCodeController = TextEditingController(text: '91');
  final _pairPhoneController = TextEditingController();
  final _boosterCountController = TextEditingController(text: '1');
  int _boosterRepeatCount = 1;
  double _delaySeconds = 2.0;

  bool _isCheckingStatus = false;
  GatewayStatus? _status;
  String? _lastTrackedUser;
  bool _isSending = false;
  bool _isStopping = false;
  BulkSendResponse? _sendResult;
  Timer? _statusTimer;

  String? _pairingCode;
  bool _isRequestingPairingCode = false;

  // Groups and contacts
  List<WhatsAppGroupItem> _availableGroups = [];
  bool _isLoadingGroups = false;
  bool _termsAccepted = false;

  @override
  void initState() {
    super.initState();
    _termsAccepted = LicenseService.termsAccepted;
    _checkServerStatus();
    _statusTimer = Timer.periodic(const Duration(milliseconds: 2500), (_) {
      if (mounted && !_isSending) {
        _checkServerStatus(silent: true);
      }
    });
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _serverUrlController.dispose();
    _numbersController.dispose();
    _messageController.dispose();
    _countryCodeController.dispose();
    _pairPhoneController.dispose();
    _boosterCountController.dispose();
    super.dispose();
  }

  int _consecutiveFailures = 0;
  bool _isStartingServer = false;
  bool _hasAttemptedAutoStart = false;

  Future<void> _startLocalServer() async {
    if (kIsWeb || !Platform.isWindows) {
      _showSnackbar('Local server is only supported on Windows Desktop.');
      return;
    }

    setState(() {
      _isStartingServer = true;
    });

    try {
      String? batPath;
      String? serverDir;

      final currentDir = Directory.current.path;
      if (File('$currentDir\\start_bot.bat').existsSync()) {
        batPath = '$currentDir\\start_bot.bat';
        serverDir = '$currentDir\\whatsapp_server';
      } else {
        final exeDir = File(Platform.resolvedExecutable).parent.path;
        if (File('$exeDir\\start_bot.bat').existsSync()) {
          batPath = '$exeDir\\start_bot.bat';
          serverDir = '$exeDir\\whatsapp_server';
        } else if (File('$exeDir\\..\\..\\..\\start_bot.bat').existsSync()) {
          batPath = File('$exeDir\\..\\..\\..\\start_bot.bat').resolveSymbolicLinksSync();
          serverDir = File('$exeDir\\..\\..\\..\\whatsapp_server').resolveSymbolicLinksSync();
        }
      }

      if (batPath == null && File(r'd:\StudioProjects\whatsapp_bot\start_bot.bat').existsSync()) {
        batPath = r'd:\StudioProjects\whatsapp_bot\start_bot.bat';
        serverDir = r'd:\StudioProjects\whatsapp_bot\whatsapp_server';
      }

      if (batPath != null && File(batPath).existsSync()) {
        await Process.start(
          'cmd.exe',
          ['/c', 'start', '""', batPath],
          mode: ProcessStartMode.detached,
        );
        _showSnackbar('🚀 Starting WhatsApp Server... Connecting in background.');
      } else if (serverDir != null && Directory(serverDir).existsSync()) {
        await Process.start(
          'cmd.exe',
          ['/c', 'start', '""', 'node', 'server.js'],
          workingDirectory: serverDir,
          mode: ProcessStartMode.detached,
        );
        _showSnackbar('🚀 Starting WhatsApp Server... Connecting in background.');
      } else {
        _showSnackbar('⚠️ Could not find start_bot.bat or whatsapp_server folder.');
      }
    } catch (e) {
      _showSnackbar('Error starting server: $e');
    } finally {
      Future.delayed(const Duration(seconds: 2), () => _checkServerStatus());
      Future.delayed(const Duration(seconds: 4), () => _checkServerStatus());
      Future.delayed(const Duration(seconds: 7), () {
        if (mounted) {
          setState(() {
            _isStartingServer = false;
          });
          _checkServerStatus();
        }
      });
    }
  }

  Future<void> _checkServerStatus({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isCheckingStatus = true;
      });
    }
    _gatewayService.baseUrl = _serverUrlController.text.trim();
    final res = await _gatewayService.checkStatus();
    if (mounted) {
      setState(() {
        _isCheckingStatus = false;
        if (res.connected || res.isLoggedIn) {
          _status = res;
          _consecutiveFailures = 0;
        } else {
          _consecutiveFailures++;
          // Only switch to logged-out state if we were not logged in or 3 consecutive polls failed
          if (_status == null || !_status!.isLoggedIn || _consecutiveFailures >= 3) {
            _status = res;
          }
        }
      });

      // Synchronize per-number account license & data isolation
      final currentUser = (res.connected || res.isLoggedIn) ? res.user : null;
      final cleanCurrent = LicenseService.normalizePhone(currentUser);
      if (cleanCurrent != _lastTrackedUser) {
        final previousUser = _lastTrackedUser;
        _lastTrackedUser = cleanCurrent;

        // If switched to another distinct number, clear old group extractions & send reports
        if (previousUser != null &&
            previousUser.isNotEmpty &&
            cleanCurrent.isNotEmpty &&
            previousUser != cleanCurrent) {
          _availableGroups = [];
          _sendResult = null;
        }

        final accountStatus = await LicenseService.switchAccount(cleanCurrent);
        if (mounted) {
          setState(() {});
          if (accountStatus.shouldShowExpiredPopup) {
            _showPassExpiredDialog(accountStatus);
          }
        }
      }

      // Auto-start server once if completely offline on startup
      if (!_hasAttemptedAutoStart && !res.connected && !res.hasQr && _consecutiveFailures >= 2) {
        _hasAttemptedAutoStart = true;
        _startLocalServer();
      }
    }
  }

  Future<void> _requestPairingCode() async {
    final phone = _pairPhoneController.text.trim();
    if (phone.isEmpty) {
      _showSnackbar('Please enter your WhatsApp phone number.');
      return;
    }

    setState(() {
      _isRequestingPairingCode = true;
      _pairingCode = null;
    });

    final defaultCode = _countryCodeController.text.trim().replaceAll('+', '');
    _gatewayService.baseUrl = _serverUrlController.text.trim();
    final res = await _gatewayService.requestPairingCode(
      phone,
      countryCode: defaultCode.isNotEmpty ? defaultCode : '91',
    );

    if (mounted) {
      setState(() {
        _isRequestingPairingCode = false;
      });

      if (res['success'] == true && res['code'] != null) {
        setState(() {
          _pairingCode = res['code'].toString();
        });
        _showSnackbar('Pairing code generated! Enter it in your WhatsApp.');
      } else {
        _showSnackbar(
          res['error']?.toString() ?? 'Could not generate pairing code.',
        );
      }
    }
  }

  Future<void> _logoutWhatsApp() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log Out of WhatsApp?'),
        content: const Text(
          'Are you sure you want to log out of WhatsApp? You will need to scan QR or use a pairing code to link your device again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Log Out'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    _gatewayService.baseUrl = _serverUrlController.text.trim();
    final ok = await _gatewayService.logout();
    if (mounted) {
      if (ok) {
        _lastTrackedUser = '';
        await LicenseService.switchAccount('');
        setState(() {
          _pairingCode = null;
          _status = null;
          _availableGroups = [];
          _sendResult = null;
        });
        _showSnackbar('Logged out successfully! Reconnect using QR or pairing code.');
        _checkServerStatus();
      } else {
        _showSnackbar('Logout failed. Please check if the local server is running.');
      }
    }
  }

  Future<void> _resetSession() async {
    _gatewayService.baseUrl = _serverUrlController.text.trim();
    final ok = await _gatewayService.resetSession();
    if (mounted) {
      if (ok) {
        _lastTrackedUser = '';
        await LicenseService.switchAccount('');
        setState(() {
          _pairingCode = null;
          _status = null;
          _availableGroups = [];
          _sendResult = null;
        });
        _showSnackbar('Session reset! Generating fresh QR code...');
        _checkServerStatus();
      } else {
        _showSnackbar('Could not reset session. Ensure local server is running.');
      }
    }
  }

  // 1. IMPORT CONTACTS (Cross-platform: Windows, Web, Android, iOS)
  Future<void> _pickContactsFromPhone() async {
    final isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);

    if (!isMobile) {
      _showDesktopContactsOrBulkDialog();
      return;
    }

    try {
      final status = await Permission.contacts.request();
      if (status.isGranted) {
        final contacts =
            await FlutterContacts.getAll(properties: {ContactProperty.phone});

        if (!mounted) return;

        // Strict 10-digit deduplication across all phone accounts (Google, WhatsApp sync, SIM)
        final seenNorm = <String>{};
        final List<CustomContactLead> leads = [];

        for (final c in contacts) {
          final displayName = (c.displayName != null && c.displayName!.trim().isNotEmpty)
              ? c.displayName!.trim()
              : 'Client';

          for (final p in c.phones) {
            final digits = p.number.replaceAll(RegExp(r'\D'), '');
            final norm = digits.length > 10 ? digits.substring(digits.length - 10) : digits;
            if (norm.length >= 10 && !seenNorm.contains(norm)) {
              seenNorm.add(norm);
              leads.add(CustomContactLead(
                name: displayName,
                phone: p.number.trim(),
              ));
            }
          }
        }

        if (leads.isEmpty) {
          _showSnackbar('No contacts with phone numbers found on this device.');
          return;
        }

        _showParsedContactsSelectionDialog(
          leads,
          title: 'Phone Contacts',
        );
      } else if (status.isPermanentlyDenied) {
        _showPermissionDeniedDialog();
      } else {
        _showSnackbar(
          'Contacts access permission was denied. Please allow it to import contacts.',
        );
      }
    } on MissingPluginException catch (_) {
      if (!mounted) return;
      _showDesktopContactsOrBulkDialog(
        subtitle:
            'Phone address book native plugin requires full APK build. You can import from WhatsApp contacts or paste leads directly:',
      );
    } catch (_) {
      if (!mounted) return;
      _showDesktopContactsOrBulkDialog();
    }
  }

  void _showDesktopContactsOrBulkDialog({String? subtitle}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Center(
        child: Container(
          constraints: BoxConstraints(
            maxWidth: 580,
            maxHeight: MediaQuery.of(ctx).size.height * 0.88,
          ),
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 20,
                spreadRadius: 2,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.people_alt, color: Color(0xFF128C7E), size: 24),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Import Your Contacts & Leads',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle ??
                        'Apne phone ke real contacts load karne ke liye option chunein:',
                    style: const TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),

                  // Option 1: WhatsApp Direct 1-to-1 Chats
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.teal.shade50,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.chat, color: Color(0xFF128C7E)),
                    ),
                    title: const Text('WhatsApp Direct Chats',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: const Text(
                        'Load all genuine direct chats and verified contacts from linked WhatsApp',
                        style: TextStyle(fontSize: 12)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.pop(ctx);
                      _fetchAndSelectWhatsAppChats();
                    },
                  ),
                  const Divider(),

                  // Option 2: File Picker (.vcf or .csv)
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.file_upload, color: Color(0xFF25D366)),
                    ),
                    title: const Text('Phone Contacts File (.vcf / .csv)',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: const Text(
                        'Select exported .vcf or .csv file (imports contacts with names and numbers)',
                        style: TextStyle(fontSize: 12)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.pop(ctx);
                      _pickFileAndParseContacts();
                    },
                  ),
                  const Divider(),

                  // Option 3: Paste Contacts / Numbers
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.paste, color: Colors.blue),
                    ),
                    title: const Text('Paste Contacts / Numbers List',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: const Text(
                        'Paste numbers copied from Excel, Notepad, or WhatsApp',
                        style: TextStyle(fontSize: 12)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.pop(ctx);
                      _showPasteOrPathDialog();
                    },
                  ),
                  const Divider(),

                  // Option 4: Phone Export Guide
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.phone_android, color: Colors.amber),
                    ),
                    title: const Text('How to Export Phone Contacts?',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: const Text(
                        '10-second guide to export .vcf contacts from your phone Contacts app',
                        style: TextStyle(fontSize: 12)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.pop(ctx);
                      _showPhoneExportGuideDialog();
                    },
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickFileAndParseContacts() async {
    String? filePath;

    if (!kIsWeb && Platform.isWindows) {
      try {
        final result = await Process.run('powershell', [
          '-NoProfile',
          '-Command',
          r'[System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms") | Out-Null; $dialog = New-Object System.Windows.Forms.OpenFileDialog; $dialog.InitialDirectory = [Environment]::GetFolderPath("UserProfile") + "\Downloads"; $dialog.Filter = "Contacts (*.vcf;*.csv;*.txt)|*.vcf;*.csv;*.txt|All Files (*.*)|*.*"; $dialog.Title = "Select Contacts File (.vcf / .csv)"; if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { Write-Output $dialog.FileName }'
        ]);
        final output = result.stdout.toString().trim();
        if (output.isNotEmpty && File(output).existsSync()) {
          filePath = output;
        }
      } catch (_) {}
    }

    if (filePath != null) {
      try {
        final content = await File(filePath).readAsString();
        final contacts = _parseContactsFromText(content);
        if (!mounted) return;
        if (contacts.isNotEmpty) {
          _showParsedContactsSelectionDialog(
            contacts,
            title: 'Contacts from ${filePath.split(RegExp(r"[\\/]")).last}',
          );
        } else {
          _showSnackbar('No valid 10-digit phone numbers found in file.');
        }
      } catch (e) {
        _showSnackbar('File read error: $e');
      }
    } else {
      _showPasteOrPathDialog();
    }
  }

  List<CustomContactLead> _parseContactsFromText(String content) {
    final List<CustomContactLead> list = [];
    final seen = <String>{};

    // A) Check for vCard (.vcf)
    if (content.contains('BEGIN:VCARD')) {
      final vcards = content.split('BEGIN:VCARD');
      for (var card in vcards) {
        if (card.trim().isEmpty) continue;
        String name = 'Client';
        String phone = '';

        for (var line in card.split(RegExp(r'[\r\n]+'))) {
          line = line.trim();
          if (line.startsWith('FN:') || line.startsWith('FN;')) {
            name = line.substring(line.indexOf(':') + 1).trim();
          } else if (line.startsWith('N:') && name == 'Client') {
            final parts = line.substring(line.indexOf(':') + 1).split(';');
            final joined =
                parts.where((p) => p.trim().isNotEmpty).join(' ').trim();
            if (joined.isNotEmpty) name = joined;
          } else if (line.startsWith('TEL') || line.contains('TEL;')) {
            final rawPhone = line.substring(line.indexOf(':') + 1).trim();
            final clean = rawPhone.replaceAll(RegExp(r'[^0-9]'), '');
            if (clean.length >= 10) {
              phone = clean;
            }
          }
        }

        if (phone.isNotEmpty) {
          final norm = phone.length > 10 ? phone.substring(phone.length - 10) : phone;
          if (!seen.contains(norm)) {
            seen.add(norm);
            list.add(CustomContactLead(
              name: name.isNotEmpty ? name : 'Client',
              phone: phone,
            ));
          }
        }
      }
      return list;
    }

    // B) CSV or line-by-line format:
    final lines = content.split(RegExp(r'[\r\n]+'));
    for (var line in lines) {
      line = line.trim();
      if (line.isEmpty) continue;

      String name = 'Client';
      String phone = '';

      if (line.contains(',') ||
          line.contains('\t') ||
          line.contains(';') ||
          line.contains(':')) {
        final delimiter = line.contains(',')
            ? ','
            : (line.contains('\t')
                ? '\t'
                : (line.contains(';') ? ';' : ':'));
        final parts = line.split(delimiter);
        if (parts.length >= 2) {
          final p1 = parts[0].trim();
          final p2 = parts[1].trim();

          final d1 = p1.replaceAll(RegExp(r'[^0-9]'), '');
          final d2 = p2.replaceAll(RegExp(r'[^0-9]'), '');

          if (d1.length >= 10 && d2.length < 10) {
            phone = d1;
            name = p2;
          } else if (d2.length >= 10) {
            phone = d2;
            name = p1;
          } else if (d1.length >= 10) {
            phone = d1;
            name = p2;
          }
        }
      } else {
        final digits = line.replaceAll(RegExp(r'[^0-9]'), '');
        if (digits.length >= 10) {
          phone = digits;
        }
      }

      if (phone.isNotEmpty) {
        final norm = phone.length > 10 ? phone.substring(phone.length - 10) : phone;
        if (!seen.contains(norm)) {
          seen.add(norm);
          list.add(CustomContactLead(
            name: name.isNotEmpty ? name : 'Client',
            phone: phone,
          ));
        }
      }
    }

    return list;
  }

  void _showParsedContactsSelectionDialog(
    List<CustomContactLead> rawContacts, {
    String title = 'Select Contacts',
  }) {
    // 100% Strict deduplication by normalized phone number
    final seen = <String>{};
    final contacts = <CustomContactLead>[];
    for (var c in rawContacts) {
      final digits = c.phone.replaceAll(RegExp(r'\D'), '');
      final norm = digits.length > 10 ? digits.substring(digits.length - 10) : digits;
      if (norm.isNotEmpty && !seen.contains(norm)) {
        seen.add(norm);
        contacts.add(c);
      }
    }

    final selectedIndices = <int>{for (var i = 0; i < contacts.length; i++) i};
    final searchController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 640),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final query = searchController.text.toLowerCase();
          final filtered = contacts.asMap().entries.where((entry) {
            final c = entry.value;
            final name = c.name.toLowerCase();
            final phone = c.phone.toLowerCase();
            return name.contains(query) || phone.contains(query);
          }).toList();

          final isAllSelected = selectedIndices.length == contacts.length;

          return SizedBox(
            height: MediaQuery.of(context).size.height * 0.85,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.contacts, color: Color(0xFF128C7E), size: 24),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '$title (${contacts.length})',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        icon: Icon(
                          isAllSelected ? Icons.deselect : Icons.select_all,
                          size: 16,
                        ),
                        label:
                            Text(isAllSelected ? 'Deselect All' : 'Select All'),
                        onPressed: () {
                          setModalState(() {
                            if (isAllSelected) {
                              selectedIndices.clear();
                            } else {
                              selectedIndices.addAll(
                                  List.generate(contacts.length, (i) => i));
                            }
                          });
                        },
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: 'Close',
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: searchController,
                    decoration: const InputDecoration(
                      labelText: 'Search contacts by name or number...',
                      prefixIcon: Icon(Icons.search),
                      isDense: true,
                    ),
                    onChanged: (_) => setModalState(() {}),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: filtered.isEmpty
                        ? const Center(
                            child: Text(
                              'No contacts found',
                              style: TextStyle(color: Colors.grey),
                            ),
                          )
                        : ListView.separated(
                            itemCount: filtered.length,
                            separatorBuilder: (_, _) => const Divider(height: 1),
                            itemBuilder: (context, i) {
                              final originalIndex = filtered[i].key;
                              final contact = filtered[i].value;
                              final isSelected =
                                  selectedIndices.contains(originalIndex);

                              return CheckboxListTile(
                                value: isSelected,
                                dense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                                title: Text(contact.name,
                                    style: const TextStyle(fontWeight: FontWeight.w600)),
                                subtitle: Text(contact.phone, style: const TextStyle(fontSize: 11)),
                                activeColor: const Color(0xFF128C7E),
                                onChanged: (val) {
                                  setModalState(() {
                                    if (val == true) {
                                      selectedIndices.add(originalIndex);
                                    } else {
                                      selectedIndices.remove(originalIndex);
                                    }
                                  });
                                },
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF25D366),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () {
                      final imported = <String>[];
                      for (var idx in selectedIndices) {
                        final c = contacts[idx];
                        imported.add('${c.phone}, ${c.name}');
                      }

                      if (imported.isNotEmpty) {
                        setState(() {
                          final current = _numbersController.text.trim();
                          final existingNorm = current
                              .split('\n')
                              .map((l) => l.split(',')[0].trim().replaceAll(RegExp(r'\D'), ''))
                              .where((s) => s.isNotEmpty)
                              .map((s) => s.length > 10 ? s.substring(s.length - 10) : s)
                              .toSet();

                          final uniqueNew = <String>[];
                          for (var item in imported) {
                            final numStr = item.split(',')[0].trim().replaceAll(RegExp(r'\D'), '');
                            final norm = numStr.length > 10 ? numStr.substring(numStr.length - 10) : numStr;
                            if (!existingNorm.contains(norm)) {
                              existingNorm.add(norm);
                              uniqueNew.add(item);
                            }
                          }

                          if (uniqueNew.isNotEmpty) {
                            if (current.isEmpty) {
                              _numbersController.text = uniqueNew.join('\n');
                            } else {
                              _numbersController.text = '$current\n${uniqueNew.join('\n')}';
                            }
                          }
                        });

                        // Persist imported contacts to local server
                        final toSync = imported.map((str) {
                          final parts = str.split(', ');
                          return {
                            'phone': parts[0].trim(),
                            'name': parts.length > 1 ? parts[1].trim() : parts[0].trim(),
                          };
                        }).toList();
                        _gatewayService.importContacts(toSync);

                        _showSnackbar(
                            '✅ ${imported.length} contacts outreach list me add ho gaye!');
                      }
                      Navigator.pop(ctx);
                    },
                    child: Text(
                      'Import Selected (${selectedIndices.length}) Contacts',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showPasteOrPathDialog() {
    final textController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Paste Contacts List or vCard'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Paste numbers (e.g. "9876543210, John Doe" or .vcf file content):',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: textController,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    hintText:
                        '9876543210, John Doe\n9812345678, Sarah Smith\n9823456789, Alex Turner\n\nOr paste your contacts.vcf / CSV raw text here',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF128C7E),
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              final raw = textController.text.trim();
              if (raw.isNotEmpty) {
                final contacts = _parseContactsFromText(raw);
                Navigator.pop(ctx);
                if (contacts.isNotEmpty) {
                  _showParsedContactsSelectionDialog(contacts,
                      title: 'Parsed Contacts');
                } else {
                  _showSnackbar('No valid 10-digit phone numbers found.');
                }
              } else {
                Navigator.pop(ctx);
              }
            },
            child: const Text('Parse & Select'),
          ),
        ],
      ),
    );
  }

  void _showPhoneExportGuideDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.phone_android, color: Color(0xFF128C7E)),
            SizedBox(width: 8),
            Text('Phone Contacts Export Guide'),
          ],
        ),
        content: const SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '2 Simple Ways to Import Phone Contacts to PC:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                SizedBox(height: 12),
                Text(
                  'Method 1: From Phone Contacts App (10 Seconds)\n'
                  '1. Open Contacts app on your phone > Settings (Fix & Manage).\n'
                  '2. Tap "Export to file" -> saves contacts.vcf.\n'
                  '3. Send to PC via WhatsApp or Email, then select here using "Phone Contacts File (.vcf)"!',
                  style: TextStyle(fontSize: 12, height: 1.4),
                ),
                SizedBox(height: 12),
                Text(
                  'Method 2: Via Google Contacts (Web Browser)\n'
                  '1. Open contacts.google.com on your PC browser.\n'
                  '2. Click "Export" -> choose vCard (for iOS/Contacts) or CSV.\n'
                  '3. Select the downloaded file here!',
                  style: TextStyle(fontSize: 12, height: 1.4),
                ),
              ],
            ),
          ),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF128C7E),
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _pickFileAndParseContacts();
            },
            child: const Text('Select Contacts File'),
          ),
        ],
      ),
    );
  }

  void _showPermissionDeniedDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Contacts Permission Required'),
        content: const Text(
          'Please enable Contacts permission in your phone App Settings so WhatsApp Bot can select your client numbers.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }


  // 1b. FETCH & SELECT WHATSAPP CHATS & CONTACTS
  bool _isLoadingChats = false;

  Future<void> _fetchAndSelectWhatsAppChats() async {
    final canFetch = _status?.connected == true || _status?.isLoggedIn == true;
    if (!canFetch) {
      _showSnackbar('Please connect your WhatsApp first to load your chats.');
      return;
    }

    setState(() {
      _isLoadingChats = true;
    });

    _gatewayService.baseUrl = _serverUrlController.text.trim();
    final contacts = await _gatewayService.fetchContacts();

    if (!mounted) return;

    setState(() {
      _isLoadingChats = false;
    });

    if (contacts.isEmpty) {
      _showSnackbar(
        'No active 1-on-1 direct WhatsApp chats found. Please import phone contacts (.vcf) or paste numbers.',
      );
      return;
    }

    final leads = contacts
        .map((c) => CustomContactLead(name: c.name, phone: c.phone))
        .toList();

    _showParsedContactsSelectionDialog(
      leads,
      title: 'All WhatsApp Contacts & Members',
    );
  }

  // 2. FETCH & SELECT WHATSAPP GROUPS
  Future<void> _fetchAndSelectGroups() async {
    final canFetch = _status?.connected == true || _status?.isLoggedIn == true;
    if (!canFetch) {
      _showSnackbar('Please connect your WhatsApp first to load your groups.');
      return;
    }

    setState(() {
      _isLoadingGroups = true;
    });

    _gatewayService.baseUrl = _serverUrlController.text.trim();
    final groups = await _gatewayService.fetchGroups();

    if (!mounted) return;

    setState(() {
      _isLoadingGroups = false;
      _availableGroups = groups;
    });

    if (groups.isEmpty) {
      _showSnackbar(
        'No participating groups found for this WhatsApp account.',
      );
      return;
    }

    _showGroupSelectionDialog(groups);
  }

  void _showGroupSelectionDialog(List<WhatsAppGroupItem> groups) {
    final selectedIndices = <int>{};
    final searchController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 640),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final query = searchController.text.toLowerCase();
          final filtered = groups.asMap().entries.where((entry) {
            final g = entry.value;
            return g.name.toLowerCase().contains(query);
          }).toList();

          return SizedBox(
            height: MediaQuery.of(context).size.height * 0.85,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.groups, color: Color(0xFF128C7E), size: 24),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Select WhatsApp Groups',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.teal.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.teal.shade200),
                        ),
                        child: Text(
                          '${selectedIndices.length} Selected',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.teal.shade800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: 'Close',
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: searchController,
                    decoration: const InputDecoration(
                      labelText: 'Search WhatsApp groups...',
                      prefixIcon: Icon(Icons.search),
                      isDense: true,
                    ),
                    onChanged: (_) => setModalState(() {}),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: filtered.isEmpty
                        ? const Center(
                            child: Text(
                              'No groups found',
                              style: TextStyle(color: Colors.grey),
                            ),
                          )
                        : ListView.separated(
                            itemCount: filtered.length,
                            separatorBuilder: (_, _) => const Divider(height: 1),
                            itemBuilder: (context, i) {
                              final originalIndex = filtered[i].key;
                              final group = filtered[i].value;
                              final isSelected =
                                  selectedIndices.contains(originalIndex);

                              return CheckboxListTile(
                                value: isSelected,
                                dense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                                title: Text(group.name,
                                    style: const TextStyle(fontWeight: FontWeight.w600)),
                                subtitle: Text(
                                  '${group.participantsCount} members • ID: ${group.id}',
                                  style: const TextStyle(fontSize: 11),
                                ),
                                activeColor: const Color(0xFF128C7E),
                                onChanged: (val) {
                                  setModalState(() {
                                    if (val == true) {
                                      selectedIndices.add(originalIndex);
                                    } else {
                                      selectedIndices.remove(originalIndex);
                                    }
                                  });
                                },
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF25D366),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () {
                      final imported = <String>[];
                      for (var idx in selectedIndices) {
                        final g = groups[idx];
                        imported.add('${g.id}, ${g.name}');
                      }

                      if (imported.isNotEmpty) {
                        setState(() {
                          final current = _numbersController.text.trim();
                          if (current.isEmpty) {
                            _numbersController.text = imported.join('\n');
                          } else {
                            _numbersController.text =
                                '$current\n${imported.join('\n')}';
                          }
                        });
                        _showSnackbar(
                          '✅ ${imported.length} WhatsApp Groups added to broadcast list!',
                        );
                      }
                      Navigator.pop(ctx);
                    },
                    child: Text(
                      'Add Selected (${selectedIndices.length}) Groups to Broadcast',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  List<Map<String, String>> _parseRecipients() {
    final raw = _numbersController.text;
    final defaultCode = _countryCodeController.text.trim().replaceAll('+', '');
    final lines = raw.split(RegExp(r'[\r\n]'));
    final List<Map<String, String>> list = [];
    final seen = <String>{};

    for (var line in lines) {
      line = line.trim();
      if (line.isEmpty) continue;

      String name = 'Client';
      String numberPart = line;

      if (line.contains(',')) {
        final parts = line.split(',');
        numberPart = parts[0].trim();
        if (parts.length > 1 && parts[1].trim().isNotEmpty) {
          name = parts[1].trim();
        }
      } else if (line.contains(':')) {
        final parts = line.split(':');
        name = parts[0].trim();
        if (parts.length > 1) {
          numberPart = parts[1].trim();
        }
      }

      // Check if it's a group ID
      if (numberPart.contains('@g.us') ||
          numberPart.contains('-') ||
          (numberPart.startsWith('120363') && numberPart.length >= 16)) {
        if (!seen.contains(numberPart)) {
          seen.add(numberPart);
          list.add({'phone': numberPart, 'name': name, 'type': 'group'});
        }
        continue;
      }

      var clean = numberPart.replaceAll(RegExp(r'[^0-9]'), '');
      if (clean.length == 10 && defaultCode.isNotEmpty) {
        clean = '$defaultCode$clean';
      }

      if (clean.isNotEmpty) {
        final norm =
            clean.length > 10 ? clean.substring(clean.length - 10) : clean;
        if (!seen.contains(norm)) {
          seen.add(norm);
          list.add({'phone': clean, 'name': name, 'type': 'contact'});
        }
      }
    }
    return list;
  }

  int get _duplicateLinesCount {
    final raw = _numbersController.text;
    if (raw.trim().isEmpty) return 0;
    final totalLines = raw
        .split(RegExp(r'[\r\n]'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .length;
    final uniqueCount = _parseRecipients().length;
    final diff = totalLines - uniqueCount;
    return diff > 0 ? diff : 0;
  }

  void _removeDuplicatesFromController() {
    final recipients = _parseRecipients();
    final originalRaw = _numbersController.text.trim();
    final originalCount = originalRaw
        .split(RegExp(r'[\r\n]'))
        .where((l) => l.trim().isNotEmpty)
        .length;

    final newLines =
        recipients.map((r) => '${r['phone']}, ${r['name']}').toList();
    final removed = originalCount - newLines.length;

    setState(() {
      _numbersController.text = newLines.join('\n');
    });

    if (removed > 0) {
      _showSnackbar(
        '✅ Cleaned $removed duplicate numbers! Now total ${newLines.length} unique targets.',
      );
    } else {
      _showSnackbar('No duplicate numbers found (all targets are unique).');
    }
  }

  Future<void> _showTermsAndConditionsDialog() async {
    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF128C7E).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.verified_user_rounded,
                  color: Color(0xFF128C7E),
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Terms & Anti-Spam Policy',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Responsible WhatsApp Outreach Agreement',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.amber.shade300),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            size: 20, color: Colors.amber.shade900),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Please read carefully. By enabling message booster and broadcasting, you agree to comply with WhatsApp Terms and local anti-spam regulations.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.amber.shade900,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _buildTermPoint(
                    icon: Icons.check_circle_outline,
                    title: '1. Opt-In & Consent Guarantee',
                    description:
                        'You confirm that all phone numbers and contacts receiving messages have explicitly agreed or given prior consent to receive communications from you. Unsolicited cold-spamming or harassing strangers is strictly forbidden.',
                  ),
                  const SizedBox(height: 12),
                  _buildTermPoint(
                    icon: Icons.security_rounded,
                    title: '2. WhatsApp Anti-Spam Compliance & Pacing',
                    description:
                        'WhatsApp uses automated fraud detection. You agree to use appropriate delay intervals (2s to 5s recommended) and avoid excessive blasting that violates WhatsApp Terms of Service.',
                  ),
                  const SizedBox(height: 12),
                  _buildTermPoint(
                    icon: Icons.shield_outlined,
                    title: '3. Disclaimer of Liability',
                    description:
                        'This software is an outreach automation utility provided "as-is". The developer/author is NOT responsible or liable for any WhatsApp account temporary bans, permanent suspensions, or legal complaints arising from misuse by the user.',
                  ),
                  const SizedBox(height: 12),
                  _buildTermPoint(
                    icon: Icons.vpn_key_outlined,
                    title: '4. License & Fair Usage',
                    description:
                        'Pro License keys are non-transferable per user/device. Trial is limited to 25 messages for product evaluation.',
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF128C7E),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () async {
                setState(() {
                  _termsAccepted = true;
                });
                await LicenseService.setTermsAccepted(true);
                if (ctx.mounted) Navigator.pop(ctx);
                _showSnackbar('✅ Terms & Conditions accepted! Outreach booster enabled.');
              },
              icon: const Icon(Icons.check, size: 18),
              label: const Text('I Agree & Accept Terms'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTermPoint({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: const Color(0xFF128C7E)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade700,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTermsAndConditionsCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: _termsAccepted
              ? const Color(0xFF25D366).withValues(alpha: 0.5)
              : Colors.amber.shade400,
          width: 1.5,
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: _termsAccepted
              ? const Color(0xFFF0FDF4)
              : const Color(0xFFFFFBEB),
        ),
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _termsAccepted
                      ? Icons.verified_user_rounded
                      : Icons.warning_amber_rounded,
                  color: _termsAccepted
                      ? const Color(0xFF16A34A)
                      : Colors.amber.shade900,
                  size: 22,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _termsAccepted
                        ? 'Terms & Anti-Spam Compliance: ACCEPTED'
                        : 'Terms & Conditions Acceptance Required',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: _termsAccepted
                          ? const Color(0xFF15803D)
                          : Colors.amber.shade900,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _showTermsAndConditionsDialog,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: const Text(
                    'Read Terms',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            InkWell(
              onTap: () async {
                final newVal = !_termsAccepted;
                setState(() {
                  _termsAccepted = newVal;
                });
                await LicenseService.setTermsAccepted(newVal);
              },
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: Checkbox(
                        value: _termsAccepted,
                        activeColor: const Color(0xFF16A34A),
                        onChanged: (val) async {
                          final newVal = val ?? false;
                          setState(() {
                            _termsAccepted = newVal;
                          });
                          await LicenseService.setTermsAccepted(newVal);
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'I accept the Terms and Conditions & Anti-Spam Policy. I confirm all recipients have opted in, and I will not send unsolicited spam.',
                        style: TextStyle(
                          fontSize: 12,
                          color: _termsAccepted
                              ? Colors.grey.shade900
                              : Colors.amber.shade900,
                          fontWeight: _termsAccepted
                              ? FontWeight.w500
                              : FontWeight.w600,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUpgradeNoticeBanner() {
    final isLicensed = LicenseService.isLicensed;
    final remaining = LicenseService.remainingTrial;
    final isExpired = LicenseService.isExpired;

    if (isLicensed) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF064E3B), Color(0xFF065F46), Color(0xFF047857)],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF34D399), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                color: Color(0xFFFFD700),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.workspace_premium,
                color: Colors.black87,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          LicenseService.licenseType,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFD700),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'ACTIVE PRO',
                          style: TextStyle(
                            color: Colors.black87,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Validity: ${LicenseService.expiryLabel} • 100x Multi-round repeats unlocked',
                    style: const TextStyle(
                      color: Color(0xFFD1FAE5),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: Colors.white.withValues(alpha: 0.18),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                visualDensity: VisualDensity.compact,
              ),
              onPressed: () => _showPaymentAndLicenseDialog(),
              child: const Text('Manage',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF0F172A),
            Color(0xFF1E293B),
            Color(0xFF0F172A),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isExpired ? Colors.red.shade400 : const Color(0xFFF59E0B),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isExpired
                        ? [Colors.red.shade600, Colors.red.shade800]
                        : [const Color(0xFFFFD700), const Color(0xFFF59E0B)],
                  ),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isExpired ? Icons.timer_off_rounded : Icons.workspace_premium,
                  color: isExpired ? Colors.white : Colors.black87,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            isExpired ? 'License Expired' : 'Free Trial Mode',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: isExpired
                                ? Colors.red.shade700
                                : (remaining > 0
                                    ? const Color(0xFF10B981)
                                    : Colors.red.shade700),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            isExpired ? 'RENEW NOW' : '$remaining / 25 Free Left',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      isExpired
                          ? 'Your pass expired. Renew via UPI to restore unlimited booster blast.'
                          : '⚡ 1-Day Trial available at just ₹49 • Or get Monthly ₹299 / Lifetime ₹999!',
                      style: TextStyle(
                        color: Colors.grey.shade300,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Action Buttons Bar
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFD700),
                    foregroundColor: Colors.black87,
                    elevation: 3,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () => _showPaymentAndLicenseDialog(),
                  icon: const Icon(Icons.flash_on_rounded, size: 16),
                  label: const Text(
                    'Upgrade Pro (From ₹49)',
                    style:
                        TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white38),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () => _showPaymentAndLicenseDialog(),
                icon: const Icon(Icons.vpn_key_outlined, size: 16),
                label: const Text(
                  'Enter Key',
                  style:
                      TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showPassExpiredDialog(AccountLicenseStatus status) async {
    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Colors.red.shade400, width: 1.5),
        ),
        backgroundColor: const Color(0xFF0F172A),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        actionsPadding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.shade700,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.timer_off_rounded, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Booster Pass Expired',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.phone_android, size: 16, color: Color(0xFF25D366)),
                      const SizedBox(width: 6),
                      Text(
                        'Account: +${status.phone}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.verified, size: 16, color: Color(0xFFFFD700)),
                      const SizedBox(width: 6),
                      Text(
                        'Plan: ${status.licenseType}',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.schedule, size: 16, color: Colors.red.shade300),
                      const SizedBox(width: 6),
                      Text(
                        'Expired on: ${status.formattedExpiryDateTime}',
                        style: TextStyle(
                          color: Colors.red.shade200,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Your ${status.licenseType} pass for WhatsApp account (+${status.phone}) expired on ${status.formattedExpiryDateTime}.\n\nWould you like to renew your booster pass to restore unlimited broadcasts, multi-round repeats, and full outreach features?',
              style: const TextStyle(
                color: Color(0xFFE2E8F0),
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Colors.grey.shade400,
            ),
            onPressed: () async {
              await LicenseService.markExpiredPopupShown(status.phone);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Not Now (Close)'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFD700),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              await LicenseService.markExpiredPopupShown(status.phone);
              if (ctx.mounted) Navigator.pop(ctx);
              _showPaymentAndLicenseDialog(reason: 'renewal');
            },
            icon: const Icon(Icons.flash_on_rounded, size: 16),
            label: const Text(
              '⚡ Renew Pass (UPI / Key)',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showPaymentAndLicenseDialog({String? reason, String? prefillKey}) async {
    final keyController = TextEditingController(text: prefillKey ?? '');
    String? errorText;
    String selectedPlanId = 'monthly_pro';
    bool copiedUpi = false;
    int currentStep = (prefillKey != null && prefillKey.isNotEmpty) ? 1 : 0;

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final isLicensed = LicenseService.isLicensed;
            final isExpired = LicenseService.isExpired;
            final selectedTier = LicenseService.tiers.firstWhere(
              (t) => t.id == selectedPlanId,
              orElse: () => LicenseService.tiers[1],
            );

            // ==========================================
            // STEP 1 WIDGET: PLAN SELECTION
            // ==========================================
            Widget buildStep1Plans() {
              return Column(
                key: const ValueKey<int>(0),
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // TOP HEADER BANNER
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF075E54), Color(0xFF0F172A), Color(0xFF064E3B)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFF128C7E).withValues(alpha: 0.6),
                        width: 1.2,
                      ),
                    ),
                    child: Row(
                      children: [
                        // Gold Medal
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(
                              colors: [Color(0xFFFFDF00), Color(0xFFF59E0B), Color(0xFFB45309)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFF59E0B).withValues(alpha: 0.4),
                                blurRadius: 10,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: const Center(
                            child: Icon(Icons.workspace_premium, color: Color(0xFF3B1E00), size: 22),
                          ),
                        ),
                        const SizedBox(width: 10),

                        // Plan Title & Status
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isLicensed
                                    ? '👑 ${LicenseService.licenseType} Active'
                                    : (isExpired
                                        ? '⏰ Booster Pass Expired'
                                        : '⚡ WhatsApp Outreach Booster Passes'),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  letterSpacing: 0.2,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 1),
                              Text(
                                isLicensed
                                    ? 'Status: ${LicenseService.expiryLabel}'
                                    : (isExpired
                                        ? 'Status: Expired • Choose any pass below to renew'
                                        : 'Free Trial: ${LicenseService.freeSentCount}/${LicenseService.freeTrialLimit} sent • Choose a pass below'),
                                style: const TextStyle(
                                  color: Color(0xFFD1FAE5),
                                  fontSize: 10.5,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Sparkle
                        const Icon(Icons.auto_awesome, color: Color(0xFFFFD700), size: 20),
                        const SizedBox(width: 10),

                        // Close Button 'X'
                        InkWell(
                          onTap: () => Navigator.pop(ctx),
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E293B),
                              shape: BoxShape.circle,
                              border: Border.all(color: const Color(0xFF334155)),
                            ),
                            child: const Icon(Icons.close, size: 14, color: Color(0xFF94A3B8)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Optional Alert Banner
                  if (reason == 'booster') ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF431407),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFEA580C)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.local_fire_department, color: Color(0xFFFB923C), size: 16),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Multi-Round Booster Repeats (5x-100x) require an active pass. Test it for ₹49 or choose Pro below.',
                              style: TextStyle(fontSize: 10.5, color: Color(0xFFFFEDD5), fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else if (reason == 'limit' || isExpired) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF450A0A),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFDC2626)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: Color(0xFFF87171), size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              isExpired
                                  ? '⏰ Previous pass has expired. Choose any plan below to renew.'
                                  : '⚠️ Free trial exhausted (${LicenseService.freeSentCount}/${LicenseService.freeTrialLimit} sent)! Choose a plan below.',
                              style: const TextStyle(fontSize: 10.5, color: Color(0xFFFEE2E2), fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else if (reason == 'ad_free') ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1B4B),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF6366F1)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.workspace_premium, color: Color(0xFFA5B4FC), size: 16),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '👑 Upgrade to any Pro pass to permanently remove all sponsored ads & unlock 100x message repeats!',
                              style: TextStyle(fontSize: 10.5, color: Color(0xFFE0E7FF), fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // SECTION 1 HEADER
                  Row(
                    children: [
                      Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: const Color(0xFF128C7E),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Center(
                          child: Text(
                            '1',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Choose Your Booster Pass',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const Spacer(),
                      const Text(
                        'Tap any plan to select',
                        style: TextStyle(fontSize: 10, color: Color(0xFF25D366), fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // THE 4 PLAN CARDS (100% Clickable & Reactive)
                  Column(
                    children: LicenseService.tiers.map((tier) {
                      final isSelected = selectedPlanId == tier.id;

                      LinearGradient cardGradient;
                      Color borderColor;
                      List<BoxShadow> shadows;
                      Widget iconWidget;
                      String badgeText;
                      Color badgeBg;
                      Color badgeBorder;
                      Color badgeTextColor;
                      String priceText = tier.price;
                      String periodText;
                      Color priceColor;
                      bool hasPopularRibbon = false;

                      if (tier.id == 'trial_1day') {
                        badgeText = 'TEST DRIVE ⚡';
                        periodText = '24h Access';
                        iconWidget = Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: const Color(0xFF064E3B),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFF059669).withValues(alpha: 0.5)),
                          ),
                          child: const Icon(Icons.bolt_rounded, color: Color(0xFF34D399), size: 18),
                        );
                        badgeBg = const Color(0xFF064E3B);
                        badgeBorder = const Color(0xFF059669);
                        badgeTextColor = const Color(0xFF34D399);
                        priceColor = const Color(0xFF34D399);

                        if (isSelected) {
                          cardGradient = const LinearGradient(
                            colors: [Color(0xFF064E3B), Color(0xFF047857), Color(0xFF059669)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          );
                          borderColor = const Color(0xFF34D399);
                          shadows = [
                            BoxShadow(
                              color: const Color(0xFF10B981).withValues(alpha: 0.4),
                              blurRadius: 10,
                            ),
                          ];
                        } else {
                          cardGradient = const LinearGradient(
                            colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
                          );
                          borderColor = const Color(0xFF334155);
                          shadows = [];
                        }
                      } else if (tier.id == 'monthly_pro') {
                        badgeText = 'MOST POPULAR 🔥';
                        periodText = '30 Days Validity';
                        hasPopularRibbon = true;
                        iconWidget = Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: const Color(0xFF075E54),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFF128C7E).withValues(alpha: 0.6)),
                          ),
                          child: const Icon(Icons.workspace_premium, color: Color(0xFFFFD700), size: 18),
                        );
                        badgeBg = const Color(0xFF075E54);
                        badgeBorder = const Color(0xFF128C7E);
                        badgeTextColor = const Color(0xFF6EE7B7);
                        priceColor = Colors.white;

                        if (isSelected) {
                          cardGradient = const LinearGradient(
                            colors: [Color(0xFF075E54), Color(0xFF128C7E), Color(0xFF0B665A)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          );
                          borderColor = const Color(0xFF25D366);
                          shadows = [
                            BoxShadow(
                              color: const Color(0xFF25D366).withValues(alpha: 0.4),
                              blurRadius: 12,
                            ),
                          ];
                        } else {
                          cardGradient = const LinearGradient(
                            colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
                          );
                          borderColor = const Color(0xFF334155);
                          shadows = [];
                        }
                      } else if (tier.id == 'lifetime_vip') {
                        badgeText = 'BEST VALUE ⭐';
                        periodText = 'One-Time (Forever)';
                        iconWidget = Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: const Color(0xFF451A03),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFD97706).withValues(alpha: 0.5)),
                          ),
                          child: const Icon(Icons.all_inclusive_rounded, color: Color(0xFFFBBF24), size: 18),
                        );
                        badgeBg = const Color(0xFF451A03);
                        badgeBorder = const Color(0xFFD97706);
                        badgeTextColor = const Color(0xFFFCD34D);
                        priceColor = const Color(0xFFFBBF24);

                        if (isSelected) {
                          cardGradient = const LinearGradient(
                            colors: [Color(0xFF78350F), Color(0xFFB45309), Color(0xFFD97706)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          );
                          borderColor = const Color(0xFFFCD34D);
                          shadows = [
                            BoxShadow(
                              color: const Color(0xFFD97706).withValues(alpha: 0.4),
                              blurRadius: 10,
                            ),
                          ];
                        } else {
                          cardGradient = const LinearGradient(
                            colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
                          );
                          borderColor = const Color(0xFF334155);
                          shadows = [];
                        }
                      } else {
                        // Agency Master
                        badgeText = 'AGENCY 👑';
                        periodText = 'Lifetime Commercial';
                        iconWidget = Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: const Color(0xFF3B0764),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFF7C3AED).withValues(alpha: 0.5)),
                          ),
                          child: const Icon(Icons.groups_rounded, color: Color(0xFFC084FC), size: 18),
                        );
                        badgeBg = const Color(0xFF3B0764);
                        badgeBorder = const Color(0xFF9333EA);
                        badgeTextColor = const Color(0xFFE9D5FF);
                        priceColor = const Color(0xFFC084FC);

                        if (isSelected) {
                          cardGradient = const LinearGradient(
                            colors: [Color(0xFF4C1D95), Color(0xFF6D28D9), Color(0xFF7C3AED)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          );
                          borderColor = const Color(0xFFC084FC);
                          shadows = [
                            BoxShadow(
                              color: const Color(0xFF7C3AED).withValues(alpha: 0.4),
                              blurRadius: 10,
                            ),
                          ];
                        } else {
                          cardGradient = const LinearGradient(
                            colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
                          );
                          borderColor = const Color(0xFF334155);
                          shadows = [];
                        }
                      }

                      return Container(
                        margin: const EdgeInsets.only(bottom: 7),
                        child: Material(
                          color: Colors.transparent,
                          child: Ink(
                            decoration: BoxDecoration(
                              gradient: cardGradient,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: borderColor,
                                width: isSelected ? 2.0 : 1.0,
                              ),
                              boxShadow: shadows,
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              hoverColor: Colors.white.withValues(alpha: 0.05),
                              splashColor: const Color(0xFF25D366).withValues(alpha: 0.2),
                              onTap: () {
                                setDialogState(() {
                                  selectedPlanId = tier.id;
                                });
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    Row(
                                      children: [
                                        // Radio indicator
                                        Container(
                                          width: 20,
                                          height: 20,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: isSelected ? const Color(0xFF25D366) : const Color(0xFF1E293B),
                                            border: Border.all(
                                              color: isSelected ? const Color(0xFF34D399) : const Color(0xFF64748B),
                                              width: 1.8,
                                            ),
                                          ),
                                          child: isSelected
                                              ? const Center(
                                                  child: Icon(Icons.check, size: 13, color: Colors.white),
                                                )
                                              : null,
                                        ),
                                        const SizedBox(width: 8),

                                        // Tier Icon Box
                                        iconWidget,
                                        const SizedBox(width: 8),

                                        // Title + Badge + Subtitle
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Flexible(
                                                    child: Text(
                                                      tier.name,
                                                      style: const TextStyle(
                                                        fontWeight: FontWeight.bold,
                                                        fontSize: 12.5,
                                                        color: Colors.white,
                                                      ),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                                    decoration: BoxDecoration(
                                                      color: badgeBg,
                                                      borderRadius: BorderRadius.circular(4),
                                                      border: Border.all(color: badgeBorder, width: 0.8),
                                                    ),
                                                    child: Text(
                                                      badgeText,
                                                      style: TextStyle(
                                                        fontSize: 8,
                                                        fontWeight: FontWeight.w900,
                                                        color: badgeTextColor,
                                                        letterSpacing: 0.2,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 1),
                                              Text(
                                                tier.description,
                                                style: const TextStyle(
                                                  fontSize: 10,
                                                  color: Color(0xFF94A3B8),
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),

                                        // Price + Pay/Select Action Chip
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                              priceText,
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w900,
                                                color: priceColor,
                                                letterSpacing: -0.5,
                                              ),
                                            ),
                                            Text(
                                              periodText,
                                              style: TextStyle(
                                                fontSize: 9,
                                                color: isSelected ? const Color(0xFFCBD5E1) : const Color(0xFF64748B),
                                              ),
                                            ),
                                            const SizedBox(height: 3),
                                            // Action indicator button / chip
                                            InkWell(
                                              onTap: () {
                                                setDialogState(() {
                                                  selectedPlanId = tier.id;
                                                  currentStep = 1;
                                                });
                                              },
                                              borderRadius: BorderRadius.circular(6),
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: isSelected
                                                      ? const Color(0xFF059669)
                                                      : const Color(0xFF1E293B),
                                                  borderRadius: BorderRadius.circular(6),
                                                  border: Border.all(
                                                    color: isSelected
                                                        ? const Color(0xFF34D399)
                                                        : const Color(0xFF475569),
                                                    width: 0.8,
                                                  ),
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Text(
                                                      isSelected ? 'Pay Now' : 'Select',
                                                      style: TextStyle(
                                                        fontSize: 9.5,
                                                        fontWeight: FontWeight.bold,
                                                        color: isSelected ? Colors.white : const Color(0xFFCBD5E1),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 3),
                                                    Icon(
                                                      isSelected ? Icons.arrow_forward_rounded : Icons.check_circle_outline,
                                                      size: 10,
                                                      color: isSelected ? Colors.white : const Color(0xFF94A3B8),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),

                                    // Popular ribbon
                                    if (hasPopularRibbon && isSelected)
                                      Positioned(
                                        top: -6,
                                        right: -4,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFFFD700),
                                            borderRadius: BorderRadius.circular(4),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withValues(alpha: 0.3),
                                                blurRadius: 4,
                                              ),
                                            ],
                                          ),
                                          child: const Text(
                                            'POPULAR',
                                            style: TextStyle(
                                              fontSize: 7.5,
                                              fontWeight: FontWeight.w900,
                                              color: Colors.black87,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),

                  // GLOWING PROCEED TO PAY BUTTON
                  InkWell(
                    onTap: () {
                      setDialogState(() {
                        currentStep = 1;
                      });
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF075E54), Color(0xFF128C7E), Color(0xFF25D366)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF34D399), width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF25D366).withValues(alpha: 0.4),
                            blurRadius: 14,
                            spreadRadius: 1,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.qr_code_2_rounded, color: Colors.white, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Proceed to Pay ${selectedTier.price} (${selectedTier.name})',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13.5,
                              letterSpacing: 0.3,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 18),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // SECONDARY ACTION: ALREADY HAVE KEY?
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton.icon(
                        onPressed: () {
                          setDialogState(() {
                            currentStep = 1;
                          });
                        },
                        icon: const Icon(Icons.vpn_key_rounded, size: 13, color: Color(0xFF94A3B8)),
                        label: const Text(
                          'Already have a License Key? Click to Activate',
                          style: TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 11,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),

                  // Testing & Verification Bar
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B).withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            'Simulator (+${LicenseService.currentPhone.isNotEmpty ? LicenseService.currentPhone : "Guest"}):',
                            style: const TextStyle(fontSize: 10, color: Colors.white60),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            InkWell(
                              onTap: () async {
                                final st = await LicenseService.simulateExpireAccount(_status?.user);
                                setDialogState(() {});
                                setState(() {});
                                if (ctx.mounted) Navigator.pop(ctx);
                                _showPassExpiredDialog(st);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade900.withValues(alpha: 0.6),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Colors.red.shade400, width: 0.8),
                                ),
                                child: const Text(
                                  '🧪 Test Expired Popup',
                                  style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            InkWell(
                              onTap: () async {
                                await LicenseService.simulateActivate24hPass(_status?.user);
                                setDialogState(() {});
                                setState(() {});
                                _showSnackbar('🎉 24-Hour Active Pass restored for +${LicenseService.currentPhone}!');
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade900.withValues(alpha: 0.6),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Colors.green.shade400, width: 0.8),
                                ),
                                child: const Text(
                                  '⚡ 24h Pass (₹49)',
                                  style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }

            // ==========================================
            // STEP 2 WIDGET: SCAN QR & PAY
            // ==========================================
            Widget buildStep2Payment() {
              return Column(
                key: const ValueKey<int>(1),
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // STEP 2 HEADER BAR (Back button + selected plan info + close)
                  Row(
                    children: [
                      InkWell(
                        onTap: () {
                          setDialogState(() {
                            currentStep = 0;
                          });
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFF334155)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.arrow_back_rounded, size: 14, color: Color(0xFF34D399)),
                              SizedBox(width: 4),
                              Text(
                                'Change Plan',
                                style: TextStyle(
                                  color: Color(0xFF34D399),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Plan pill
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF064E3B),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFF059669)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.verified, size: 13, color: Color(0xFF34D399)),
                              const SizedBox(width: 5),
                              Flexible(
                                child: Text(
                                  'Amount: ${selectedTier.price} (${selectedTier.name})',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11.5,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Close button
                      InkWell(
                        onTap: () => Navigator.pop(ctx),
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E293B),
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFF334155)),
                          ),
                          child: const Icon(Icons.close, size: 14, color: Color(0xFF94A3B8)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // QR CODE & SCANNER BOX (Paytm UPI QR for Natish Kumar)
                  Center(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFF00BAF2), width: 1.8),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF00BAF2).withValues(alpha: 0.22),
                            blurRadius: 12,
                            spreadRadius: 1,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Top Header Badge
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE8F7FE),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: const Color(0xFFBAE6FD)),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.qr_code_scanner_rounded, color: Color(0xFF002970), size: 14),
                                    SizedBox(width: 5),
                                    Text(
                                      'Scan with Any UPI App (Paytm, GPay, PhonePe)',
                                      style: TextStyle(
                                        color: Color(0xFF002970),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 10.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),

                          // Interactive QR Image (Tap to Zoom)
                          InkWell(
                            onTap: () {
                              showDialog(
                                context: ctx,
                                builder: (c) => Dialog(
                                  backgroundColor: Colors.transparent,
                                  insetPadding: const EdgeInsets.all(16),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(18),
                                          color: Colors.white,
                                          boxShadow: const [
                                            BoxShadow(color: Colors.black26, blurRadius: 20, spreadRadius: 4),
                                          ],
                                        ),
                                        padding: const EdgeInsets.all(14),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(14),
                                          child: const PaymentQrImageWidget(
                                            fit: BoxFit.contain,
                                            width: 320,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.white,
                                          foregroundColor: Colors.black87,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                        ),
                                        onPressed: () => Navigator.pop(c),
                                        icon: const Icon(Icons.close, size: 16),
                                        label: const Text('Close QR', style: TextStyle(fontWeight: FontWeight.bold)),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.grey.shade200),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: const PaymentQrImageWidget(
                                  height: 190,
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 5),

                          // Hint
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.zoom_in_rounded, size: 13, color: Color(0xFF64748B)),
                              const SizedBox(width: 4),
                              Text(
                                'Pay ${selectedTier.price} to Natish Kumar • Tap to view full screen',
                                style: const TextStyle(
                                  color: Color(0xFF475569),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // UPI DETAILS BOX (Stylized UPI Logo + Copy UPI Button)
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF334155)),
                    ),
                    child: Row(
                      children: [
                        // Stylized UPI logo badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFF334155)),
                          ),
                          child: RichText(
                            text: const TextSpan(
                              text: 'UPI ',
                              style: TextStyle(
                                fontStyle: FontStyle.italic,
                                fontWeight: FontWeight.w900,
                                fontSize: 14,
                                color: Colors.white,
                                letterSpacing: 0.5,
                              ),
                              children: [
                                TextSpan(
                                  text: '▶',
                                  style: TextStyle(color: Color(0xFFFF9933), fontSize: 10),
                                ),
                                TextSpan(
                                  text: '▶',
                                  style: TextStyle(color: Color(0xFF138808), fontSize: 10),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),

                        // UPI ID + Name
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'UPI ID: 9610993628@ptaxis',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'monospace',
                                  color: Colors.white,
                                ),
                              ),
                              SizedBox(height: 1),
                              Text(
                                'Natish Kumar • All UPI Apps Supported',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  color: Color(0xFF94A3B8),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Copy UPI button
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: copiedUpi
                                ? const Color(0xFF10B981)
                                : const Color(0xFF128C7E),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                              side: BorderSide(
                                color: copiedUpi ? const Color(0xFF34D399) : const Color(0xFF25D366),
                              ),
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: () {
                            Clipboard.setData(const ClipboardData(text: '9610993628@ptaxis'));
                            setDialogState(() {
                              copiedUpi = true;
                            });
                            _showSnackbar('✅ UPI ID (9610993628@ptaxis) copied to clipboard!');
                            Future.delayed(const Duration(seconds: 3), () {
                              if (ctx.mounted) {
                                setDialogState(() {
                                  copiedUpi = false;
                                });
                              }
                            });
                          },
                          icon: Icon(copiedUpi ? Icons.check : Icons.copy_rounded, size: 13),
                          label: Text(
                            copiedUpi ? 'Copied!' : 'Copy UPI',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 7),

                  // SEND WHATSAPP SCREENSHOT BUTTON
                  InkWell(
                    onTap: () async {
                      final text = Uri.encodeComponent(
                        'Hello! I have completed the UPI payment for WhatsApp Outreach Booster ${selectedTier.name} (${selectedTier.price}). Please share and activate my private License Key.',
                      );
                      final uri = Uri.parse('https://wa.me/919610993628?text=$text');
                      try {
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(uri, mode: LaunchMode.externalApplication);
                        } else {
                          Clipboard.setData(const ClipboardData(text: '+919610993628'));
                          _showSnackbar('WhatsApp support +91 9610993628 copied to clipboard!');
                        }
                      } catch (_) {
                        Clipboard.setData(const ClipboardData(text: '+919610993628'));
                        _showSnackbar('WhatsApp support +91 9610993628 copied to clipboard!');
                      }
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF075E54), Color(0xFF128C7E), Color(0xFF054B3A)],
                        ),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: const Color(0xFF25D366),
                          width: 1.2,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 26,
                            height: 26,
                            decoration: const BoxDecoration(
                              color: Color(0xFF25D366),
                              shape: BoxShape.circle,
                            ),
                            child: const Center(
                              child: Icon(Icons.chat_bubble, color: Colors.white, size: 14),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Send Screenshot on WhatsApp (+91 9610993628)',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11.5,
                                  ),
                                ),
                                Text(
                                  'Send screenshot after payment for instant License Key activation.',
                                  style: TextStyle(
                                    color: Color(0xFFD1FAE5),
                                    fontSize: 9.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded, color: Color(0xFF6EE7B7), size: 20),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // SECTION 3: ENTER LICENSE KEY
                  Row(
                    children: [
                      Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: const Color(0xFF128C7E),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Center(
                          child: Text(
                            '3',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'Enter Your Private License Key',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),

                  // KEY INPUT ROW
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: errorText != null ? const Color(0xFFEF4444) : const Color(0xFF334155),
                              width: 1.1,
                            ),
                          ),
                          child: TextField(
                            controller: keyController,
                            textCapitalization: TextCapitalization.characters,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.bold,
                              fontSize: 12.5,
                              color: Colors.white,
                            ),
                            decoration: const InputDecoration(
                              prefixIcon: Icon(Icons.vpn_key_rounded, size: 16, color: Color(0xFF25D366)),
                              hintText: 'Enter 16-character License Key',
                              hintStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              fillColor: Colors.transparent,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () async {
                          final raw = keyController.text.trim();
                          if (raw.isEmpty) {
                            setDialogState(() {
                              errorText = 'Please enter your license key';
                            });
                            return;
                          }
                          final ok = await LicenseService.activateKey(raw, forPhone: _status?.user);
                          if (ok) {
                            setDialogState(() {
                              errorText = null;
                            });
                            setState(() {});
                            if (ctx.mounted) Navigator.pop(ctx);
                            _showSnackbar(
                              '🎉 Success! ${LicenseService.licenseType} activated for +${LicenseService.currentPhone}! Validity: ${LicenseService.expiryLabel}.',
                            );
                          } else {
                            setDialogState(() {
                              errorText = 'Invalid key! WhatsApp support: +91 9610993628';
                            });
                          }
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF075E54), Color(0xFF128C7E), Color(0xFF25D366)],
                            ),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFF25D366), width: 1),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF128C7E).withValues(alpha: 0.4),
                                blurRadius: 10,
                              ),
                            ],
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.bolt_rounded, size: 16, color: Colors.white),
                              SizedBox(width: 4),
                              Text(
                                'Activate',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: 5),
                    Text(
                      errorText!,
                      style: const TextStyle(color: Color(0xFFEF4444), fontSize: 10.5),
                    ),
                  ],
                ],
              );
            }

            return Dialog(
              backgroundColor: const Color(0xFF0F172A),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
                side: BorderSide(
                  color: const Color(0xFF128C7E).withValues(alpha: 0.7),
                  width: 1.5,
                ),
              ),
              insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: 560,
                  maxHeight: MediaQuery.of(ctx).size.height * 0.92,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF075E54).withValues(alpha: 0.35),
                      blurRadius: 26,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: SingleChildScrollView(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) {
                      final offsetAnimation = Tween<Offset>(
                        begin: currentStep == 1
                            ? const Offset(0.06, 0.0)
                            : const Offset(-0.06, 0.0),
                        end: Offset.zero,
                      ).animate(animation);

                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: offsetAnimation,
                          child: child,
                        ),
                      );
                    },
                    child: currentStep == 0
                        ? buildStep1Plans()
                        : buildStep2Payment(),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _sendBulkAuto() async {
    final recipients = _parseRecipients();
    final message = _messageController.text.trim();

    // 1. Mandatory Terms and Conditions Check
    if (!_termsAccepted) {
      _showSnackbar(
        '⚠️ Please accept the Terms & Conditions below before launching your broadcast!',
      );
      _showTermsAndConditionsDialog();
      return;
    }

    if (recipients.isEmpty) {
      _showSnackbar('Please enter or select at least 1 number or group.');
      return;
    }

    if (message.isEmpty) {
      _showSnackbar('Please enter a message pitch.');
      return;
    }

    if (_status == null || !_status!.connected) {
      _showSnackbar(
        'WhatsApp is not connected! Scan the QR code or enter Pairing Code first.',
      );
      return;
    }

    // 2. Licensing and Free Trial Enforcement
    if (!LicenseService.isLicensed) {
      if (_boosterRepeatCount > 1) {
        _showPaymentAndLicenseDialog(reason: 'booster');
        return;
      }
      final remaining = LicenseService.remainingTrial;
      if (remaining <= 0) {
        _showPaymentAndLicenseDialog(reason: 'limit');
        return;
      }
      if (recipients.length > remaining) {
        _showPaymentAndLicenseDialog(reason: 'limit');
        return;
      }
    }

    // 3. Sponsored Ad #1: Displayed on click before sending starts (Bypassed for Pro users)
    final proceed = await AdService.showPreSendAd(
      context,
      onUpgradePro: () => _showPaymentAndLicenseDialog(reason: 'ad_free'),
    );
    if (!proceed || !mounted) return;

    setState(() {
      _isSending = true;
      _isStopping = false;
      _sendResult = null;
    });

    _gatewayService.baseUrl = _serverUrlController.text.trim();
    final result = await _gatewayService.sendBulk(
      recipients: recipients,
      messageTemplate: message,
      delayMs: (_delaySeconds * 1000).toInt(),
      repeatCount: _boosterRepeatCount,
    );

    if (mounted) {
      setState(() {
        _isSending = false;
        _isStopping = false;
        _sendResult = result;
      });

      if (result.success && result.sentCount > 0) {
        await LicenseService.incrementSentCount(result.sentCount);
      }

      if (result.stopped) {
        _showSnackbar(
          '🛑 Broadcast Stopped by user! ${result.sentCount}/${result.total} messages sent.',
        );
      } else if (result.success) {
        _showSnackbar(
          _boosterRepeatCount > 1
              ? '🎉 Booster blast completed! ${result.sentCount}/${result.total} messages delivered.'
              : '🎉 Broadcast completed! ${result.sentCount}/${result.total} messages sent automatically.',
        );
      } else {
        _showSnackbar('Send error: ${result.error ?? "Failed to send"}');
      }

      // 4. Sponsored Ad #2: Displayed immediately after message sending completes (Bypassed for Pro users)
      if (mounted) {
        await AdService.showPostSendAd(
          context,
          onUpgradePro: () {
            if (mounted) _showPaymentAndLicenseDialog(reason: 'ad_free');
          },
        );
      }
    }
  }

  Future<void> _stopBroadcast() async {
    if (_isStopping || !_isSending) return;
    setState(() {
      _isStopping = true;
    });
    _showSnackbar('🛑 Stopping broadcast... Abort signal sent.');
    _gatewayService.baseUrl = _serverUrlController.text.trim();
    await _gatewayService.stopBroadcast();
  }

  void _showSnackbar(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final recipients = _parseRecipients();
    final isConnected = _status?.connected == true;
    final isLoggedIn = _status?.isLoggedIn == true ||
        (_status?.user != null && _status!.user!.isNotEmpty);

    final isLicensed = LicenseService.isLicensed;
    final remainingTrial = LicenseService.remainingTrial;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF075E54),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'WhatsApp Booster Pro',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 8),
                if (isLicensed)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.workspace_premium, size: 12, color: Colors.black87),
                        SizedBox(width: 2),
                        Text(
                          'PRO',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Trial: $remainingTrial/25',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
            const Text(
              'Smart Bulk Outreach, CRM & Message Booster',
              style: TextStyle(fontSize: 11, color: Color(0xFFD1E7DD)),
            ),
          ],
        ),
        actions: [
          if (isLicensed)
            TextButton.icon(
              style: TextButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              onPressed: () => _showPaymentAndLicenseDialog(),
              icon: const Icon(Icons.verified, size: 15),
              label: Text(
                '👑 ${LicenseService.expiryLabel}',
                style:
                    const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
              ),
            )
          else if (LicenseService.isExpired)
            TextButton.icon(
              style: TextButton.styleFrom(
                backgroundColor: Colors.red.shade700,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              onPressed: () => _showPaymentAndLicenseDialog(reason: 'renewal'),
              icon: const Icon(Icons.timer_off_rounded, size: 15),
              label: Text(
                '⏰ Expired (${LicenseService.formattedExpiryDateTime})',
                style:
                    const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
              ),
            )
          else
            TextButton.icon(
              style: TextButton.styleFrom(
                backgroundColor: const Color(0xFFFF9800),
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              onPressed: () => _showPaymentAndLicenseDialog(),
              icon: const Icon(Icons.flash_on, size: 16),
              label: const Text(
                'Get Pro (₹49+)',
                style:
                    TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: 'Refresh Status',
            onPressed: _isCheckingStatus ? null : () => _checkServerStatus(),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Pro Upgrade Banner (or VIP Active status)
            _buildUpgradeNoticeBanner(),
            const SizedBox(height: 16),

            // Connection & QR Code Card (Rendered 100% inside Flutter)
            _buildConnectionCard(isConnected, isLoggedIn),
            const SizedBox(height: 16),

            // Message Pitch Card
            _buildPitchCard(),
            const SizedBox(height: 16),

            // Numbers, Groups & Contacts Input Card
            _buildNumbersAndGroupsCard(recipients.length),
            const SizedBox(height: 16),

            // Terms & Conditions Post / Acceptance Card (MANDATORY BEFORE BOOSTING)
            _buildTermsAndConditionsCard(),
            const SizedBox(height: 16),

            // One-Click Send & Booster Card
            _buildActionCard(recipients.length, isConnected || isLoggedIn),
            const SizedBox(height: 16),

            // Delivery Report
            if (_sendResult != null) _buildDeliveryReportCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionCard(bool isConnected, bool isLoggedIn) {
    final qrDataUrl = _status?.qrDataUrl;
    Uint8List? qrBytes;
    if (qrDataUrl != null && qrDataUrl.contains(',')) {
      try {
        qrBytes = base64Decode(qrDataUrl.split(',').last);
      } catch (_) {
        qrBytes = null;
      }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isLoggedIn
                      ? (isConnected ? Icons.check_circle : Icons.sync)
                      : Icons.qr_code_2,
                  color: isLoggedIn
                      ? (isConnected ? Colors.green : Colors.amber.shade800)
                      : const Color(0xFF128C7E),
                  size: 28,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isLoggedIn
                            ? 'WhatsApp Connected (+${_status?.user ?? ""})'
                            : 'WhatsApp Login (Scan QR / Code)',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (isLoggedIn) ...[
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: LicenseService.isLicensed
                                    ? const Color(0xFF065F46)
                                    : (LicenseService.isExpired
                                        ? Colors.red.shade900
                                        : const Color(0xFF78350F)),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                LicenseService.isLicensed
                                    ? '👑 PRO PASS (${LicenseService.expiryLabel})'
                                    : (LicenseService.isExpired
                                        ? '⏰ EXPIRED (${LicenseService.formattedExpiryDateTime})'
                                        : '⚡ FREE TRIAL (${LicenseService.remainingTrial}/25 left)'),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                      ],
                      Text(
                        isLoggedIn
                            ? (isConnected
                                ? 'WhatsApp is linked and ready! Broadcasts to groups and contacts enabled.'
                                : 'WhatsApp session active (syncing connection)...')
                            : 'Scan QR code or link with phone number inside the app',
                        style:
                            const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isLoggedIn
                        ? (isConnected
                            ? Colors.green.shade50
                            : Colors.amber.shade50)
                        : Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isLoggedIn
                          ? (isConnected
                              ? Colors.green.shade300
                              : Colors.amber.shade400)
                          : Colors.orange.shade300,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.circle,
                        size: 8,
                        color: isLoggedIn
                            ? (isConnected
                                ? Colors.green
                                : Colors.amber.shade800)
                            : Colors.orange,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isLoggedIn
                            ? (isConnected ? 'Online' : 'Syncing')
                            : 'Scan Required',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isLoggedIn
                              ? (isConnected
                                  ? Colors.green
                                  : Colors.amber.shade800)
                              : Colors.orange,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            if (isLoggedIn) ...[
              const SizedBox(height: 14),
              const Divider(),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF075E54),
                      side: const BorderSide(color: Color(0xFF075E54)),
                    ),
                    onPressed: () => _checkServerStatus(),
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Refresh Status'),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade50,
                      foregroundColor: Colors.red.shade700,
                      elevation: 0,
                      side: BorderSide(color: Colors.red.shade300),
                    ),
                    onPressed: _logoutWhatsApp,
                    icon: const Icon(Icons.logout, size: 16),
                    label: const Text(
                      'Logout WhatsApp',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ],

            if (!isLoggedIn) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),

              // OPTION A: QR Code Rendered directly in App
              if (qrBytes != null) ...[
                Center(
                  child: Column(
                    children: [
                      const Text(
                        'Step 1: Scan this QR with your WhatsApp',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Color(0xFF075E54),
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'WhatsApp > Linked Devices > Link a Device',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Image.memory(
                          qrBytes,
                          width: 220,
                          height: 220,
                          fit: BoxFit.contain,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'QR code auto-refreshes every few seconds...',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.5)),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (_isStartingServer || _isCheckingStatus)
                            const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2.2, color: Color(0xFFB45309)),
                            )
                          else
                            const Icon(Icons.cloud_off_rounded, color: Color(0xFFD97706), size: 24),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _isStartingServer
                                  ? 'Starting WhatsApp Server... Please wait 5 seconds'
                                  : 'Waiting for WhatsApp Server... (Port 3000 Offline)',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF92400E),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'The local WhatsApp server must be running to display QR code and broadcast messages. If the server is offline, click the button below to launch it:',
                        style: TextStyle(fontSize: 11.5, color: Color(0xFF78350F), height: 1.4),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        children: [
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF075E54),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              elevation: 2,
                            ),
                            onPressed: _isStartingServer ? null : _startLocalServer,
                            icon: _isStartingServer
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Icon(Icons.rocket_launch_rounded, size: 16),
                            label: Text(
                              _isStartingServer ? 'Starting Server...' : '🚀 1-Click Start Server',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                            ),
                          ),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF92400E),
                              side: const BorderSide(color: Color(0xFFD97706)),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: () => _checkServerStatus(),
                            icon: const Icon(Icons.refresh_rounded, size: 16),
                            label: const Text('Refresh Status', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          ),
                          TextButton.icon(
                            onPressed: () async {
                              final ok = await _gatewayService.resetSession();
                              _checkServerStatus();
                              if (ok) {
                                _showSnackbar('Session reset successful.');
                              } else {
                                _showSnackbar('Could not reset session. Start server first.');
                              }
                            },
                            icon: const Icon(Icons.restore, size: 14, color: Color(0xFFB45309)),
                            label: const Text('Reset Session', style: TextStyle(fontSize: 11.5, color: Color(0xFFB45309))),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // OPTION B: Link with Phone Number (Pairing Code)
              const Text(
                'Or Link with Phone Number (Pairing Code - No Camera Required):',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _pairPhoneController,
                      decoration: const InputDecoration(
                        labelText: 'Your WhatsApp Number',
                        hintText: 'e.g. 919876543210',
                        prefixIcon: Icon(Icons.phone),
                        isDense: true,
                      ),
                      keyboardType: TextInputType.phone,
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF128C7E),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed:
                        _isRequestingPairingCode ? null : _requestPairingCode,
                    child: _isRequestingPairingCode
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Text('Get Code'),
                  ),
                ],
              ),
              if (_pairingCode != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green.shade300),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.key, color: Colors.green),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'WhatsApp Pairing Code:',
                              style: TextStyle(fontSize: 11, color: Colors.grey),
                            ),
                            Text(
                              _pairingCode!,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 2,
                                color: Color(0xFF075E54),
                              ),
                            ),
                            const Text(
                              'WhatsApp > Linked Devices > Link with phone number instead me daalein.',
                              style:
                                  TextStyle(fontSize: 11, color: Colors.black87),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 20),
                        tooltip: 'Copy Code',
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: _pairingCode!));
                          _showSnackbar('Code copied to clipboard!');
                        },
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.help_outline, size: 16, color: Colors.blue),
                        SizedBox(width: 6),
                        Text(
                          'If WhatsApp shows "Try again later" or connection fails:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      '1. Open WhatsApp on your phone > Linked Devices and log out old sessions (Max 4 allowed).\n'
                      '2. Verify that country code (+91) and phone number are correct.\n'
                      '3. Click the Reset button below to clear session and scan a fresh QR code.',
                      style: TextStyle(fontSize: 11, color: Colors.black87),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red.shade700,
                          side: BorderSide(color: Colors.red.shade300),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                        ),
                        onPressed: _resetSession,
                        icon: const Icon(Icons.restore, size: 16),
                        label: const Text(
                          'Fix / Reset WhatsApp Session',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPitchCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Message Pitch (Script)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _messageController,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Message Body',
                hintText: 'Use {name} to personalize each message...',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              '💡 Tip: Message me {name} apne aap client ke naam se replace ho jayega (groups me group name aayega).',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNumbersAndGroupsCard(int count) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Recipients (Numbers & Groups)',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                if (_duplicateLinesCount > 0) ...[
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.orange.shade800,
                      backgroundColor: Colors.orange.shade50,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    onPressed: _removeDuplicatesFromController,
                    icon: const Icon(Icons.cleaning_services, size: 14),
                    label: Text(
                      'Remove $_duplicateLinesCount Duplicates',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                if (count > 0) ...[
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.red.shade700,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    onPressed: () {
                      setState(() {
                        _numbersController.clear();
                      });
                    },
                    icon: const Icon(Icons.clear_all, size: 16),
                    label: const Text('Clear', style: TextStyle(fontSize: 12)),
                  ),
                  const SizedBox(width: 6),
                ],
                Badge(
                  label: Text('$count Unique'),
                  backgroundColor:
                      count > 0 ? const Color(0xFF128C7E) : Colors.grey,
                ),
              ],
            ),
            const SizedBox(height: 10),

            // ACTION BUTTONS: Import Phone Contacts, WhatsApp Chats & Select Groups
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF128C7E),
                      side: const BorderSide(color: Color(0xFF128C7E)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    onPressed: _pickContactsFromPhone,
                    icon: const Icon(Icons.file_upload, size: 16),
                    label: const Text(
                      'Import .vcf/Leads',
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF075E54),
                      side: const BorderSide(color: Color(0xFF075E54)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    onPressed: _isLoadingChats ? null : _fetchAndSelectWhatsAppChats,
                    icon: _isLoadingChats
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.chat, size: 16),
                    label: const Text(
                      'Direct Chats',
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF128C7E),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      elevation: 0,
                    ),
                    onPressed:
                        _isLoadingGroups ? null : _fetchAndSelectGroups,
                    icon: _isLoadingGroups
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Icon(Icons.groups, size: 16),
                    label: Text(
                      _availableGroups.isEmpty
                          ? 'Groups'
                          : 'Groups (${_availableGroups.length})',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                SizedBox(
                  width: 100,
                  child: TextField(
                    controller: _countryCodeController,
                    decoration: const InputDecoration(
                      labelText: 'Code',
                      prefixText: '+',
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Default code for 10-digit numbers (91 for India).',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _numbersController,
              maxLines: 4,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Recipients: Numbers or Groups',
                hintText:
                    'Contacts yahan add honge...\nUpar diye gaye buttons se "Import .vcf/Leads", "WhatsApp Chats" ya "Groups" chunein.',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'You can add both regular phone numbers and WhatsApp Groups here.',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionCard(int count, bool isConnected) {
    final totalMessages = count * _boosterRepeatCount;
    final isBooster = _boosterRepeatCount > 1;

    return Card(
      color: isBooster ? Colors.orange.shade50 : Colors.green.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isBooster ? Colors.orange.shade400 : Colors.green.shade300,
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // BOOSTER MODE HEADER & CONTROLS
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isBooster
                      ? Colors.orange.shade300
                      : Colors.grey.shade300,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.bolt,
                        color: isBooster
                            ? Colors.orange.shade800
                            : const Color(0xFF128C7E),
                        size: 22,
                      ),
                      const SizedBox(width: 6),
                      const Expanded(
                        child: Text(
                          'Message Booster / Multiplier',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: isBooster
                              ? Colors.orange.shade100
                              : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isBooster
                                ? Colors.orange.shade400
                                : Colors.grey.shade300,
                          ),
                        ),
                        child: Text(
                          isBooster
                              ? '🔥 ${_boosterRepeatCount}x Booster Active'
                              : '1x (Single Send)',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isBooster
                                ? Colors.orange.shade900
                                : Colors.grey.shade700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Select repeat count (how many times to repeat send each message):',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  const SizedBox(height: 10),

                  // Quick Repeat Chips
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [1, 5, 10, 20, 50, 100].map((countVal) {
                      final isSelected = _boosterRepeatCount == countVal;
                      final isLockedForUser =
                          countVal > 1 && !LicenseService.isLicensed;
                      return ChoiceChip(
                        label: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(countVal == 1 ? '1x (Normal)' : '${countVal}x'),
                            if (isLockedForUser) ...[
                              const SizedBox(width: 4),
                              const Icon(Icons.lock, size: 12, color: Colors.amber),
                            ],
                          ],
                        ),
                        selected: isSelected,
                        selectedColor: isBooster
                            ? Colors.orange.shade400
                            : const Color(0xFF128C7E),
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.white : Colors.black87,
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.normal,
                          fontSize: 12,
                        ),
                        onSelected: _isSending
                            ? null
                            : (selected) {
                                if (selected) {
                                  if (isLockedForUser) {
                                    _showPaymentAndLicenseDialog(
                                        reason: 'booster');
                                    return;
                                  }
                                  setState(() {
                                    _boosterRepeatCount = countVal;
                                    _boosterCountController.text =
                                        countVal.toString();
                                  });
                                }
                              },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 10),

                  // Custom Count Stepper & Input
                  Row(
                    children: [
                      const Text(
                        'Custom Repeat:',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        icon: const Icon(Icons.remove, size: 16),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                            minWidth: 32, minHeight: 32),
                        onPressed: (_isSending || _boosterRepeatCount <= 1)
                            ? null
                            : () {
                                setState(() {
                                  _boosterRepeatCount--;
                                  _boosterCountController.text =
                                      _boosterRepeatCount.toString();
                                });
                              },
                      ),
                      const SizedBox(width: 6),
                      SizedBox(
                        width: 70,
                        height: 36,
                        child: TextField(
                          controller: _boosterCountController,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14),
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding:
                                EdgeInsets.symmetric(vertical: 8),
                          ),
                          onChanged: (val) {
                            final parsed = int.tryParse(val.trim());
                            if (parsed != null && parsed >= 1) {
                              if (parsed > 1 && !LicenseService.isLicensed) {
                                _boosterCountController.text = '1';
                                _boosterCountController.selection =
                                    const TextSelection.collapsed(offset: 1);
                                setState(() {
                                  _boosterRepeatCount = 1;
                                });
                                _showPaymentAndLicenseDialog(reason: 'booster');
                                return;
                              }
                              setState(() {
                                _boosterRepeatCount = parsed;
                              });
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton.filledTonal(
                        icon: const Icon(Icons.add, size: 16),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                            minWidth: 32, minHeight: 32),
                        onPressed: _isSending
                            ? null
                            : () {
                                if (!LicenseService.isLicensed) {
                                  _showPaymentAndLicenseDialog(
                                      reason: 'booster');
                                  return;
                                }
                                setState(() {
                                  _boosterRepeatCount++;
                                  _boosterCountController.text =
                                      _boosterRepeatCount.toString();
                                });
                              },
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Bar / Times',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade700),
                      ),
                    ],
                  ),

                  if (isBooster && count > 0) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.local_fire_department,
                              size: 18, color: Colors.orange.shade800),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Booster Active: $count Target(s) × $_boosterRepeatCount Times = $totalMessages Messages jayenge!',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.orange.shade900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Delay Setting
            Row(
              children: [
                const Icon(Icons.timer_outlined, size: 20, color: Colors.grey),
                const SizedBox(width: 8),
                Text(
                  'Delay: ${_delaySeconds.toStringAsFixed(1)}s',
                  style: const TextStyle(
                      fontWeight: FontWeight.w500, fontSize: 13),
                ),
                Expanded(
                  child: Slider(
                    value: _delaySeconds,
                    min: 0.5,
                    max: 6.0,
                    divisions: 11,
                    activeColor: isBooster
                        ? Colors.orange.shade800
                        : const Color(0xFF128C7E),
                    onChanged: _isSending
                        ? null
                        : (val) {
                            setState(() {
                              _delaySeconds = val;
                            });
                          },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Action Button / Stop Button
            if (_isSending) ...[
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  minimumSize: const Size.fromHeight(54),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 3,
                ),
                onPressed: _isStopping ? null : _stopBroadcast,
                icon: _isStopping
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Icon(Icons.stop_circle, size: 26),
                label: Text(
                  _isStopping
                      ? 'Stopping Broadcast...'
                      : '🛑 STOP BROADCAST NOW',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                backgroundColor: Colors.red.shade100,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.red.shade600),
              ),
              const SizedBox(height: 6),
              Center(
                child: Text(
                  _isStopping
                      ? 'Aborting active sends...'
                      : 'Sending $totalMessages messages (${_boosterRepeatCount}x Booster)... Tap STOP anytime to cancel immediately!',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.red.shade800,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ] else ...[
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: !isConnected
                      ? Colors.grey.shade400
                      : (!_termsAccepted
                          ? Colors.blueGrey.shade600
                          : (isBooster
                              ? Colors.orange.shade800
                              : const Color(0xFF25D366))),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 2,
                ),
                onPressed: (!isConnected || count == 0)
                    ? null
                    : () {
                        if (!_termsAccepted) {
                          _showSnackbar(
                              '⚠️ Please accept the Terms & Conditions below to enable message boosting!');
                          _showTermsAndConditionsDialog();
                          return;
                        }
                        _sendBulkAuto();
                      },
                icon: Icon(
                  !_termsAccepted
                      ? Icons.lock_outline
                      : (isBooster
                          ? Icons.local_fire_department
                          : Icons.rocket_launch),
                  size: 22,
                ),
                label: Text(
                  isConnected
                      ? (!_termsAccepted
                          ? '⚠️ Accept Terms Below to Boost / Send'
                          : (isBooster
                              ? '🔥 Launch Booster: $totalMessages Messages ($count Targets × ${_boosterRepeatCount}x)'
                              : '🚀 Send to All $count Targets in 1 Click'))
                      : 'Connect WhatsApp First (Scan QR / Code)',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              if (isConnected) ...[
                const SizedBox(height: 6),
                Center(
                  child: Text(
                    isBooster
                        ? '⚡ Booster Mode: Har target ko lagatar $_boosterRepeatCount baar message deliver hoga.'
                        : 'Ek click me sabhi numbers aur groups par background me bina browser khole message send ho jayega!',
                    style: TextStyle(
                      fontSize: 11,
                      color: isBooster
                          ? Colors.orange.shade900
                          : const Color(0xFF075E54),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDeliveryReportCard() {
    final result = _sendResult!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Delivery Report',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Chip(
                  label: Text('✅ ${result.sentCount} Sent'),
                  backgroundColor: Colors.green.shade50,
                  side: BorderSide(color: Colors.green.shade200),
                ),
                const SizedBox(width: 8),
                Chip(
                  label: Text('❌ ${result.failedCount} Failed'),
                  backgroundColor: Colors.red.shade50,
                  side: BorderSide(color: Colors.red.shade200),
                ),
              ],
            ),
            const Divider(),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: result.results.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, idx) {
                final item = result.results[idx];
                final isGroup = item.phone.contains('@g.us') ||
                    item.phone.contains('-') ||
                    item.phone.startsWith('120363');

                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    radius: 14,
                    backgroundColor: item.success
                        ? Colors.green.shade100
                        : Colors.red.shade100,
                    child: Icon(
                      item.success ? Icons.check : Icons.close,
                      size: 16,
                      color: item.success ? Colors.green : Colors.red,
                    ),
                  ),
                  title: Row(
                    children: [
                      Icon(
                        isGroup ? Icons.groups : Icons.person,
                        size: 16,
                        color: Colors.grey.shade600,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          item.name,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  subtitle: item.success
                      ? Text(
                          'Target: ${item.phone} • Delivered',
                          style:
                              const TextStyle(fontSize: 11, color: Colors.grey),
                        )
                      : Text(
                          item.error ?? 'Failed',
                          style:
                              const TextStyle(fontSize: 11, color: Colors.red),
                        ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}