# Spotify SYNA V1 — Source Implementation

Repository: `ciowfreshh/vitrine`  
**Only authorized development branch:** `syna-spotify-v1`  
Baseline before source changes: `cd7ace640513e02e398f1fa9f8f2e29d07aa8eac`  
The `main` branch and existing services are not modified.

## Implemented and committed

- **SYNA identity and onboarding** — replaced the Vitrine glass-reed logo with a vector trace of the supplied SYNA organic mark; white SYNA wordmark and `syna.lol`, black AMOLED backdrop, vivid neon-green selected cards and start button. Fade/landing animation honors iOS Reduce Motion.
- **Existing onboarding and restart preserved** — Modern and Classic look choices, existing ad-selection behavior, and restart path remain. An additional `spotifyglass.syna.welcome.seen` preference displays the new SYNA tour once to existing Vitrine users after they upgrade.
- **Settings** — renamed the mod entry to **Cài đặt SYNA** (English: SYNA Settings), placed the drawer entry after existing rows, and inserted language selection, export/import configuration, API connection test, and saved translation management in the settings root.
- **Language** — Vietnamese default; switch to English from the SYNA settings root and restart. Localization uses a translation dictionary for the root and major tweak settings pages without mutating stored preference keys, API model IDs or Spotify account data. Unsupported strings remain in their original language; complete translation coverage must be validated on device.
- **Theme** — added reversible Graphite and Silver accent presets to Appearance; preserves the two previous independent look-specific accent settings.
- **Settings backup** — uses the existing `SGExportSettings`/`SGImportSettings` implementation. API credentials stay in Keychain and are not exported.
- **API connectivity** — a small test translation uses the currently selected provider, endpoint, model and Keychain key. Success requires a valid one-line response, not just HTTP 200. The key is never presented in a log or alert.
- **Saved translations** — removes the 200-file eviction cap; stores JSON per track/language in `Application Support/SYNA/Translations`, copying old entries from `Caches/Vitrine/Translations` without deleting their originals. The original explicit Delete button and file count/size row remain.
- **App icon** — `scripts/generate-syna-icon.py` creates a 1024×1024 opaque SYNA AMOLED icon with Python standard library. The IPA pipeline makes it the primary icon and offers SYNA as an alternate, excluding `Vitrine.png` from alternate icon registration.
- **Branding** — SYNA app display name/output filename, diagnostic filenames, update/repository links and installation warnings.

## Verification

- Source-level checks: `python3 scripts/verify-syna-v1.py`.
- CI: `.github/workflows/syna-v1-checks.yml` runs the checks on branch pushes.
- The verification script covers onboarding markers, welcome migration, preserved choices, menu actions, translation storage migration, no auto eviction, icon selection, image data and scripts.
- A GitHub connector source inspection passed 16 of 16 checks. This **does not replace an Objective-C / Logos compiler build**.

## Build the IPA

Requires a **user-supplied decrypted Spotify IPA**, Theos, macOS Xcode/iPhoneOS 26+ SDK, `gmake`, `ldid`, `dpkg-deb` and `cyan`.

```bash
git switch syna-spotify-v1
python3 scripts/verify-syna-v1.py
make release IPA=/absolute/path/to/decrypted-spotify.ipa
```

For CI use GitHub **Actions → Build IPA from your own Spotify IPA → Run workflow**, select **`syna-spotify-v1`**, supply a direct authorized `ipa_url`, and download the generated artifact. The workflow does not magically fetch or decrypt an IPA.

## Device validation still required

Check first-run vs upgrade onboarding; native Spotify Settings placement; Vietnamese/English text; Modern/Classic switching and restart; icon selection and installation signature; API error handling/timeout and no accidental key exposure; migration of >200 saved translations; preservation of prompts and preferences; AirPods, Live Activity, lyrics and playback regressions. iOS code has **not** been built or device-tested in the ChatGPT execution environment.

## Known limits and scope

- Existing Spotify and Vitrine internals remain intact, including old `spotifyglass.` keys to preserve user data.
- Text localization uses a dictionary; some deeper screens and system messages may remain English.
- Translation archive export, the complete Liked Songs batch-translation UX, and advanced voice-aware duet translation are not claimed as completed in this Phase 1 change set.
- A decrypted IPA and a real iPhone test are required before a production release can be called finished.
