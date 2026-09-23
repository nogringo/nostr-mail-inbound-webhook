import 'dart:convert';

import 'package:http/http.dart';
import 'package:http/testing.dart';
import 'package:inbound_mail_webhook/src/nip05_resolver.dart';
import 'package:ndk/ndk.dart';
import 'package:test/test.dart';

void main() {
  final (privateKey, publicKey) = const Bip340EventSignerFactory()
      .generateKeyPair();
  final signer = Bip340EventSigner(
    privateKey: privateKey,
    publicKey: publicKey,
  );
  final alicePubkey = 'a' * 64;

  Nip05Resolver resolver(Response Function(Request request) handler) =>
      Nip05Resolver(
        signer: signer,
        client: MockClient((request) async => handler(request)),
      );

  test('signs the lookup with NIP-98 bound to the full URL', () async {
    late Request request;
    final pubkey = await resolver((incoming) {
      request = incoming;
      return Response(
        jsonEncode({
          'names': {'alice': alicePubkey},
        }),
        200,
      );
    }).resolve('Alice@Example.com');

    expect(pubkey, alicePubkey);
    expect(
      request.url.toString(),
      'https://example.com/.well-known/nostr.json?name=alice',
    );

    final auth = request.headers['authorization']!;
    expect(auth, startsWith('Nostr '));
    final event = Nip01EventModel.fromJson(
      jsonDecode(utf8.decode(base64Decode(auth.substring(6)))),
    );
    expect(event.kind, nip98Kind);
    expect(event.pubKey, publicKey);
    expect(event.getFirstTag('u'), request.url.toString());
    expect(event.getFirstTag('method'), 'GET');
    expect(await Bip340EventVerifier().verify(event), isTrue);
  });

  test('returns null for unknown names and invalid responses', () async {
    expect(
      await resolver(
        (_) => Response('{"names":{},"relays":{}}', 200),
      ).resolve('alice@example.com'),
      isNull,
    );
    expect(
      await resolver((_) => Response('nope', 200)).resolve('alice@example.com'),
      isNull,
    );
    expect(
      await resolver((_) => Response('', 302)).resolve('alice@example.com'),
      isNull,
    );
    expect(
      await resolver(
        (_) => Response('{"names":{"alice":"not-a-pubkey"}}', 200),
      ).resolve('alice@example.com'),
      isNull,
    );
  });

  test('aborts the request when the server does not answer in time', () async {
    var aborted = false;
    final resolver = Nip05Resolver(
      signer: signer,
      timeout: const Duration(milliseconds: 10),
      // Unlike MockClient, the streaming handler receives the original request.
      client: MockClient.streaming((request, _) async {
        await (request as Abortable).abortTrigger;
        aborted = true;
        throw RequestAbortedException(request.url);
      }),
    );

    expect(await resolver.resolve('alice@example.com'), isNull);
    expect(aborted, isTrue);
  });
}
