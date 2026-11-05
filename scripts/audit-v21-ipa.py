#!/usr/bin/env python3
"""Evidence from the actual IPA; symbols alone never certify a callable native share API."""
import argparse, hashlib, json, pathlib, plistlib, re, zipfile
p=argparse.ArgumentParser();p.add_argument('ipa');p.add_argument('output');a=p.parse_args()
path=pathlib.Path(a.ipa)
with zipfile.ZipFile(path) as z:
    name=next(n for n in z.namelist() if re.fullmatch(r'Payload/[^/]+\.app/Info.plist', n))
    info=plistlib.loads(z.read(name)); app=name[:-10]
    binary=z.read(app+info['CFBundleExecutable'])
    hints=['ShareLyricsService','LyricsSharingPageView','LyricsShareSelectorPage','LyricsShareFormatViewController','spotify:lyrics-share-selector','spotify:internal:lyrics:share:lines']
    report={'spotify_version':info['CFBundleShortVersionString'],'bundle_id':info['CFBundleIdentifier'],
        'native_share_symbols':{s:s.encode() in binary for s in hints},
        'native_share_invocation_verified':False,'selected_line_payload_verified':False,
        'real_iphone_tested':False,'apple_music_native_share_integrated':False,
        'has_provisioning_profile':app+'embedded.mobileprovision' in z.namelist(),
        'signing_note':'Build pipeline uses fakesigning/ad-hoc signing, not a verified installable Apple distribution signature.'}
del binary
with path.open('rb') as f: report['sha256']=hashlib.file_digest(f,'sha256').hexdigest()
out=pathlib.Path(a.output);out.parent.mkdir(parents=True,exist_ok=True);out.write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
