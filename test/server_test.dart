import 'package:enough_mail_plus/enough_mail.dart';
import 'package:http/http.dart';
import 'package:ndk/ndk.dart';
import 'package:shelf/shelf_io.dart';
import 'package:test/test.dart';
import 'package:inbound_mail_webhook/inbound_mail_webhook.dart';

class FakeMailer implements MimeMailer {
  final sent = <MimeMessage>[];
  bool throwOnSend = false;

  @override
  Future<void> sendMime(
    MimeMessage message, {
    required String recipientPubkey,
    String? mailFrom,
  }) async {
    if (throwOnSend) throw MimeDeliveryException('boom');
    sent.add(message);
  }
}

void main() {
  final (_, pubkey) = const Bip340EventSignerFactory().generateKeyPair();
  late FakeMailer mailer;
  late Uri baseUri;
  late dynamic server;

  WebhookConfig config({String signingKey = '', int maxMimeBytes = 67108864}) {
    return WebhookConfig.fromEnv({
      'WEBHOOK_SIGNING_KEY': signingKey,
      'MAX_MIME_BYTES': '$maxMimeBytes',
    });
  }

  Future<void> start({
    String signingKey = '',
    int maxMimeBytes = 67108864,
  }) async {
    mailer = FakeMailer();
    final handler = createHandler(
      config: config(signingKey: signingKey, maxMimeBytes: maxMimeBytes),
      mailer: mailer,
      recipientResolver: RecipientResolver(
        lookupNip05: (identifier) async {
          if (identifier == 'alice@example.com') return pubkey;
          return null;
        },
      ),
      now: () =>
          DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000, isUtc: true),
    );
    server = await serve(handler, 'localhost', 0);
    baseUri = Uri.parse('http://localhost:${server.port}');
  }

  tearDown(() async {
    await server?.close(force: true);
  });

  test('healthz', () async {
    await start();
    final response = await get(baseUri.resolve('/healthz'));

    expect(response.statusCode, 200);
    expect(response.body, 'ok\n');
  });

  test('POST /mime accepts form-urlencoded body-mime', () async {
    await start();
    final response = await post(
      baseUri.resolve('/mime'),
      headers: {'content-type': 'application/x-www-form-urlencoded'},
      body: {
        'recipient': 'alice@example.com',
        'sender': 'sender@example.com',
        'body-mime':
            'From: Sender <sender@example.com>\r\n'
            'To: alice@example.com\r\n'
            'Subject: Hi\r\n'
            '\r\n'
            'Body\r\n',
      },
    );

    expect(response.statusCode, 200);
    expect(mailer.sent, hasLength(1));
    expect(mailer.sent.single.to!.single.email, 'alice@example.com');
    expect(
      mailer.sent.single.getHeaderValue('X-Original-Recipient'),
      'alice@example.com',
    );
  });

  test('POST /mime returns 406 when no recipient resolves', () async {
    await start();
    final response = await post(
      baseUri.resolve('/mime'),
      headers: {'content-type': 'application/x-www-form-urlencoded'},
      body: {
        'recipient': 'unknown@example.com',
        'sender': 'sender@example.com',
        'body-mime':
            'From: Sender <sender@example.com>\r\n'
            'To: unknown@example.com\r\n'
            'Subject: Hi\r\n'
            '\r\n'
            'Body\r\n',
      },
    );

    expect(response.statusCode, 406);
    expect(mailer.sent, isEmpty);
  });

  test('POST /mime returns 406 when body-mime exceeds limit', () async {
    await start(maxMimeBytes: 16);
    final response = await post(
      baseUri.resolve('/mime'),
      headers: {'content-type': 'application/x-www-form-urlencoded'},
      body: {
        'recipient': 'alice@example.com',
        'sender': 'sender@example.com',
        'body-mime':
            'From: Sender <sender@example.com>\r\n'
            'To: alice@example.com\r\n'
            'Subject: Hi\r\n'
            '\r\n'
            'Body\r\n',
      },
    );

    expect(response.statusCode, 406);
    expect(mailer.sent, isEmpty);
  });

  test('POST /mime returns 401 for invalid signature', () async {
    await start(signingKey: 'secret');
    final response = await post(
      baseUri.resolve('/mime'),
      headers: {'content-type': 'application/x-www-form-urlencoded'},
      body: {
        'recipient': 'alice@example.com',
        'sender': 'sender@example.com',
        'timestamp': '1700000000',
        'token': 'abc',
        'signature': 'bad',
        'body-mime':
            'From: Sender <sender@example.com>\r\n'
            'To: alice@example.com\r\n'
            'Subject: Hi\r\n'
            '\r\n'
            'Body\r\n',
      },
    );

    expect(response.statusCode, 401);
    expect(mailer.sent, isEmpty);
  });

  test('POST /mime returns 500 for mailer failures', () async {
    await start();
    mailer.throwOnSend = true;
    final response = await post(
      baseUri.resolve('/mime'),
      headers: {'content-type': 'application/x-www-form-urlencoded'},
      body: {
        'recipient': 'alice@example.com',
        'sender': 'sender@example.com',
        'body-mime':
            'From: Sender <sender@example.com>\r\n'
            'To: alice@example.com\r\n'
            'Subject: Hi\r\n'
            '\r\n'
            'Body\r\n',
      },
    );

    expect(response.statusCode, 500);
  });
}
