import 'package:test/test.dart';
import 'package:inbound_mail_webhook/inbound_mail_webhook.dart';

void main() {
  const rawMime =
      'DKIM-Signature: v=1; a=rsa-sha256; c=simple/simple; d=example.com;\r\n'
      ' s=sel; h=from : to : cc : subject;\r\n'
      ' bh=y7rbrrz3fS9cxJYT6o03Eube0HsdpKy2EdU8vbVrtmM=; b=abc\r\n'
      'From: Sender <sender@example.com>\r\n'
      'To: a@example.com, b@example.com\r\n'
      'Cc: c@example.com\r\n'
      'Subject: Hello\r\n'
      '\r\n'
      'Body\r\n';

  test(
    'prepends the trace header and keeps the original MIME byte for byte',
    () {
      final message = traceMimeForRecipient(
        rawMime: rawMime,
        originalRecipient: 'a@example.com',
      );

      expect(
        message.renderMessage(),
        'X-Original-Recipient: a@example.com\r\n$rawMime',
      );
    },
  );

  test('strips line breaks from the original recipient', () {
    final message = traceMimeForRecipient(
      rawMime: rawMime,
      originalRecipient: 'a@example.com\r\nBcc: evil@example.com',
    );

    expect(message.getHeaderValue('Bcc'), isNull);
    expect(
      message.getHeaderValue('X-Original-Recipient'),
      'a@example.comBcc: evil@example.com',
    );
  });
}
