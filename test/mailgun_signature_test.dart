import 'package:inbound_mail_webhook/inbound_mail_webhook.dart';
import 'package:test/test.dart';

void main() {
  test('mailgunSignature matches timestamp+token HMAC', () {
    expect(
      mailgunSignature(
        signingKey: 'secret',
        timestamp: '1700000000',
        token: 'abc',
      ),
      '0378e7a22896ffb8263c50306768eb8f8d212f9426ca6b0e9dc561e301655398',
    );
  });

  test('verifyMailgunSignature accepts valid fields', () {
    final fields = {
      'timestamp': '1700000000',
      'token': 'abc',
      'signature': mailgunSignature(
        signingKey: 'secret',
        timestamp: '1700000000',
        token: 'abc',
      ),
    };

    expect(
      () => verifyMailgunSignature(
        fields: fields,
        signingKey: 'secret',
        tolerance: const Duration(minutes: 15),
        now: DateTime.fromMillisecondsSinceEpoch(
          1700000000 * 1000,
          isUtc: true,
        ),
      ),
      returnsNormally,
    );
  });

  test('verifyMailgunSignature rejects expired timestamp', () {
    final fields = {
      'timestamp': '1700000000',
      'token': 'abc',
      'signature': mailgunSignature(
        signingKey: 'secret',
        timestamp: '1700000000',
        token: 'abc',
      ),
    };

    expect(
      () => verifyMailgunSignature(
        fields: fields,
        signingKey: 'secret',
        tolerance: const Duration(minutes: 15),
        now: DateTime.fromMillisecondsSinceEpoch(
          1700003600 * 1000,
          isUtc: true,
        ),
      ),
      throwsA(isA<WebhookSignatureException>()),
    );
  });

  test('verifyMailgunSignature rejects missing or invalid signature', () {
    expect(
      () => verifyMailgunSignature(
        fields: const {'timestamp': '1700000000', 'token': 'abc'},
        signingKey: 'secret',
        tolerance: const Duration(minutes: 15),
        now: DateTime.fromMillisecondsSinceEpoch(
          1700000000 * 1000,
          isUtc: true,
        ),
      ),
      throwsA(isA<WebhookSignatureException>()),
    );

    expect(
      () => verifyMailgunSignature(
        fields: const {
          'timestamp': '1700000000',
          'token': 'abc',
          'signature': 'bad',
        },
        signingKey: 'secret',
        tolerance: const Duration(minutes: 15),
        now: DateTime.fromMillisecondsSinceEpoch(
          1700000000 * 1000,
          isUtc: true,
        ),
      ),
      throwsA(isA<WebhookSignatureException>()),
    );
  });
}
