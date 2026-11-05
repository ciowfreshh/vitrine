#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p out/tests
python3 tests/translation-store/fixtures.py out/tests/fixtures
python3 - <<'PY'
import importlib.util,pathlib,plistlib
spec=importlib.util.spec_from_file_location('tables','scripts/install-localizations.py')
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
for relative,data in module.resources().items():
    path=pathlib.Path('out/tests')/relative
    path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(data)
    # Verify real Apple OpenStep parsing when a Spotify table must be merged.
    merged=plistlib.loads(module.merge_table(data,b'"Spotify-owned" = "Preserved";\n'))
    assert merged['Spotify-owned']=='Preserved'
PY
xcrun clang -fobjc-arc -fblocks -Wall -Wextra -Wno-unused-parameter -Wno-incompatible-pointer-types -Itweak/Sources \
  -framework Foundation -lsqlite3 -lz tweak/Sources/Core/SGLocalization.m tweak/Sources/Core/TranslationStore/*.m \
  tests/translation-store/main.m -o out/tests/translations
out/tests/translations out/tests/fixtures
