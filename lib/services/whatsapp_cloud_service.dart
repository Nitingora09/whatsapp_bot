import 'dart:convert';
import 'package:http/http.dart' as http;

/// Delivery status of a message.
enum SendStatus {
  pending,
  sending,
  success,
  failed,
}

/// Result of sending a WhatsApp message to a specific recipient.
class WhatsAppSendResult {
  final String recipient;
  final SendStatus status;
  final String? messageId;
  final String? errorMessage;
  final int? statusCode;
  final DateTime timestamp;

  WhatsAppSendResult({
    required this.recipient,
    required this.status,
    this.messageId,
    this.errorMessage,
    this.statusCode,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  WhatsAppSendResult copyWith({
    SendStatus? status,
    String? messageId,
    String? errorMessage,
    int? statusCode,
  }) {
    return WhatsAppSendResult(
      recipient: recipient,
      status: status ?? this.status,
      messageId: messageId ?? this.messageId,
      errorMessage: errorMessage ?? this.errorMessage,
      statusCode: statusCode ?? this.statusCode,
      timestamp: timestamp,
    );
  }
}

/// Meta WhatsApp Cloud API Service.
///
/// Communicates directly with Meta's official Graph API endpoint:
/// https://graph.facebook.com/{apiVersion}/{phoneNumberId}/messages
class WhatsAppCloudService {
  final String phoneNumberId;
  final String accessToken;
  final String apiVersion;

  static const String defaultApiVersion = 'v21.0';

  WhatsAppCloudService({
    required this.phoneNumberId,
    required this.accessToken,
    this.apiVersion = defaultApiVersion,
  });

  Uri get _messagesUri => Uri.parse(
        'https://graph.facebook.com/$apiVersion/${phoneNumberId.trim()}/messages',
      );

  Map<String, String> get _headers => {
        'Authorization': 'Bearer ${accessToken.trim()}',
        'Content-Type': 'application/json',
      };

  /// Clean phone numbers by removing spaces, dashes, brackets, and leading '+'
  /// WhatsApp Cloud API requires numbers in international format without symbols (e.g., 15551234567).
  static String cleanPhoneNumber(String rawNumber) {
    return rawNumber.replaceAll(RegExp(r'[\s\-\(\)\+]'), '').trim();
  }

  /// Sends a freeform text message.
  ///
  /// Note: Meta Cloud API allows freeform text if the recipient has messaged
  /// your business within the past 24 hours. Outside of this 24-hour window,
  /// Meta requires pre-approved template messages.
  Future<WhatsAppSendResult> sendTextMessage({
    required String to,
    required String message,
  }) async {
    final cleaned = cleanPhoneNumber(to);
    if (cleaned.isEmpty) {
      return WhatsAppSendResult(
        recipient: to,
        status: SendStatus.failed,
        errorMessage: 'Invalid or empty phone number',
      );
    }

    final payload = {
      'messaging_product': 'whatsapp',
      'recipient_type': 'individual',
      'to': cleaned,
      'type': 'text',
      'text': {
        'preview_url': false,
        'body': message,
      },
    };

    return _postMessage(cleaned, payload);
  }

  /// Sends a pre-approved template message (e.g. 'hello_world').
  ///
  /// Use this when initiating messages to users outside the 24-hour service window.
  Future<WhatsAppSendResult> sendTemplateMessage({
    required String to,
    required String templateName,
    String languageCode = 'en_US',
  }) async {
    final cleaned = cleanPhoneNumber(to);
    if (cleaned.isEmpty) {
      return WhatsAppSendResult(
        recipient: to,
        status: SendStatus.failed,
        errorMessage: 'Invalid or empty phone number',
      );
    }

    final payload = {
      'messaging_product': 'whatsapp',
      'to': cleaned,
      'type': 'template',
      'template': {
        'name': templateName.trim(),
        'language': {
          'code': languageCode.trim(),
        },
      },
    };

    return _postMessage(cleaned, payload);
  }

  Future<WhatsAppSendResult> _postMessage(
    String recipient,
    Map<String, dynamic> payload,
  ) async {
    try {
      final response = await http.post(
        _messagesUri,
        headers: _headers,
        body: jsonEncode(payload),
      );

      final decoded = jsonDecode(response.body);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        String? messageId;
        if (decoded is Map && decoded.containsKey('messages')) {
          final list = decoded['messages'] as List?;
          if (list != null && list.isNotEmpty) {
            messageId = list[0]['id']?.toString();
          }
        }
        return WhatsAppSendResult(
          recipient: recipient,
          status: SendStatus.success,
          messageId: messageId,
          statusCode: response.statusCode,
        );
      } else {
        String errorMessage = 'HTTP ${response.statusCode}';
        if (decoded is Map && decoded.containsKey('error')) {
          final err = decoded['error'];
          if (err is Map) {
            final msg = err['message'] ?? '';
            final code = err['code'] != null ? ' (Code: ${err['code']})' : '';
            final details = err['error_user_msg'] ?? err['error_data']?['details'] ?? '';
            errorMessage = '$msg$code ${details.isNotEmpty ? "- $details" : ""}';
          }
        }
        return WhatsAppSendResult(
          recipient: recipient,
          status: SendStatus.failed,
          errorMessage: errorMessage,
          statusCode: response.statusCode,
        );
      }
    } catch (e) {
      return WhatsAppSendResult(
        recipient: recipient,
        status: SendStatus.failed,
        errorMessage: e.toString(),
      );
    }
  }
}
