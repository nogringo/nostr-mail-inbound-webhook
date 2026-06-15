import 'dart:convert';

import 'package:crypto/crypto.dart';

class WebhookSignatureException implements Exception {
  WebhookSignatureException(this.message);

  final String message;

  @override
  String toString() => message;
}

String mailgunSignature({
  required String signingKey,
  required String timestamp,
  required String token,
}) {
  final hmac = Hmac(sha256, utf8.encode(signingKey));
  return hmac.convert(utf8.encode('$timestamp$token')).toString();
}

void verifyMailgunSignature({
  required Map<String, String> fields,
  required String signingKey,
  required Duration tolerance,
  DateTime? now,
}) {
  if (signingKey.isEmpty) return;

  final timestamp = fields['timestamp'];
  final token = fields['token'];
  final signature = fields['signature'];
  if (timestamp == null ||
      timestamp.isEmpty ||
      token == null ||
      token.isEmpty ||
      signature == null ||
      signature.isEmpty) {
    throw WebhookSignatureException('missing webhook signature fields');
  }

  final timestampSeconds = int.tryParse(timestamp);
  if (timestampSeconds == null) {
    throw WebhookSignatureException('invalid webhook timestamp');
  }

  final current = now ?? DateTime.now().toUtc();
  final signedAt = DateTime.fromMillisecondsSinceEpoch(
    timestampSeconds * 1000,
    isUtc: true,
  );
  if (current.difference(signedAt).abs() > tolerance) {
    throw WebhookSignatureException('expired webhook signature');
  }

  final expected = mailgunSignature(
    signingKey: signingKey,
    timestamp: timestamp,
    token: token,
  );
  if (!_constantTimeEquals(expected, signature.toLowerCase())) {
    throw WebhookSignatureException('invalid webhook signature');
  }
}

bool _constantTimeEquals(String a, String b) {
  if (a.length != b.length) return false;

  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}
