import 'package:enough_mail_plus/enough_mail.dart';

// The trace header is only prepended to the raw text: editing the parsed
// message re-renders every header and breaks the sender's DKIM signature.
MimeMessage traceMimeForRecipient({
  required String rawMime,
  required String originalRecipient,
}) {
  final eol = rawMime.contains('\r\n') ? '\r\n' : '\n';
  final recipient = originalRecipient.replaceAll(RegExp(r'[\r\n]'), '').trim();
  return MimeMessage.parseFromText(
    'X-Original-Recipient: $recipient$eol$rawMime',
  );
}

List<String> recipientsFromMime(MimeMessage message) {
  return message.recipients.map((recipient) => recipient.email).toList();
}
