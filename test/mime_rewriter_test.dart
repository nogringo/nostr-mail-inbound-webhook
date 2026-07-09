import 'package:ndk/ndk.dart';
import 'package:test/test.dart';
import 'package:inbound_mail_webhook/inbound_mail_webhook.dart';

void main() {
  test('rewrites MIME for one recipient without leaking other recipients', () {
    final (_, pubkey) = const Bip340EventSignerFactory().generateKeyPair();
    const rawMime =
        'From: Sender <sender@example.com>\r\n'
        'To: a@example.com, b@example.com\r\n'
        'Cc: c@example.com\r\n'
        'Bcc: d@example.com\r\n'
        'Subject: Hello\r\n'
        '\r\n'
        'Body\r\n';

    final message = rewriteMimeForRecipient(
      rawMime: rawMime,
      recipientPubkey: pubkey,
      originalRecipient: 'a@example.com',
      mailFrom: 'sender@example.com',
    );
    final rendered = message.renderMessage();

    expect(message.to!.single.email, '${Nip19.encodePubKey(pubkey)}@nostr');
    expect(message.cc, isEmpty);
    expect(message.bcc, isEmpty);
    expect(rendered, contains('To: ${Nip19.encodePubKey(pubkey)}@nostr'));
    expect(rendered, contains('X-Original-Recipient: a@example.com'));
    expect(rendered, contains('X-Haraka-Mail-From: sender@example.com'));
    expect(rendered, isNot(contains('b@example.com')));
    expect(rendered, isNot(contains('Cc:')));
    expect(rendered, isNot(contains('Bcc:')));
  });
}
