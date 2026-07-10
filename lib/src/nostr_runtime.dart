import 'dart:io';

import 'package:bip340/bip340.dart' as bip340;
import 'package:blossom_cache/blossom_cache.dart';
import 'package:enough_mail_plus/enough_mail.dart';
import 'package:idb_sqflite/idb_sqflite.dart';
import 'package:ndk/entities.dart' as ndk_entities;
import 'package:ndk/ndk.dart';
import 'package:nostr_mail/nostr_mail.dart';
import 'package:path/path.dart' as p;
import 'package:sembast/sembast_io.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'config.dart';
import 'inbound_notification.dart';
import 'mime_delivery.dart';

class NostrRuntime implements MimeMailer {
  NostrRuntime._({
    required this.ndk,
    required this.client,
    this.notificationClient,
  });

  final Ndk ndk;
  final NostrMailClient client;
  final InboundNotificationClient? notificationClient;

  static Future<NostrRuntime> create(WebhookConfig config) async {
    final privateKey = _privateKeyHex(config.nostrPrivateKey);
    final publicKey = bip340.getPublicKey(privateKey);

    final dataDir = Directory(config.dataDir);
    await dataDir.create(recursive: true);

    final ndk = Ndk(
      config.bootstrapNostrRelays.isEmpty
          ? NdkConfig(
              eventVerifier: Bip340EventVerifier(),
              cache: MemCacheManager(),
              fetchedRangesEnabled: true,
            )
          : NdkConfig(
              bootstrapRelays: config.bootstrapNostrRelays,
              eventVerifier: Bip340EventVerifier(),
              cache: MemCacheManager(),
              fetchedRangesEnabled: true,
            ),
    );
    ndk.accounts.loginPrivateKey(pubkey: publicKey, privkey: privateKey);

    final db = await databaseFactoryIo.openDatabase(
      p.join(dataDir.path, 'nostr_mail.db'),
    );
    sqfliteFfiInit();
    final blossomCache = await IdbBlossomCache.open(
      factory: getIdbFactorySqflite(databaseFactoryFfi),
      dbName: p.join(dataDir.path, 'inbound_mail_webhook_blossom.db'),
    );
    final notificationUrl = config.inboundNotificationUrl;
    final notificationToken = config.inboundNotificationToken;
    if ((notificationUrl == null) != (notificationToken == null)) {
      throw StateError(
        'INBOUND_NOTIFICATION_URL and INBOUND_NOTIFICATION_TOKEN '
        'must be configured together',
      );
    }
    final notificationClient =
        notificationUrl != null && notificationToken != null
        ? InboundNotificationClient(
            url: notificationUrl,
            token: notificationToken,
          )
        : null;

    final client = await NostrMailClient.create(
      ndk: ndk,
      db: db,
      blossomCache: blossomCache,
      defaultDmRelays: config.defaultDmRelays.isEmpty
          ? null
          : config.defaultDmRelays,
      defaultBlossomServers: config.defaultBlossomServers.isEmpty
          ? null
          : config.defaultBlossomServers,
    );

    return NostrRuntime._(
      ndk: ndk,
      client: client,
      notificationClient: notificationClient,
    );
  }

  Future<String?> resolveNip05(String identifier) async {
    final result = await ndk.nip05.resolve(identifier);
    return switch (result) {
      ndk_entities.Nip05Found(:final data) => data.pubKey,
      ndk_entities.Nip05NotFound() ||
      ndk_entities.Nip05ResolveNetworkError() ||
      ndk_entities.Nip05ResolveInvalidResponse() => null,
    };
  }

  @override
  Future<void> sendMime(
    MimeMessage message, {
    required String recipientPubkey,
    String? mailFrom,
  }) {
    final email = EmailNotification.fromMime(message);
    return client.sendMime(
      message,
      to: [NostrRecipient.fromPubkey(recipientPubkey)],
      keepCopy: false,
      mailFrom: mailFrom,
      beforePublish: notificationClient == null
          ? null
          : (event, relays) async {
              await notifyInboundBestEffort(
                notifier: notificationClient!,
                recipientPubkey: recipientPubkey,
                relays: relays,
                event: event,
                email: email,
                onError: (error, stackTrace) {
                  stderr.writeln('inbound notification failed: $error');
                  stderr.writeln(stackTrace);
                },
              );
            },
    );
  }

  Future<void> dispose() async {
    await client.dispose();
    notificationClient?.close();
    await ndk.destroy();
  }
}

String _privateKeyHex(String? configured) {
  if (configured == null || configured.trim().isEmpty) {
    throw StateError('NOSTR_PRIVATE_KEY is required');
  }

  final trimmed = configured.trim();
  if (RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(trimmed)) {
    return trimmed.toLowerCase();
  }

  if (trimmed.toLowerCase().startsWith('nsec1')) {
    final decoded = Nip19.decode(trimmed);
    if (RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(decoded)) {
      return decoded.toLowerCase();
    }
  }

  throw StateError('NOSTR_PRIVATE_KEY must be a 64-char hex key or nsec');
}
