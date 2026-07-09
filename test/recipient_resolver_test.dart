import 'package:ndk/ndk.dart';
import 'package:test/test.dart';
import 'package:inbound_mail_webhook/inbound_mail_webhook.dart';

void main() {
  final (_, hexPubkey) = const Bip340EventSignerFactory().generateKeyPair();

  late RecipientResolver resolver;
  late List<String> nip05Lookups;

  setUp(() {
    nip05Lookups = [];
    resolver = RecipientResolver(
      lookupNip05: (identifier) async {
        nip05Lookups.add(identifier);
        if (identifier == 'alice@example.com') return hexPubkey;
        return null;
      },
    );
  });

  test('resolves npub local-part', () async {
    final npub = Nip19.encodePubKey(hexPubkey);
    final resolved = await resolver.resolveOne('$npub@example.com');

    expect(resolved, hexPubkey);
    expect(nip05Lookups, isEmpty);
  });

  test('resolves hex local-part', () async {
    final resolved = await resolver.resolveOne('${hexPubkey.toUpperCase()}@x');

    expect(resolved, hexPubkey);
    expect(nip05Lookups, isEmpty);
  });

  test('resolves base36 local-part', () async {
    final base36 = BigInt.parse(
      hexPubkey,
      radix: 16,
    ).toRadixString(36).padLeft(48, '0');
    expect(base36.length, inInclusiveRange(48, 50));

    final resolved = await resolver.resolveOne('$base36@example.com');

    expect(resolved, hexPubkey);
    expect(nip05Lookups, isEmpty);
  });

  test('falls back to NIP-05 and skips unresolved addresses', () async {
    expect(await resolver.resolveOne('Alice <alice@example.com>'), hexPubkey);
    expect(await resolver.resolveOne('bob@example.com'), isNull);
    expect(nip05Lookups, ['alice@example.com', 'bob@example.com']);
  });

  test('deduplicates resolved pubkeys', () async {
    final npub = Nip19.encodePubKey(hexPubkey);
    final resolved = await resolver.resolveAll([
      '$npub@example.com',
      '$hexPubkey@example.com',
      'alice@example.com',
    ]);

    expect(resolved, hasLength(1));
    expect(resolved.first.pubkey, hexPubkey);
  });
}
