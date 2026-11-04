#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p out/tests
python3 tests/translation-store/fixtures.py out/tests/fixtures
xcrun clang -fobjc-arc -fblocks -Wall -Wextra -Wno-unused-parameter -Wno-incompatible-pointer-types -Itweak/Sources \
  -framework Foundation -lsqlite3 -lz tweak/Sources/Core/SGLocalization.m tweak/Sources/Core/TranslationStore/*.m \
  tests/translation-store/main.m -o out/tests/translations
out/tests/translations out/tests/fixtures
