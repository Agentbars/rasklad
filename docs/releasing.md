# Releasing

A `v*` tag runs `.github/workflows/release.yml` on macOS 26. It:

1. imports the **Rasklad Release Signing** certificate (self-signed, valid until 2056) from
   secrets into a temporary keychain;
2. builds with `VERSION=<tag without v> SIGN_IDENTITY="Rasklad Release Signing" ./build.sh`
   (`CFBundleShortVersionString` and `CFBundleVersion` both get the version, Sparkle compares
   `CFBundleVersion`) and runs the tests;
3. zips the app (`Rasklad-vX.Y.Z.zip` + `.sha256`);
4. writes `appcast.xml` with `scripts/make-appcast.sh`: one item pointing at that zip, with the
   EdDSA signature and length from Sparkle's `sign_update`;
5. publishes the GitHub release with the zip, the checksum and `appcast.xml`.

The app reads `SUFeedURL` = `https://github.com/Agentbars/rasklad/releases/latest/download/appcast.xml`,
so the newest (non-draft, non-prerelease) release always serves the current appcast.

The Homebrew cask lives in [Agentbars/homebrew-tap](https://github.com/Agentbars/homebrew-tap).
Its own workflow checks the latest release every 3 hours and bumps `version` and `sha256`
(Actions → Update Rasklad cask → Run workflow to do it right away). No cross-repo token needed.

## Why the same certificate every time

macOS ties Accessibility and Input Monitoring permissions to the app's designated requirement:
`identifier "local.rasklad" and certificate root = H"5f1e6d5d569163d3edba4ffff07683c8c0bcae15"`.
Same certificate → same requirement → permissions survive updates. Ad-hoc signatures change
with every build, which is why releases up to 0.2.0 lost permissions on every update.

Local builds use a different certificate (`Rasklad Local Signing`), so switching between a local
build and a release build on the same Mac asks for permissions again.

## Secrets (Agentbars/rasklad → Settings → Secrets → Actions)

| Secret | What |
| --- | --- |
| `RELEASE_SIGNING_P12_BASE64` | `release.p12` (certificate + private key), base64 |
| `RELEASE_SIGNING_P12_PASSWORD` | its password |
| `SPARKLE_ED_PRIVATE_KEY` | Sparkle EdDSA private key (public one is `SUPublicEDKey` in Info.plist) |

The originals are in `~/.rasklad-release` on Pavel's Mac (not in git); the EdDSA key is also in
the login keychain (`generate_keys --account rasklad -p` prints the public key). Back that folder
up. Upload or re-upload all three with:

```bash
scripts/set-release-secrets.sh
```

If the certificate is lost, a new one works, but every user re-grants permissions once.
If the EdDSA key is lost, installed copies reject every new update: users have to install the
next version by hand (brew or zip). Rotate keys only while the old one still exists: ship a
release with the new `SUPublicEDKey`, signed with the old key.

## Plan for the next release (0.3.0, first with Sparkle)

0. Secrets are set (`gh secret list -R Agentbars/rasklad` shows all three), otherwise
   run `scripts/set-release-secrets.sh`.
1. Merge the Sparkle branch into `main`, CI green.
2. `git tag v0.3.0 && git push origin v0.3.0`; check the release has the zip, `.sha256` and
   `appcast.xml`, and that the log of "Build and test" shows the `certificate root` requirement above.
3. Check the feed: `curl -sL https://github.com/Agentbars/rasklad/releases/latest/download/appcast.xml`.
4. Wait for the tap bump (or run it by hand), then
   `brew upgrade --cask rasklad` on a test Mac.
5. Users on 0.1/0.2 have no updater: they update once by hand (brew upgrade or zip) and grant
   permissions once more, because the signature changes from ad-hoc to the release certificate.
   Mention this in the release notes.
6. 0.3.1 or later: verify a real Sparkle update from 0.3.0 (menu → «Проверить обновления…»)
   keeps the permissions. After that, add `auto_updates true` to the cask (with it, plain
   `brew upgrade` skips Rasklad, so adding it earlier would strand 0.2.0 users).
