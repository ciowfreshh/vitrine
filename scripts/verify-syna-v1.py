#!/usr/bin/env python3
"""Source-level regression checks for Spotify SYNA V1 (no iOS SDK needed)."""
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import zlib

ROOT = Path(__file__).resolve().parents[1]

def source(path):
    return (ROOT / path).read_text(encoding="utf-8")

def has(path, text):
    assert text in source(path), f"{path} missing {text!r}"

def run(*argv):
    subprocess.run(list(argv), cwd=ROOT, check=True)

def validate():
    has("tweak/Sources/App/Onboarding/Tour.m", 'accessibilityLabel = @"SYNA, syna.lol"')
    has("tweak/Sources/App/Onboarding/Tour.m", "UIAccessibilityIsReduceMotionEnabled()")
    has("tweak/Sources/App/Onboarding/Tour.m", "kCAFillRuleEvenOdd")
    has("tweak/Sources/App/Onboarding/Onboarding.x", "SGKeySYNAWelcomeSeen")
    has("tweak/Sources/App/Onboarding/Tour.m", "setBool:YES forKey:SGKeySYNAWelcomeSeen")
    has("tweak/Sources/App/ModSettings.x", 'initWithTitle:@"SYNA Settings"')
    has("tweak/Sources/App/ModSettings.x", "SGSetSYNALanguage")
    has("tweak/Sources/App/ModSettings.x", "SGExportSettings()")
    has("tweak/Sources/App/ModSettings.x", "SGImportSettings()")
    has("tweak/Sources/App/ModSettings.x", "SGSavedTranslationsRow()")
    has("tweak/Sources/App/ModSettings.x", "SGTestAIConnection()")
    has("tweak/Sources/Shared/LyricsTranslation/LyricsTranslation.m", "void SGTestAIConnection(void)")
    has("tweak/Sources/Shared/LyricsTranslation/LyricsTranslation.m", "storedSecret(p, kKeyAccount)")
    saved = source("tweak/Sources/Shared/LyricsTranslation/SavedTranslations.m")
    assert "NSApplicationSupportDirectory" in saved
    assert "kKept" not in saved
    assert "copyItemAtURL:file" in saved
    has("tweak/Sources/Shared/AppIcon/AppIcon.m", '[names removeObject:@"Vitrine"]')
    has("scripts/pipeline.sh", "Spotify SYNA")
    has("scripts/pipeline.sh", '"Vitrine.png"')
    has("scripts/pipeline.sh", "scripts/generate-syna-icon.py")
    # The package entrypoint must use the same Python environment as CI's pip.
    # Guessing a sibling /usr/local/bin/python from `cyan` is broken on macOS.
    pipeline = source("scripts/pipeline.sh")
    assert "python3 -c 'from PIL import Image'" in pipeline
    assert 'readlink -f "$(command -v cyan)"' not in pipeline
    has("tweak/Sources/App/Pages.m", "SGKeySYNATheme")
    run("bash", "-n", "scripts/pipeline.sh")
    run(sys.executable, "-m", "py_compile", "scripts/generate-syna-icon.py")
    run("bash", "scripts/check-layers.sh", "tweak/Sources")

    with tempfile.TemporaryDirectory(prefix="syna-v1-") as directory:
        icon = Path(directory)/"SYNA.png"
        run(sys.executable, "scripts/generate-syna-icon.py", str(icon))
        data = icon.read_bytes()
        assert data.startswith(b"\x89PNG\r\n\x1a\n"), "Bad PNG signature"
        chunks = []
        idx = 8
        while idx < len(data):
            n = int.from_bytes(data[idx:idx+4], "big")
            kind = data[idx+4:idx+8]
            payload = data[idx+8:idx+8+n]
            assert zlib.crc32(kind+payload) & 0xffffffff == int.from_bytes(data[idx+8+n:idx+12+n], "big")
            chunks.append((kind,payload))
            idx += 12+n
        hdr = next(payload for kind,payload in chunks if kind==b"IHDR")
        width,height,bits,color,*_ = struct.unpack(">IIBBBBB", hdr)
        assert (width,height,bits,color)==(1024,1024,8,6)
        decoded = zlib.decompress(b"".join(payload for kind,payload in chunks if kind==b"IDAT"))
        assert len(decoded)==1024*(1+1024*4), "Invalid RGBA size"
        assert decoded.count(b"\xff\xff\xff\xff")>1000, "SYNA white mark not visible"
    print("Spotify SYNA V1 source and icon checks: PASSED")

if __name__ == "__main__":
    validate()
