#!/usr/bin/env python3
"""Generate an opaque Spotify SYNA AMOLED icon; pure Python 3, no Pillow dependency."""
import struct
import sys
import zlib
from pathlib import Path

N = 1024
pixels = bytearray(b"\x00\x00\x00\xff" * (N * N))
# Simplified polygon trace of the user-supplied organic SYNA logo.
outer = [(182,34),(149,35),(131,45),(120,58),(114,74),(114,92),
(132,134),(133,150),(128,170),(105,200),(54,228),(41,243),
(35,258),(34,281),(43,306),(62,327),(83,338),(113,342),
(150,329),(172,308),(203,255),(229,234),(249,228),(266,228),
(308,247),(332,250),(353,241),(370,216),(370,194),(355,171),
(336,163),(294,162),(262,144),(236,111),(211,55),(197,41)]
hole = [(199,145),(245,185),(247,201),(240,209),(175,238),(163,237),
(154,230),(151,222),(161,184),(175,153),(183,146)]
def put(x, y, rgba):
    if 0 <= x < N and 0 <= y < N:
        i = (y * N + x) * 4
        pixels[i:i+4] = rgba

def fill_polygon(poly, rgba):
    # Scanline span filling; the white shape and its black cutout are separate.
    low = max(0, min(y for _, y in poly))
    high = min(N, max(y for _, y in poly) + 1)
    for y in range(low, high):
        intersections = []
        for (x1,y1),(x2,y2) in zip(poly, poly[1:]+poly[:1]):
            if (y1 <= y+0.5 < y2) or (y2 <= y+0.5 < y1):
                intersections.append(x1 + (y+0.5-y1)*(x2-x1)/(y2-y1))
        intersections.sort()
        for a,b in zip(intersections[::2], intersections[1::2]):
            for x in range(max(0,int(a)), min(N, int(b)+1)):
                put(x,y,rgba)

def transform(poly):
    return [(round(237+(x-34)*1.64), round(118+(y-34)*1.64)) for x,y in poly]

fill_polygon(transform(outer), b"\xff\xff\xff\xff")
fill_polygon(transform(hole), b"\x00\x00\x00\xff")
glyphs = {
"S":("01111","10000","10000","01110","00001","00001","11110"),
"Y":("10001","10001","01010","00100","00100","00100","00100"),
"N":("10001","11001","10101","10101","10011","10001","10001"),
"A":("01110","10001","10001","11111","10001","10001","10001"),
}
size = 17
left = (N - (4*5 + 3)*size)//2
for i,letter in enumerate("SYNA"):
    for row,bits in enumerate(glyphs[letter]):
        for col,bit in enumerate(bits):
            if bit != "1": continue
            x0 = left + (i*6+col)*size
            y0 = 771 + row*size
            for y in range(y0,y0+size):
                for x in range(x0,x0+size):
                    put(x,y,b"\xff\xff\xff\xff")
for y in range(942,948):
    for x in range(398,626):
        put(x,y,b"\x35\xff\x71\xff")

def chunk(kind, data):
    return struct.pack(">I",len(data)) + kind + data + struct.pack(">I",zlib.crc32(kind+data)&0xffffffff)
scanlines = b"".join(b"\x00" + pixels[i*N*4:(i+1)*N*4] for i in range(N))
png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB",N,N,8,6,0,0,0)) + chunk(b"IDAT",zlib.compress(scanlines,6)) + chunk(b"IEND",b"")
target = Path(sys.argv[1] if len(sys.argv)>1 else "icons/SYNA.png")
target.parent.mkdir(parents=True,exist_ok=True)
target.write_bytes(png)
print("Generated",target,"bytes",len(png))
