# Yandex Object Storage Avatars

## What To Create In Yandex Cloud

1. Open `Object Storage`.
2. Create a bucket, for example `sportsearch-uploads`.
3. Keep the bucket in Yandex Cloud / Russia.
4. Allow public read access for avatar objects, or configure an equivalent public access rule for the `avatars/` prefix.
5. Create a service account for runtime storage access, for example `sportsearch-storage`.
6. Grant it permission to upload objects to the bucket.
7. Create a static access key for that service account.
8. Store the key ID and secret in `.env.production` on the VM.

## Production Env

```env
UPLOADS_PROVIDER=s3
S3_ENDPOINT=https://storage.yandexcloud.net
S3_REGION=ru-central1
S3_BUCKET=sportsearch-uploads
S3_ACCESS_KEY_ID=<static_key_id>
S3_SECRET_ACCESS_KEY=<static_key_secret>
S3_FORCE_PATH_STYLE=true
S3_PUBLIC_BASE_URL=https://storage.yandexcloud.net/sportsearch-uploads
```

The app stores avatar URLs in the database. With the default public base URL, an uploaded avatar will look like:

```text
https://storage.yandexcloud.net/sportsearch-uploads/avatars/<user-id>/<uuid>.jpg
```

## Local Env

```env
UPLOADS_PROVIDER=local
```

Local mode keeps writing files to `public/uploads`.

## Limits

- Accepted avatar types: JPG, PNG, WEBP, GIF.
- Max file size: 5 MB.
- Uploaded objects get long-lived immutable cache headers.
