#!/usr/bin/env python3
import argparse,pathlib,plistlib,struct,zipfile,hashlib,re
parser=argparse.ArgumentParser();parser.add_argument('ipa');parser.add_argument('--built',action='store_true');parser.add_argument('--original');parser.add_argument('--sha256',default='');args=parser.parse_args()
if args.sha256:
    if not re.fullmatch('[0-9a-fA-F]{64}',args.sha256):raise ValueError('Invalid expected IPA SHA-256')
    digest=hashlib.sha256()
    with open(args.ipa,'rb') as source:
        for chunk in iter(lambda:source.read(1024*1024),b''):digest.update(chunk)
    if digest.hexdigest()!=args.sha256.lower():raise ValueError('IPA SHA-256 does not match the expected input')
def app_info(ipa):
    names=ipa.namelist();apps=[n for n in names if n.startswith('Payload/') and n.endswith('.app/Info.plist') and n.count('/')==2]
    if len(apps)!=1:raise ValueError('Expected one main app')
    app=apps[0][:-len('Info.plist')];info=plistlib.loads(ipa.read(apps[0]));return app,info

def decrypted(binary):
    magic=binary[:4]
    if magic in (b'\xca\xfe\xba\xbe',b'\xca\xfe\xba\xbf'):
        n=struct.unpack_from('>I',binary,4)[0];size=32 if magic[-1]==191 else 20
        if n>32:raise ValueError('Invalid universal binary')
        for i in range(n):
            start=8+i*size
            offset,length=struct.unpack_from('>QQ' if size==32 else '>II',binary,start+8)
            decrypted(binary[offset:offset+length])
        return
    if magic not in (b'\xcf\xfa\xed\xfe',b'\xce\xfa\xed\xfe'):raise ValueError('Unsupported Mach-O executable')
    ncmds=struct.unpack_from('<I',binary,16)[0];offset=32 if magic[0]==207 else 28
    if ncmds>10000:raise ValueError('Invalid load commands')
    for _ in range(ncmds):
        command,size=struct.unpack_from('<II',binary,offset)
        if size<8 or offset+size>len(binary):raise ValueError('Invalid load command')
        if command in (0x21,0x2c) and struct.unpack_from('<I',binary,offset+16)[0]!=0:raise ValueError('IPA executable is still encrypted')
        offset+=size
with zipfile.ZipFile(args.ipa) as ipa:
    if ipa.testzip() is not None:raise ValueError('Archive CRC failure')
    app,info=app_info(ipa)
    if info.get('CFBundleIdentifier')!='com.spotify.client':raise ValueError('Expected an original Spotify bundle identifier')
    decrypted(ipa.read(app+info['CFBundleExecutable']))
    if args.built:
        for language in ('en','vi'):
            for table in ('Vitrine','AppShortcuts'):
                if app+language+'.lproj/'+table+'.strings' not in ipa.namelist():raise ValueError('Missing UI localization')
        if not any(n.endswith('/spotifyglass.dylib') for n in ipa.namelist()):raise ValueError('Missing tweak')
        if not any('SpotifyGlassLiveActivity.appex/vi.lproj/Vitrine.strings' in n for n in ipa.namelist()):raise ValueError('Missing extension localization')
        if args.original:
            with zipfile.ZipFile(args.original) as original:
                _,before=app_info(original)
                for key in ('CFBundleIdentifier','CFBundleName','CFBundleDisplayName'):
                    if before.get(key)!=info.get(key):raise ValueError('Unexpected branding change: '+key)
                if before.get('CFBundleIcons',{}).get('CFBundlePrimaryIcon')!=info.get('CFBundleIcons',{}).get('CFBundlePrimaryIcon'):raise ValueError('Default icon changed')
    print('PASS: IPA integrity, executable decryption'+(', localization, tweak, extension and original branding' if args.built else ''))
