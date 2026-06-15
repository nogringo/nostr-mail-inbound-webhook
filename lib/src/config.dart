class WebhookConfig {
  WebhookConfig({
    required this.port,
    required this.nostrPrivateKey,
    required this.webhookSigningKey,
    required this.signatureTolerance,
    required this.dataDir,
    required this.bootstrapNostrRelays,
    required this.defaultDmRelays,
    required this.defaultBlossomServers,
    required this.maxMimeBytes,
  });

  final int port;
  final String? nostrPrivateKey;
  final String webhookSigningKey;
  final Duration signatureTolerance;
  final String dataDir;
  final List<String> bootstrapNostrRelays;
  final List<String> defaultDmRelays;
  final List<String> defaultBlossomServers;
  final int maxMimeBytes;

  bool get requiresSignature => webhookSigningKey.isNotEmpty;

  factory WebhookConfig.fromEnv(Map<String, String> env) {
    return WebhookConfig(
      port: _parsePositiveInt(env['PORT'], 8080),
      nostrPrivateKey: _blankToNull(env['NOSTR_PRIVATE_KEY']),
      webhookSigningKey: env['WEBHOOK_SIGNING_KEY'] ?? '',
      signatureTolerance: Duration(
        seconds: _parsePositiveInt(env['SIGNATURE_TOLERANCE_SECONDS'], 900),
      ),
      dataDir: env['DATA_DIR']?.trim().isNotEmpty == true
          ? env['DATA_DIR']!.trim()
          : '.data',
      bootstrapNostrRelays: _parseList(
        env['BOOTSTRAP_NOSTR_RELAYS'] ?? env['NOSTR_RELAYS'],
      ),
      defaultDmRelays: _parseList(env['DEFAULT_DM_RELAYS']),
      defaultBlossomServers: _parseList(env['DEFAULT_BLOSSOM_SERVERS']),
      maxMimeBytes: _parsePositiveInt(env['MAX_MIME_BYTES'], 67108864),
    );
  }
}

String? _blankToNull(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return trimmed;
}

int _parsePositiveInt(String? value, int defaultValue) {
  if (value == null || value.trim().isEmpty) return defaultValue;
  final parsed = int.tryParse(value);
  if (parsed == null || parsed <= 0) return defaultValue;
  return parsed;
}

List<String> _parseList(String? value) {
  if (value == null || value.trim().isEmpty) return const [];
  return value
      .split(',')
      .map((entry) => entry.trim())
      .where((entry) => entry.isNotEmpty)
      .toList(growable: false);
}
