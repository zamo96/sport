# Yandex Cloud Postbox OTP

## What To Create In Yandex Cloud

1. Open `Yandex Cloud Postbox`.
2. Create and verify a sender address or domain.
3. Add the DNS records that Postbox shows for verification, DKIM, SPF, and DMARC.
4. Create a service account in the same folder as the Postbox address.
5. Assign the service account the `postbox.sender` role.
6. Create an API key for that service account with the `yc.postbox.send` scope.
7. Store the API key ID and secret in production env variables.

Yandex Cloud Postbox supports SMTP on `postbox.cloud.yandex.net`, port `587` with STARTTLS or port `465` with SMTPS. For SMTP with an API key, the username is the API key ID and the password is the secret part of the API key.

## Production Env

```env
EMAIL_PROVIDER=smtp
EMAIL_FROM=TennisSearch <no-reply@example.ru>
SMTP_HOST=postbox.cloud.yandex.net
SMTP_PORT=587
SMTP_SECURE=false
SMTP_USER=<api_key_id>
SMTP_PASSWORD=<api_key_secret>
```

Use `SMTP_SECURE=true` only with port `465`.

## Local Env

```env
EMAIL_PROVIDER=console
```

In console mode, OTP codes are printed to application logs and no email is sent.

## Smoke Test

After deployment, request a code from the auth screen and inspect the app logs:

```bash
docker compose --env-file .env.production -f docker-compose.prod.yml logs -f app
```

If Postbox rejects the email, common causes are:

- sender address is not verified
- service account does not have `postbox.sender`
- API key does not have the `yc.postbox.send` scope
- `EMAIL_FROM` does not match an allowed sender
- DNS verification records have not propagated yet
