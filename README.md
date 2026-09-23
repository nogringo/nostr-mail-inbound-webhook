# Haraka Mail Webhook to Nostr

Reusable Dart webhook that receives Haraka/Mailgun-style raw MIME payloads and
forwards inbound mail to Nostr with `nostr_mail`.

## Endpoints

- `GET /healthz`: health check, returns `ok`.
- `POST /mime`: accepts `application/x-www-form-urlencoded` payloads with
  `body-mime`, `recipient`, `sender`, `timestamp`, `token`, and `signature`.

`/mime` returns:

- `200` when at least one recipient was accepted for Nostr delivery.
- `401` when `WEBHOOK_SIGNING_KEY` is configured and the signature is invalid.
- `406` for invalid payloads, invalid MIME, or zero resolvable recipients.
- `500` for retryable Nostr delivery failures.

## Configuration

```sh
NOSTR_PRIVATE_KEY=nsec1... # or 64-char hex private key
WEBHOOK_SIGNING_KEY=change-me
PORT=8080
DATA_DIR=.data
```

Optional settings:

```sh
SIGNATURE_TOLERANCE_SECONDS=900
BOOTSTRAP_NOSTR_RELAYS=wss://relay.damus.io,wss://nos.lol
DEFAULT_DM_RELAYS=wss://relay.nmail.li,wss://auth.nostr1.com
DEFAULT_BLOSSOM_SERVERS=https://blossom.nmail.li
MAX_MIME_BYTES=67108864
INBOUND_NOTIFICATION_URL=https://api.example.com/inbound/notifications
INBOUND_NOTIFICATION_TOKEN=change-me
```

When the notification URL and token are configured, the webhook calls the
inbound notification API after each outgoing event and its destination relays
have been built, but before the event is queued for publication. Gift wrap
content and signatures are omitted from the notification; public email events
are sent in full. Notification delivery is best effort: failures are logged but
do not prevent the email from being sent to Nostr.

If `WEBHOOK_SIGNING_KEY` is set, signatures are verified like Mailgun:
`HMAC_SHA256(timestamp + token)`.

## Recipient Resolution

The webhook uses the Haraka `recipient` form field as the authoritative envelope
recipient list, split by commas. If it is missing, it falls back to the MIME
`To`, `Cc`, and `Bcc` headers.

For each recipient, the local-part before `@` is checked in this order:

1. `npub1...`
2. 64-character hex pubkey
3. base36 pubkey, only when the whole local-part is 48 to 50 alphanumeric chars
4. NIP-05 lookup using the full email address

NIP-05 lookups are signed with NIP-98 using `NOSTR_PRIVATE_KEY`, with a `u` tag
that includes the query. An nmail-api instance that lists the webhook pubkey in
`NIP05_PRIVATE_READERS` then also resolves private addresses. Other NIP-05
servers ignore the header and answer as usual.

Unresolved addresses are skipped. If none resolve, the webhook returns `406` so
Haraka can dead-letter the message.

## Running

With the published GHCR image:

```sh
cp .env.example .env
# Edit .env, especially NOSTR_PRIVATE_KEY and WEBHOOK_SIGNING_KEY.
docker compose up -d
```

## License

MIT
