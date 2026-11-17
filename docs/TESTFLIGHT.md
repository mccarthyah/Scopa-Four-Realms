# GitHub Actions: iOS / TestFlight

The **iOS TestFlight** workflow is started manually from GitHub Actions. On a
GitHub-hosted Mac it exports a Godot Xcode project, signs an App Store IPA, and
optionally uploads it to App Store Connect. It uses the current checked-out
commit, including the supplied card artwork. It does not submit the app for App
Review or automatically add testers. Apple processes an uploaded build before
it becomes available in TestFlight; external testing may require Beta App Review.

**Status:** the workflow needs real Apple account configuration and its first
macOS run. It has not yet been verified against Xcode, Apple signing, TestFlight,
or a physical iOS device. A GitHub token alone cannot provide Apple signing.

## 1. Apple prerequisites

- An active Apple Developer Program membership with permissions for certificates,
  identifiers, profiles and App Store Connect.
- Register an explicit App ID / bundle identifier and create a corresponding
  app record in App Store Connect. The bundle ID must match exactly.
- An **Apple Distribution** certificate **with its private key**, exported
  together as a password-protected `.p12` file. An iOS **App Store Connect**
  distribution provisioning profile for the same team, explicit App ID, and
  certificate. Do not use a development or ad-hoc profile.
- For uploads, an App Store Connect **team API key** with sufficient upload
  permissions, its key ID, issuer ID, and downloaded `.p8` private key.
  Keep all keys private. Do not send them in chat or commit them to Git.

## 2. GitHub environment settings

In the repository's **Settings → Environments**, create an environment named
`testflight`. Add these environment **variables** (or use repository variables):

| Variable | Value |
| --- | --- |
| `APPLE_TEAM_ID` | Your 10-character Apple Developer team ID. |
| `IOS_BUNDLE_ID` | The exact registered bundle ID; the placeholder in `export_presets.cfg` need not be yours. |
| `IOS_VERSION` | Marketing version, e.g. `1.0` (optional; defaults to `1.0`). |

Add these environment **secrets** (or repository secrets):

| Secret | Value |
| --- | --- |
| `IOS_DISTRIBUTION_P12_BASE64` | Base64 of the `.p12` certificate **and private key**. |
| `IOS_DISTRIBUTION_P12_PASSWORD` | Password used when exporting the `.p12`. |
| `IOS_APP_STORE_PROFILE_BASE64` | Base64 of the `.mobileprovision` App Store distribution profile. |
| `ASC_KEY_ID` | App Store Connect team API key ID; required only when uploading. |
| `ASC_ISSUER_ID` | App Store Connect API issuer ID; required only when uploading. |
| `ASC_PRIVATE_KEY_BASE64` | Base64 of the `.p8` API private key; required only when uploading. |

On macOS, generate each Base64 value locally without printing it in chat:

```sh
base64 -i /path/to/distribution.p12 | pbcopy
# Paste into IOS_DISTRIBUTION_P12_BASE64 in GitHub, then:
base64 -i /path/to/appstore.mobileprovision | pbcopy
# Paste into IOS_APP_STORE_PROFILE_BASE64, then:
base64 -i /path/to/AuthKey_KEYID.p8 | pbcopy
# Paste into ASC_PRIVATE_KEY_BASE64; clear your clipboard afterward.
```

Use repository access controls and, if desired, environment protection rules to
limit who can run this workflow. A signed IPA is saved as an Actions artifact only if **Keep IPA** is selected;
it is retained for seven days and can be downloaded by people with access to
that repository's artifacts. This repository is public, so an artifact may be
broadly accessible. Leave **Keep IPA** off if that is not acceptable. The temporary
certificate, profile and API key are removed from the hosted runner at the end.

## 3. Run it

1. Open **Actions → iOS TestFlight → Run workflow** and choose the desired branch.
2. Optionally enter a positive integer build number that is unique and higher
   than previous builds for that marketing version. If omitted, the workflow
   uses `run_number × 100 + run_attempt`; this is unique within this workflow,
   but **may collide with or be lower than builds made elsewhere**. Use an
   explicit number if you already have builds in App Store Connect.
3. Leave **Upload** off to build and retain a signed IPA without uploading.
   Turn it on to upload to App Store Connect / TestFlight. This is an explicit,
   manual choice; the workflow does not run on every push.
4. Optionally turn **Keep IPA** on to retain an artifact (see the public-access
   warning above); it is off by default. Check the Actions log and any artifact.
   After upload, wait for processing in App
   Store Connect → TestFlight, complete any required compliance questions, and
   assign internal or external testers there.

The job downloads the official Godot 4.7.2 macOS editor and matching export
templates with pinned SHA-256 checksums, and uses the Xcode installed on the
GitHub `macos-15` runner. To upgrade Godot, update the version and both pinned
checksums together. GitHub-hosted runner images and Apple's signing requirements
can change; inspect failed Xcode/Apple messages rather than assuming a successful
upload. The workflow modifies `export_presets.cfg` only in the ephemeral runner.
Its 1024×1024 opaque iOS icon is based on the project's existing card icon.
