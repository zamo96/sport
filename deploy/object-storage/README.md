# Uploads bucket policy

`uploads-bucket-policy.json` is the access policy of the Yandex Object Storage bucket
`sportsearch-uploads` (folder `sportsearch`), applied on 2026-09-27.

- Anyone may read files in the public folders: `avatars`, `profile-media`, `courts`,
  `game-reports`, `personal-activities`. The site and the apps link to them directly.
- `chat-media` is not in that list, so a direct link to a chat photo answers 403. The app
  serves chat photos itself after checking that the viewer is in the chat.
- The app's service account `sport-search-postbox` (`aje1m9cejch35rchffe2`, the owner of
  the static key in `S3_ACCESS_KEY_ID`) and the owner's account (`aje9mci2ahto3u5g2n9s`)
  have full access.

In Object Storage a request that matches no `Allow` rule falls back to the object's own
ACL, and our objects have none, so anything not listed here is closed. A new public
folder has to be added to the first statement, or its files stop opening.

Apply (needs `yc init` with the owner's account; the app's key cannot change policies):

```bash
yc storage bucket update --name sportsearch-uploads --policy-from-file deploy/object-storage/uploads-bucket-policy.json
```

Check from outside: a chat photo URL must answer 403, an avatar URL 200.

To undo, delete the policy in the console (bucket → Security → Access policy) or apply
a policy whose first statement allows `s3:GetObject` on `arn:aws:s3:::sportsearch-uploads/*`.
