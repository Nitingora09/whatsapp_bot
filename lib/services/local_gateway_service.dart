import 'dart:convert';

import 'package:http/http.dart' as http;

class WhatsAppGroupItem {
  final String id;
  final String name;
  final int participantsCount;

  WhatsAppGroupItem({
    required this.id,
    required this.name,
    required this.participantsCount,
  });

  factory WhatsAppGroupItem.fromJson(Map<String, dynamic> json) {
    return WhatsAppGroupItem(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Unnamed Group',
      participantsCount: json['participantsCount'] as int? ?? 0,
    );
  }
}

class WhatsAppContactItem {
  final String id;
  final String phone;
  final String name;

  WhatsAppContactItem({
    required this.id,
    required this.phone,
    required this.name,
  });

  factory WhatsAppContactItem.fromJson(Map<String, dynamic> json) {
    return WhatsAppContactItem(
      id: json['id']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Client',
    );
  }
}

class GatewayStatus {
  final bool connected;
  final bool isLoggedIn;
  final String? user;
  final bool hasQr;
  final String? qrDataUrl;

  GatewayStatus({
    required this.connected,
    this.isLoggedIn = false,
    this.user,
    required this.hasQr,
    this.qrDataUrl,
  });

  factory GatewayStatus.fromJson(Map<String, dynamic> json) {
    final conn = json['connected'] == true;
    final loggedIn = json['isLoggedIn'] == true || conn;
    return GatewayStatus(
      connected: conn,
      isLoggedIn: loggedIn,
      user: json['user']?.toString(),
      hasQr: json['hasQr'] == true,
      qrDataUrl: json['qrDataUrl']?.toString(),
    );
  }
}

class BulkSendItemResult {
  final String phone;
  final String name;
  final bool success;
  final String? messageId;
  final String? error;

  BulkSendItemResult({
    required this.phone,
    required this.name,
    required this.success,
    this.messageId,
    this.error,
  });

  factory BulkSendItemResult.fromJson(Map<String, dynamic> json) {
    return BulkSendItemResult(
      phone: json['phone']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Client',
      success: json['success'] == true,
      messageId: json['messageId']?.toString(),
      error: json['error']?.toString(),
    );
  }
}

class BulkSendResponse {
  final bool success;
  final bool stopped;
  final int total;
  final int sentCount;
  final int failedCount;
  final List<BulkSendItemResult> results;
  final String? error;

  BulkSendResponse({
    required this.success,
    this.stopped = false,
    required this.total,
    required this.sentCount,
    required this.failedCount,
    required this.results,
    this.error,
  });

  factory BulkSendResponse.fromJson(Map<String, dynamic> json) {
    final list =
        (json['results'] as List?)
            ?.map((e) => BulkSendItemResult.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    return BulkSendResponse(
      success: json['success'] == true,
      stopped: json['stopped'] == true,
      total: json['total'] as int? ?? list.length,
      sentCount:
          json['sentCount'] as int? ?? list.where((r) => r.success).length,
      failedCount:
          json['failedCount'] as int? ?? list.where((r) => !r.success).length,
      results: list,
      error: json['error']?.toString(),
    );
  }
}

class LocalGatewayService {
  String baseUrl;

  LocalGatewayService({this.baseUrl = 'http://localhost:3000'});

  Uri _uri(String path) {
    final cleanBase = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return Uri.parse('$cleanBase$path');
  }

  Future<GatewayStatus> checkStatus() async {
    try {
      final response = await http
          .get(_uri('/api/status'))
          .timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return GatewayStatus.fromJson(data);
      }
      return GatewayStatus(connected: false, hasQr: false);
    } catch (_) {
      return GatewayStatus(connected: false, hasQr: false);
    }
  }

  Future<List<WhatsAppGroupItem>> fetchGroups() async {
    try {
      final response = await http
          .get(_uri('/api/groups'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['success'] == true && data['groups'] is List) {
          return (data['groups'] as List)
              .map((g) => WhatsAppGroupItem.fromJson(g as Map<String, dynamic>))
              .toList();
        }
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<List<WhatsAppContactItem>> fetchContacts() async {
    try {
      final response = await http
          .get(_uri('/api/contacts'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['success'] == true && data['contacts'] is List) {
          return (data['contacts'] as List)
              .map(
                (c) => WhatsAppContactItem.fromJson(c as Map<String, dynamic>),
              )
              .toList();
        }
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<int> importContacts(List<Map<String, String>> contacts) async {
    try {
      final response = await http
          .post(
            _uri('/api/import-contacts'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'contacts': contacts}),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return (data['added'] as int?) ?? 0;
      }
      return 0;
    } catch (_) {
      return 0;
    }
  }

  Future<bool> clearContacts() async {
    try {
      final response = await http
          .post(_uri('/api/contacts/clear'))
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<BulkSendResponse> sendBulk({
    required List<Map<String, String>> recipients,
    required String messageTemplate,
    int delayMs = 2000,
    int repeatCount = 1,
  }) async {
    final expectedTotal =
        recipients.length * (repeatCount > 0 ? repeatCount : 1);
    try {
      final response = await http
          .post(
            _uri('/api/send-bulk'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'recipients': recipients,
              'messageTemplate': messageTemplate,
              'delayMs': delayMs,
              'repeatCount': repeatCount,
            }),
          )
          .timeout(const Duration(minutes: 15));

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return BulkSendResponse.fromJson(data);
    } catch (e) {
      return BulkSendResponse(
        success: false,
        total: expectedTotal,
        sentCount: 0,
        failedCount: expectedTotal,
        results: [],
        error: e.toString(),
      );
    }
  }

  Future<bool> stopBroadcast() async {
    try {
      final response = await http
          .post(_uri('/api/stop-broadcast'))
          .timeout(const Duration(seconds: 4));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> requestPairingCode(
    String phone, {
    String countryCode = '91',
  }) async {
    try {
      final response = await http
          .post(
            _uri('/api/pair'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'phone': phone, 'countryCode': countryCode}),
          )
          .timeout(const Duration(seconds: 10));
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<bool> resetSession() async {
    try {
      final res = await http.post(_uri('/api/reset-session'));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> logout() async {
    try {
      final res = await http
          .post(_uri('/api/logout'))
          .timeout(const Duration(seconds: 5));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> sendSingle({
    required String phone,
    required String message,
  }) async {
    try {
      final response = await http.post(
        _uri('/api/send'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'phone': phone, 'message': message}),
      );
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }
}
