import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:ndk/ndk.dart';

const nip98Kind = 27235;

/// Resolves NIP-05 identifiers with a NIP-98 signed request, so servers that
/// list the webhook pubkey as a private reader also return private identities.
class Nip05Resolver {
  Nip05Resolver({
    required this.signer,
    this.timeout = const Duration(seconds: 10),
    http.Client? client,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null;

  final EventSigner signer;
  final Duration timeout;
  final http.Client _client;
  final bool _ownsClient;

  Future<String?> resolve(String identifier) async {
    final parts = identifier.trim().toLowerCase().split('@');
    if (parts.length != 2 || parts.any((part) => part.isEmpty)) return null;
    final [name, domain] = parts;

    final url = Uri.https(domain, '/.well-known/nostr.json', {'name': name});
    final authorization = await _authorization(url);
    final abort = Completer<void>();
    final timer = Timer(timeout, abort.complete);
    // NIP-05: fetchers MUST ignore HTTP redirects.
    final request =
        http.AbortableRequest('GET', url, abortTrigger: abort.future)
          ..followRedirects = false
          ..headers['authorization'] = authorization;

    try {
      final response = await http.Response.fromStream(
        await _client.send(request),
      );
      if (response.statusCode != 200) return null;

      final body = jsonDecode(response.body);
      final pubkey = body is Map && body['names'] is Map
          ? body['names'][name]
          : null;
      if (pubkey is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(pubkey)) {
        return null;
      }
      return pubkey;
    } catch (_) {
      return null;
    } finally {
      timer.cancel();
    }
  }

  Future<String> _authorization(Uri url) async {
    final event = await signer.sign(
      Nip01Event(
        pubKey: signer.getPublicKey(),
        createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        kind: nip98Kind,
        tags: [
          ['u', url.toString()],
          ['method', 'GET'],
        ],
        content: '',
      ),
    );
    return 'Nostr ${Nip01EventModel.fromEntity(event).toBase64()}';
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}
