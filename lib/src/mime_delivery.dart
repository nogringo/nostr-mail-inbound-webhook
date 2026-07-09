import 'package:enough_mail_plus/enough_mail.dart';

abstract interface class MimeMailer {
  Future<void> sendMime(
    MimeMessage message, {
    required String recipientPubkey,
    String? mailFrom,
  });
}

class MimeDeliveryException implements Exception {
  MimeDeliveryException(this.message);

  final String message;

  @override
  String toString() => message;
}
