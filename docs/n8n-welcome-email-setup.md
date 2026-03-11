# Monk Welcome Email via n8n

This setup uses Monk's `WelcomeEmailService` webhook payload and sends one welcome email per user.

## 1) Import the n8n workflow

1. In n8n, go to **Workflows**.
2. Choose **Import from file**.
3. Import:
`/Users/gabrielberezovsky/Documents/Projects/Monk/docs/n8n-monk-welcome-workflow.json`
4. Open the node **Send Welcome Email** and attach your Gmail credentials.
5. Save and activate the workflow.

## 2) Get your production webhook URL

After activation, copy the **Production URL** from the **Webhook** node.

It will look like:
`https://<your-n8n-domain>/webhook/monk-welcome`

## 3) Configure Monk

Set this URL in:
- [Info.plist](/Users/gabrielberezovsky/Documents/Projects/Monk/Monk/Info.plist) key `WELCOME_WEBHOOK_URL`, or
- runtime override in UserDefaults key `welcome.webhook.url` for testing.

Example plist value:
`https://<your-n8n-domain>/webhook/monk-welcome`

## 4) Payload Monk sends

`WelcomeEmailService` sends JSON:

```json
{
  "userId": "string",
  "email": "string",
  "firstName": "string|null",
  "provider": "apple|google|password|restored",
  "isFirstSeenOnDevice": true,
  "signedInAt": "2026-03-02T10:00:00Z",
  "appVersion": "1.0 (1)",
  "platform": "ios"
}
```

## 5) Workflow behavior

- Validates payload has `userId` and an email-like value.
- Dedupe uses n8n workflow static storage (`sentUsers`) keyed by `userId` (fallback email).
- Sends welcome email only once per key.
- Returns HTTP JSON:
  - `200 { ok: true, sent: true, ... }` when sent
  - `200 { ok: true, sent: false, reason: ... }` when skipped
  - `400 { ok: false, sent: false, reason: ... }` when invalid payload

## 6) Notes

- If you reset n8n workflow static data, dedupe history is lost.
- For stronger dedupe across workflow resets, replace static-data dedupe with a persistent store (Postgres, Redis, Airtable, etc.).
