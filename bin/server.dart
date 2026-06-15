import 'dart:io';

import 'package:shelf/shelf_io.dart';

import 'package:inbound_mail_webhook/inbound_mail_webhook.dart';

void main(List<String> args) async {
  final config = WebhookConfig.fromEnv(Platform.environment);
  final runtime = await NostrRuntime.create(config);
  final handler = createHandler(
    config: config,
    mailer: runtime,
    recipientResolver: RecipientResolver(lookupNip05: runtime.resolveNip05),
  );
  final ip = InternetAddress.anyIPv4;

  final server = await serve(handler, ip, config.port);
  print('Server listening on port ${server.port}');
}
