# OSS upload

OSS upload sends one or more files to Alibaba Cloud Object Storage Service, then copies their links
to the clipboard. **Upload to OSS** opens an in-palette screen with Finder paste, a multi-file picker,
progress and searchable upload history. **Settings → OSS Upload** owns connection details, Keychain
credentials, object naming, and the access lifetime of generated links.

## Invariants

- **Secrets live only in the login Keychain.** `UserDefaults` holds the endpoint, region, bucket,
  prefix, link access and expiry; it never holds an AccessKey Secret. The Keychain service includes
  the bundle identifier so Debug and installed channels cannot share credentials.
- **Every request uses OSS V4 signing.** Upload URLs expire after 15 minutes; private download links
  use the selected lifetime and are clamped to OSS's seven-day limit.
- **Networking is feature-private and uncached.** `OSSUploadService` owns an ephemeral `URLSession`
  with no URL cache. It never uses `URLSession.shared`.
- **`Model/` stays Foundation-only.** Configuration validation, credential values and object-key
  generation compile in `oss-upload-test` without AppKit or SwiftUI.
- **The coordinator is the only user-action funnel.** The palette reaches `OSSUploadCoordinator`,
  which validates configuration and credentials before accepting pasted or selected files, owns batch
  progress, copies successful links and presents failures.
- **History is local metadata, never another copy of the object.** `OSSUploadHistoryStore` keeps at
  most 200 successful uploads in the per-channel cache, including each link's configured expiry.

## Configuration and credentials

`OSSSettingsStore`, owned by `AppCore`, persists one `OSSConfiguration` as JSON. Validation requires
an HTTPS endpoint with no path, a lowercase OSS region, and a 3–63 character lowercase bucket name.
The endpoint is the public regional endpoint without a bucket name; validation constructs the
virtual-hosted authority by prepending the bucket when necessary.

`OSSCredentialStore` writes one JSON-encoded `OSSCredentials` value as a generic-password Keychain
item accessible while the Mac is unlocked. Updating credentials with a blank secret field preserves
the existing secret. Removal goes through Tinycast's own confirmation dialog.

Use a RAM user scoped to the target bucket and only the operations this feature needs:
`oss:PutObject` for upload and `oss:GetObject` for signed downloads. A public link does not change
bucket policy; it is useful only when the object is already publicly readable.

## Object keys and limits

Objects are written as:

```text
<prefix>/YYYY/MM/DD/<8-character UUID prefix>-<original filename>
```

The date is UTC, empty or duplicate prefix separators are removed, and the random prefix avoids
overwriting a same-named file. The original filename is retained and percent-encoded only when the
request URL is built. Direct `PutObject` uploads are limited to regular files no larger than 5 GB;
larger files need multipart upload, which this feature does not silently substitute.

## Signing and upload flow

`OSSV4Signer` produces virtual-hosted presigned URLs using `OSS4-HMAC-SHA256`, the `host` additional
header and `UNSIGNED-PAYLOAD`. Canonical signing still includes `/<bucket>/<object-key>`, while the
network URL is `https://<bucket>.<endpoint>/<object-key>`, as OSS V4 requires.

The signed-link lifetime is configured in **Settings → OSS Upload → Uploaded Objects** and is used
for every private download link generated after upload. The palette accepts Finder file URLs with
Command-V or its Paste button, and the file picker accepts multiple files. `OSSUploadCoordinator`
uploads them sequentially so the screen can name the current file and the service does not create an
unbounded set of file requests. Each successful result enters searchable history immediately, even
when a later upload fails. Return copies a history link, Command-Return opens it, and expired signed
links remain visible but are not copied or opened. At completion, successful links are copied
newline-separated only if the clipboard has not changed during the batch and the batch was not
cancelled. Otherwise the result card offers explicit copying without replacing newer clipboard data.

Pasted PNG or TIFF screenshots upload as PNG from memory without temporary files. Finder file URLs
take precedence over image representations. Byte progress comes from URLSession's upload delegate;
100% sent still waits for the server's successful response. Cancellation stops the current transfer
and queue, never deletes remote objects, and preserves confirmed successes in history. A cancelled
request may already have reached OSS, so the app does not claim a remote rollback.

The result card lists failures and can retry only failed, cancelled and unstarted items. Retry retains
the original destination, object date and identifier while signing each request with a fresh timestamp.
Credentials are read again from Keychain. Retry state, including screenshot bytes, lasts for the
current session until the next batch; it is not persisted. Search does not hide the transfer controls.

The transfer card fades in over 180 ms when switching between uploading and the result summary.
Outgoing controls disappear immediately, so cancelling and retrying never leave stale clickable buttons.
Byte updates and history selection remain immediate; Reduce Motion disables the card transition.

## Testing

`Tests/oss-upload-test.swift` covers normalization and rejection paths, deterministic object naming,
percent encoding, the expiration query, and an independent fixed HMAC-SHA256 signature fixture.
The real service needs an OSS bucket and intentionally has no network test in the local harness; run
the OSS upload section of the manual sweep in [`testing.md`](../testing.md) before shipping.
