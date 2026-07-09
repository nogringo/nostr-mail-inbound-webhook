import 'dart:convert';
import 'dart:typed_data';

import 'package:enough_mail_plus/enough_mail.dart' show MimeMessage;
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'config.dart';
import 'mailgun_signature.dart';
import 'mime_delivery.dart';
import 'mime_rewriter.dart';
import 'recipient_resolver.dart';

Handler createHandler({
  required WebhookConfig config,
  required MimeMailer mailer,
  required RecipientResolver recipientResolver,
  DateTime Function()? now,
}) {
  final router = Router()
    ..get('/healthz', (_) => Response.ok('ok\n'))
    ..post('/mime', (request) {
      return _handleMime(
        request,
        config: config,
        mailer: mailer,
        recipientResolver: recipientResolver,
        now: now,
      );
    });

  return Pipeline().addMiddleware(logRequests()).addHandler(router.call);
}

Future<Response> _handleMime(
  Request request, {
  required WebhookConfig config,
  required MimeMailer mailer,
  required RecipientResolver recipientResolver,
  DateTime Function()? now,
}) async {
  final contentType = request.headers['content-type'] ?? '';
  if (!contentType.toLowerCase().contains(
    'application/x-www-form-urlencoded',
  )) {
    return Response(406, body: 'expected application/x-www-form-urlencoded\n');
  }

  final String body;
  try {
    body = await _readBodyWithLimit(request, _maxFormBytes(config));
  } on PayloadTooLargeException {
    return Response(406, body: 'payload too large\n');
  } on FormatException {
    return Response(406, body: 'invalid form payload\n');
  }

  final Map<String, String> fields;
  try {
    fields = Uri.splitQueryString(body);
  } catch (_) {
    return Response(406, body: 'invalid form payload\n');
  }

  try {
    verifyMailgunSignature(
      fields: fields,
      signingKey: config.webhookSigningKey,
      tolerance: config.signatureTolerance,
      now: now?.call(),
    );
  } on WebhookSignatureException catch (error) {
    return Response(401, body: '$error\n');
  }

  final rawMime = fields['body-mime'];
  if (rawMime == null || rawMime.isEmpty) {
    return Response(406, body: 'missing body-mime\n');
  }
  if (utf8.encode(rawMime).length > config.maxMimeBytes) {
    return Response(406, body: 'MIME too large\n');
  }

  final MimeMessage parsedMime;
  try {
    parsedMime = MimeMessage.parseFromText(rawMime);
  } catch (_) {
    return Response(406, body: 'invalid MIME\n');
  }

  final envelopeRecipients = _parseEnvelopeRecipients(fields['recipient']);
  final recipientInputs = envelopeRecipients.isNotEmpty
      ? envelopeRecipients
      : recipientsFromMime(parsedMime);

  final resolved = await recipientResolver.resolveAll(recipientInputs);
  if (resolved.isEmpty) {
    return Response(406, body: 'no resolvable recipients\n');
  }

  try {
    for (final recipient in resolved) {
      final message = rewriteMimeForRecipient(
        rawMime: rawMime,
        recipientPubkey: recipient.pubkey,
        originalRecipient: recipient.original,
        mailFrom: fields['sender'],
      );
      await mailer.sendMime(
        message,
        recipientPubkey: recipient.pubkey,
        mailFrom: fields['sender'],
      );
    }
  } catch (error) {
    return Response.internalServerError(body: 'nostr delivery failed\n');
  }

  return Response.ok('accepted ${resolved.length} recipient(s)\n');
}

List<String> _parseEnvelopeRecipients(String? recipients) {
  if (recipients == null || recipients.trim().isEmpty) return const [];
  return recipients
      .split(',')
      .map((recipient) => recipient.trim())
      .where((recipient) => recipient.isNotEmpty)
      .toList(growable: false);
}

int _maxFormBytes(WebhookConfig config) {
  // application/x-www-form-urlencoded can percent-encode MIME bytes. Allow
  // room for that transport overhead while still bounding memory use.
  return config.maxMimeBytes * 4 + 1024 * 1024;
}

Future<String> _readBodyWithLimit(Request request, int maxBytes) async {
  final builder = BytesBuilder(copy: false);
  var total = 0;

  await for (final chunk in request.read()) {
    total += chunk.length;
    if (total > maxBytes) {
      throw PayloadTooLargeException();
    }
    builder.add(chunk);
  }

  return utf8.decode(builder.takeBytes());
}

class PayloadTooLargeException implements Exception {}
