import 'package:enough_mail_plus/enough_mail.dart';
import 'package:ndk/ndk.dart';

MimeMessage rewriteMimeForRecipient({
  required String rawMime,
  required String recipientPubkey,
  required String originalRecipient,
  String? mailFrom,
}) {
  final message = MimeMessage.parseFromText(rawMime);
  final npubAddress = '${Nip19.encodePubKey(recipientPubkey)}@nostr';

  message.to = [MailAddress(null, npubAddress)];
  message.cc = null;
  message.bcc = null;

  message
    ..setHeader('To', npubAddress)
    ..removeHeader('Cc')
    ..removeHeader('Bcc')
    ..setHeader('X-Original-Recipient', originalRecipient);

  if (mailFrom != null && mailFrom.trim().isNotEmpty) {
    message.setHeader('X-Haraka-Mail-From', mailFrom.trim());
  }

  return message;
}

List<String> recipientsFromMime(MimeMessage message) {
  return message.recipients.map((recipient) => recipient.email).toList();
}
