#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
build_dir="$(mktemp -d)"
trap 'rm -rf "$build_dir"' EXIT
sources=tweak/Sources
mkdir "$build_dir/UIKit"
printf '#import <Foundation/Foundation.h>\n@class UIView, UIViewController;\n' > "$build_dir/UIKit/UIKit.h"
xcrun --sdk macosx clang -fobjc-arc -fblocks -Werror -Wno-incompatible-pointer-types \
  -I"$sources" -I"$build_dir" -framework Foundation -framework CoreFoundation -lz \
  harness/lyrics-library/main.m \
  "$sources"/Shared/LyricsLibrary/{SGLibraryModel,SGLibraryZIP,SGLibraryStore,SGLibraryScan,SGLibraryPlayback,SGLibraryOriginal}.m \
  "$sources"/Core/SGVietnamese.m "$sources"/Shared/Lyrics/KaraokeTiming.m \
  -o "$build_dir/check"
"$build_dir/check"
