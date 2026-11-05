#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p out/tests
sdk=$(xcrun --sdk macosx --show-sdk-path)
xcrun -sdk macosx clang -target arm64-apple-ios17.0-macabi -isysroot "$sdk" \
  -iframework "$sdk/System/iOSSupport/System/Library/Frameworks" -fobjc-arc -fblocks \
  -Wall -Wextra -Werror -Wno-unused-parameter -Wno-incompatible-pointer-types -Wno-deprecated-declarations \
  -Itweak/Sources -framework UIKit -framework Foundation -framework CoreGraphics -framework NaturalLanguage -lsqlite3 \
  tweak/Sources/Core/SGLocalization.m tweak/Sources/Core/TranslationStore/SGTranslationStore.m \
  tweak/Sources/Core/BatchQueue/SGTranslationAlignment.m \
  tweak/Sources/Shared/LyricsTranslation/SavedTranslations.m tweak/Sources/Shared/Lyrics/KaraokeTiming.m \
  tweak/Sources/Shared/AdBlock/Protobuf.m tests/translation-playback/main.m -o out/tests/translation-playback
out/tests/translation-playback 2>&1 | tee out/tests/translation-playback.log
