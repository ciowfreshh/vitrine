# Vitrine V2 source audit

## Provenance

The connected repository is `ciowfreshh/vitrine`, whose GitHub parent is
`My-Name-Is-Jeff/vitrine`. The source ZIP supplied by the user is the official
`v1.0.0-beta.16` tag, commit `36d3b38ec39c0b8b696f1d2db026ca9e9939bf14`.
Every regular file was compared by Git blob hash with that upstream tree before editing.
The upstream releases endpoint contained beta releases only; there was no release marked stable.
Beta.16 was the newest published release at the time of the audit.
The development branch starts at that tag, not at `syna-spotify-v1`. No main ref is changed.

## Source inventory and integration

Read `AGENTS.md` and `docs/tweaks.md`, enumerated the complete Sources tree, and
inventoried Objective-C/Logos strings before implementation. Reviewed settings factories,
page routing, onboarding, UIKit and SwiftUI renderers, translation request/response paths,
saved files, batch translation, application packaging, and Live Activity/App Intents builds.

- `Core`: locale selection and durable storage infrastructure, importing no higher layer.
- `Settings`: existing settings controls and pages; no replacement dashboard.
- `App`: onboarding, Mod Settings, combined pages, About, diagnostics and updates.
- `Native` and `Redesigned`: independent presentation of both existing looks.
- `Shared`: lyrics, AI/device translation, meanings, sources, local files, fonts, icons,
  audio effects, Karaoke, spatial voice, haptics, AirPods gestures, privacy, Premium,
  flags, navigation, listening statistics, animated art, AutoMix, lossless and player UI.
- `extension/LiveActivity`: lock-screen widgets, controls and accessibility labels.

The original saved-translation implementation kept `kKept = 200`, deleted the oldest
JSON files after each save, and used `NSCachesDirectory/Vitrine/Translations`.
Its settings row only deleted all saved translations. There was no translation archive interface.

## Preservation

Playback algorithms, default Spotify name/icon, provider IDs, API request structure,
models, translation prompts, the two existing UI modes and onboarding layout are retained.
Localization uses explicit UI call sites, not global UIKit/NSBundle method swizzling or
an AppleLanguages override. Spotify titles, artists, original lyrics, user-entered text,
protocol keys, SF Symbol names and source matching tokens remain data.
Third-party license originals are retained as legally supplied; their surrounding UI is localized.
Upstream release descriptions and Genius explanations are external content, not translated by this patch.

`tests/upstream-contract.json` pins unchanged DSP files and original AI instructions/provider table.
`localization/non-ui-literals.json` is a reviewed baseline for protocol, diagnostics, names,
external content and model instructions; a new literal fails CI until classified.
A static inventory is a regression gate, not proof of visual or linguistic perfection on a phone.
