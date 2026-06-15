import 'package:enough_mail_plus/enough_mail.dart';
import 'package:ndk/ndk.dart';

typedef Nip05Lookup = Future<String?> Function(String identifier);

class ResolvedRecipient {
  ResolvedRecipient({required this.original, required this.pubkey});

  final String original;
  final String pubkey;
}

class RecipientResolver {
  RecipientResolver({required this.lookupNip05});

  final Nip05Lookup lookupNip05;

  Future<List<ResolvedRecipient>> resolveAll(Iterable<String> addresses) async {
    final resolved = <ResolvedRecipient>[];
    final seenPubkeys = <String>{};

    for (final address in addresses) {
      final trimmed = address.trim();
      if (trimmed.isEmpty) continue;

      final pubkey = await resolveOne(trimmed);
      if (pubkey == null || !seenPubkeys.add(pubkey)) continue;
      resolved.add(ResolvedRecipient(original: trimmed, pubkey: pubkey));
    }

    return resolved;
  }

  Future<String?> resolveOne(String address) async {
    final email = _extractEmail(address);
    final localPart = _localPart(email);

    final npubPubkey = _decodeNpub(localPart);
    if (npubPubkey != null) return npubPubkey;

    final hexPubkey = _decodeHexPubkey(localPart);
    if (hexPubkey != null) return hexPubkey;

    final base36Pubkey = _decodeBase36Pubkey(localPart);
    if (base36Pubkey != null) return base36Pubkey;

    if (email.contains('@')) {
      return lookupNip05(email.toLowerCase());
    }

    return null;
  }
}

String _extractEmail(String value) {
  try {
    return MailAddress.parse(value).email.trim();
  } catch (_) {
    final match = RegExp(r'<([^>]+)>').firstMatch(value);
    return (match?.group(1) ?? value).trim();
  }
}

String _localPart(String email) {
  final at = email.indexOf('@');
  return (at == -1 ? email : email.substring(0, at)).trim();
}

String? _decodeNpub(String localPart) {
  if (!localPart.toLowerCase().startsWith('npub1')) return null;
  final decoded = Nip19.decode(localPart);
  return _decodeHexPubkey(decoded);
}

String? _decodeHexPubkey(String value) {
  if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(value)) return null;
  return value.toLowerCase();
}

String? _decodeBase36Pubkey(String localPart) {
  if (!RegExp(r'^[0-9a-zA-Z]{48,50}$').hasMatch(localPart)) return null;

  final parsed = BigInt.tryParse(localPart.toLowerCase(), radix: 36);
  if (parsed == null || parsed == BigInt.zero) return null;

  final hex = parsed.toRadixString(16);
  if (hex.length > 64) return null;

  return hex.padLeft(64, '0');
}
