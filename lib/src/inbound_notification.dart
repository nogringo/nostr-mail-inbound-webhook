import 'dart:convert';

import 'package:enough_mail_plus/enough_mail.dart';
import 'package:http/http.dart' as http;
import 'package:ndk/ndk.dart';

const giftWrapKind = 1059;
const _previewLength = 160;

class EmailNotification {
  const EmailNotification({
    required this.fromAddress,
    required this.fromName,
    required this.subject,
    required this.preview,
  });

  factory EmailNotification.fromMime(MimeMessage message) {
    final from = message.from?.firstOrNull;
    final plainText = message.decodeTextPlainPart() ?? '';
    final normalizedPreview = plainText.replaceAll(RegExp(r'\s+'), ' ').trim();

    return EmailNotification(
      fromAddress: from?.email ?? message.fromEmail ?? '',
      fromName: from?.personalName,
      subject: message.decodeSubject() ?? '',
      preview: String.fromCharCodes(
        normalizedPreview.runes.take(_previewLength),
      ),
    );
  }

  final String fromAddress;
  final String? fromName;
  final String subject;
  final String preview;

  Map<String, Object?> toJson() => {
    'from': {'address': fromAddress, 'name': fromName},
    'subject': subject,
    'preview': preview,
  };
}

abstract interface class InboundNotifier {
  Future<void> notify({
    required String recipientPubkey,
    required List<String> relays,
    required Nip01Event event,
    required EmailNotification email,
  });
}

class InboundNotificationClient implements InboundNotifier {
  InboundNotificationClient({
    required this.url,
    required this.token,
    this.timeout = const Duration(seconds: 10),
    http.Client? client,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null;

  final Uri url;
  final String token;
  final Duration timeout;
  final http.Client _client;
  final bool _ownsClient;

  @override
  Future<void> notify({
    required String recipientPubkey,
    required List<String> relays,
    required Nip01Event event,
    required EmailNotification email,
  }) async {
    final response = await _client
        .post(
          url,
          headers: {
            'authorization': 'Bearer $token',
            'content-type': 'application/json',
          },
          body: jsonEncode({
            'recipientPubkey': recipientPubkey,
            'relays': relays,
            'event': _eventJson(event),
            'email': email.toJson(),
          }),
        )
        .timeout(timeout);

    if (response.statusCode != 202) {
      throw InboundNotificationException(
        'notification API returned ${response.statusCode}',
      );
    }

    Object? body;
    try {
      body = jsonDecode(response.body);
    } on FormatException {
      throw InboundNotificationException(
        'notification API returned invalid JSON',
      );
    }
    if (body is! Map || body['status'] != 'accepted') {
      throw InboundNotificationException(
        'notification API did not accept the notification',
      );
    }
  }

  Map<String, Object?> _eventJson(Nip01Event event) => {
    'id': event.id,
    'pubkey': event.pubKey,
    'created_at': event.createdAt,
    'kind': event.kind,
    'tags': event.tags,
    if (event.kind != giftWrapKind) ...{
      'content': event.content,
      'sig': event.sig,
    },
  };

  void close() {
    if (_ownsClient) _client.close();
  }
}

class InboundNotificationException implements Exception {
  InboundNotificationException(this.message);

  final String message;

  @override
  String toString() => message;
}
