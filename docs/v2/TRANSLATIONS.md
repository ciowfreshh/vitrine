# Translation library and validation

Vitrine Settings → Lyrics → Saved translations opens the library.
Select one song and Export selected produces JSON. Multiple selected songs produce ZIP.
Export all always produces ZIP. Each ZIP member is a separate JSON record, named by
SHA-256 of the track/language pair; song text never becomes a filesystem path.
Import JSON or ZIP offers Skip duplicates or Replace duplicates. Track plus language is
identity; repeats within the same import use the same rule. AirDrop, Files and iCloud Drive
can carry these files to another iPhone. No network or API key is needed for transfer.

## Durable storage

`Application Support/Vitrine/Translations/translations.sqlite3`, WAL with synchronous FULL.
A complete record is an atomic SQLite commit, serialized on one database queue. There is
no song-count cap or eviction. Completed songs survive termination; an interrupted song
retains its previous committed snapshot. Device backup includes Application Support.
Uninstalling Spotify or changing to a separate signed app container can remove or isolate
its data: export before uninstalling or changing the signing identity.

Old cached JSON files are imported at the first store access. Both historical line-only and
source-aware formats are accepted. A valid source file is removed only after a successful
commit or a confirmed existing record. Broken files remain in place for recovery. The
migration cannot restore translations already removed by the old 200-file limit or iOS.

Exports whitelist `type`, `schemaVersion`, `track`, `language`, `lines`, `by`, `model`,
`made`, `title`, `artist`. API keys, server credentials and settings are never exported.
Current playback saves track/source/model/date/lines and available display metadata;
older files without a song title display their track ID rather than an invented title.

JSON format: `type = vitrine.translation`, `schemaVersion = 1`, nonempty track/language
and string-to-string `lines`; source and date are optional. Unknown fields are discarded.
Malformed records do not replace existing data. Imports commit each valid song and report
counts if a later entry fails, so a retry can safely skip previously committed records.

ZIP accepts stored and deflated entries with CRC validation, no encryption, symlinks,
traversal, duplicate archive member names or ZIP64. It never extracts untrusted paths.
Import safety bounds: 8 MiB per JSON, 50,000 ZIP members, 512 MiB expanded total and
1 GiB input ZIP. Export streams ZIP32 without holding all lyrics in memory; a single
export supports 50,000 songs and less than 4 GiB. These transfer bounds do not cap storage.

## Checks

- `python3 scripts/localization.py`: catalog generation parity, formatting arguments,
  placeholders and classified Objective-C/Logos/Swift source-string inventory. Existing
  catalog text must use a localizer or an explicitly reviewed deferred display/protocol
  statement; adding an English string already present in the catalog still fails the gate.
- `python3 -m unittest discover -s tests -v`: regression tests, including an injected new
  untranslated warning, preservation contracts and resource isolation.
- `tests/translation-store/run.sh` on macOS: real Foundation/SQLite/zlib tests with
  10,001 records, reopening, abrupt process exit, old migration, duplicate policies,
  whitelist export, selected/all JSON/ZIP and malicious/corrupted ZIP fixtures.
- GitHub Actions compiles the complete Theos tweak and the extension/App Intents metadata.
  The compile-only job uses an empty flag table and does not publish an IPA.
- A manual build on this branch requires the user's decrypted Spotify IPA. It regenerates
  the real flags from that IPA, validates input/output integrity and encryption status,
  checks original branding and localization resources, then uploads IPA/checksums/commit.

## Device checks still required

No iPhone is attached to this environment. Before treating the build as a release, check
both existing looks, onboarding, every settings subpage, Vietnamese wrapping/Dynamic Type,
VoiceOver, manual/device language selection, Live Activity, import/export via Files/AirDrop,
a large library, low storage, app termination during saving, upgrade over the same signed
container, and existing playback/translation behavior. OS-owned sheets and Siri/Shortcuts
metadata may require the system language or a system refresh; validate these on a device.
The UI language changes immediately for newly built screens; restart applies it to all
cached views. It is independent of the lyrics translation target and Spotify's own locale.
