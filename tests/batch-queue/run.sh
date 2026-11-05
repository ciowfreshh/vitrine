#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p out/tests
xcrun clang -fobjc-arc -fblocks -Wall -Wextra -Werror -Wno-unused-parameter -Wno-incompatible-pointer-types \
  -Itweak/Sources -framework Foundation -framework NaturalLanguage tweak/Sources/Core/BatchQueue/*.m tests/batch-queue/main.m -o out/tests/batch-queue
out/tests/batch-queue 2>&1 | tee out/tests/batch-queue.log
