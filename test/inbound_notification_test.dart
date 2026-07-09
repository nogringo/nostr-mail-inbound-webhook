import 'dart:convert';

import 'package:http/http.dart';
import 'package:http/testing.dart';
import 'package:inbound_mail_webhook/src/inbound_notification.dart';
import 'package:ndk/ndk.dart';
import 'package:test/test.dart';

void main() {
  final (_, recipientPubkey) = const Bip340EventSignerFactory()
      .generateKeyPair();
  final (_, authorPubkey) = const Bip340EventSignerFactory().generateKeyPair();
  final url = Uri.parse('https://api.example.com/inbound/notifications');
  const email = EmailNotification(
    fromAddress: 'alice@example.net',
    fromName: 'Alice',
    subject: 'Hello',
    preview: 'Short plaintext preview',
  );

  Nip01Event event({required int kind}) => Nip01Event(
    id: 'event-id',
    pubKey: authorPubkey,
    createdAt: 1700000000,
    kind: kind,
    tags: [
      ['p', recipientPubkey],
    ],
    content: 'secret content',
    sig: 'event-signature',
  );

  test('sends a gift wrap without content or sig', () async {
    late Request request;
    final client = InboundNotificationClient(
      url: url,
      token: 'secret',
      client: MockClient((incoming) async {
        request = incoming;
        return Response('{"status":"accepted"}', 202);
      }),
    );

    await client.notify(
      recipientPubkey: recipientPubkey,
      relays: const ['wss://relay.example.net'],
      event: event(kind: giftWrapKind),
      email: email,
    );

    final body = jsonDecode(request.body) as Map<String, dynamic>;
    expect(request.headers['authorization'], 'Bearer secret');
    expect(body['recipientPubkey'], recipientPubkey);
    expect(body['relays'], ['wss://relay.example.net']);
    expect(body['event']['kind'], giftWrapKind);
    expect(body['event'], isNot(contains('content')));
    expect(body['event'], isNot(contains('sig')));
    expect(body['email'], {
      'from': {'address': 'alice@example.net', 'name': 'Alice'},
      'subject': 'Hello',
      'preview': 'Short plaintext preview',
    });
  });

  test('sends a public email event with content and sig', () async {
    late Request request;
    final client = InboundNotificationClient(
      url: url,
      token: 'secret',
      client: MockClient((incoming) async {
        request = incoming;
        return Response('{"status":"accepted"}', 202);
      }),
    );

    await client.notify(
      recipientPubkey: recipientPubkey,
      relays: const ['wss://relay.example.net'],
      event: event(kind: 1301),
      email: email,
    );

    final body = jsonDecode(request.body) as Map<String, dynamic>;
    expect(body['event']['content'], 'secret content');
    expect(body['event']['sig'], 'event-signature');
  });

  test('throws when the API does not accept the notification', () async {
    final client = InboundNotificationClient(
      url: url,
      token: 'secret',
      client: MockClient((_) async => Response('unavailable', 503)),
    );

    await expectLater(
      client.notify(
        recipientPubkey: recipientPubkey,
        relays: const ['wss://relay.example.net'],
        event: event(kind: giftWrapKind),
        email: email,
      ),
      throwsA(isA<InboundNotificationException>()),
    );
  });
}
