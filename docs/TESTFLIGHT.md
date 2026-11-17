# GitHub Actions: iOS / TestFlight

The **iOS TestFlight** workflow runs on a GitHub-hosted Mac; you do not need to
own a Mac. It exports a Godot Xcode project, archives it, and can export and
upload a signed IPA to App Store Connect. The run is manual and does not submit
for App Review or assign testers. Apple processes an uploaded build before it
appears in TestFlight; external testing may require Beta App Review.

**Status:** A macOS 26 / Xcode 26.6 run successfully archived, cloud-signed,
and uploaded version 1.0 build 1 to App Store Connect. Apple processing and
physical iOS device testing are separate; successful upload does not establish
that the build is available to testers.

## Recommended: cloud signing, no personal Mac

1. Have an active Apple Developer Program membership and an app record in App
   Store Connect with a registered, explicit bundle ID.
2. In [App Store Connect → Users and Access → Integrations → App Store Connect API](https://appstoreconnect.apple.com/access/integrations/api),
   enable API access if needed and create a **team API key** with permissions
   suitable for cloud-managed distribution signing and uploads. Apple states
   that Admin or Account Holder can cloud-sign by default; use an appropriately
   authorized key and check your team's access settings. Note the **Key ID** and
   **Issuer ID**, and download its `.p8` private key (Apple permits only one
   download). Do not share the private key or Apple password in chat.
3. In the GitHub repository's **Settings → Environments → testflight**, add
   these **environment variables**:

   | Name | Value |
   | --- | --- |
   | `APPLE_TEAM_ID` | 10-character Apple Developer team ID. |
   | `IOS_BUNDLE_ID` | Exact bundle ID in your App Store Connect app record. |
   | `IOS_VERSION` | Marketing version, e.g. `1.0`; already set to `1.0`. |

4. In the same environment, add these **environment secrets**:

   | Name | Value |
   | --- | --- |
   | `ASC_KEY_ID` | App Store Connect API key ID. |
   | `ASC_ISSUER_ID` | App Store Connect API issuer ID. |
   | `ASC_PRIVATE_KEY_BASE64` | Base64-encoded contents of the `.p8` file. |

   To prepare the Base64 value **on Windows**, open PowerShell and run:

   ```powershell
   [Convert]::ToBase64String([IO.File]::ReadAllBytes("C:\path\to\AuthKey_KEYID.p8")) | Set-Clipboard
   ```

   Paste it directly into the `ASC_PRIVATE_KEY_BASE64` GitHub secret, then clear
   your clipboard. Do not post it in chat or commit the `.p8` file. On macOS,
   `base64 -i /path/to/AuthKey_KEYID.p8 | pbcopy` does the equivalent.

Cloud signing uses an unsigned Xcode archive and asks Xcode, authenticated with
the API key, to export with automatic signing. Apple may create or update
profiles and cloud signing assets. It depends on Apple account permissions and
cloud-signing availability; if this unsigned-archive approach fails for your
account or Xcode version, use the manual signing alternative below. Cloud signing
and upload succeeded once with this app's Apple account; future runs still depend
on valid credentials and Apple processing.

## Run the workflow

1. Open **Actions → iOS TestFlight → Run workflow** and choose the branch.
2. Choose **cloud** signing. Optionally enter a positive integer build number
   greater than previous builds for that marketing version. The default is
   `run_number × 100 + run_attempt`, unique within this workflow but potentially
   lower than or colliding with builds made elsewhere.
3. Leave **Upload** off for an export-only test, or turn it on to upload to
   App Store Connect / TestFlight. **Keep IPA** is off by default: enabling it
   publishes a seven-day Actions artifact accessible to repository readers. This
   repository is public, so the artifact may be broadly accessible.
4. After an upload, wait for processing in App Store Connect → TestFlight,
   complete any required compliance questions, and assign testers there.

**unsigned** signing mode is a credentials-free Mac/Xcode archive check, not an
installable IPA and not a TestFlight build. It requires both Upload and Keep IPA
to be off, and uses a dummy team and bundle ID if the real variables are unset.

## Alternative: manual certificate signing

Select **manual** signing if you already have an Apple Distribution certificate
with its private key and a matching App Store provisioning profile. In addition
to the variables above, add these environment secrets:

| Name | Value |
| --- | --- |
| `IOS_DISTRIBUTION_P12_BASE64` | Base64 of the password-protected `.p12` certificate and private key. |
| `IOS_DISTRIBUTION_P12_PASSWORD` | Password used to export that `.p12`. |
| `IOS_APP_STORE_PROFILE_BASE64` | Base64 of the App Store `.mobileprovision` profile. |

The three `ASC_*` secrets are also needed when uploading in manual mode. It is
possible to create a certificate and profile on Windows using OpenSSL and the
Apple Developer portal; no Mac is required for that preparation. Never commit
or share the certificate, private key, or password. Use an explicit App ID and
a distribution profile containing the matching certificate.

## Security and maintenance

Limit repository access and use environment protection rules as appropriate.
The workflow deletes its temporary signing files and keychain at the end of the
hosted run. It targets iOS 14 or later and downloads the official Godot 4.7.2 macOS editor and matching
export templates with pinned SHA-256 checksums, and uses the Xcode installed on
Xcode 26.6 on the GitHub `macos-26` runner. To upgrade Godot, update its version and both
checksums together. Runner images and Apple's signing requirements can change;
inspect failure logs rather than assuming the build was uploaded. The workflow
modifies `export_presets.cfg` only on the runner, and uses an opaque iOS icon
based on the project's existing card icon.
