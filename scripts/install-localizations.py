#!/usr/bin/env python3
"""Add Vitrine's own table to the unsigned IPA, preserving Spotify tables and branding."""
import json,pathlib,sys,zipfile
root=pathlib.Path(__file__).resolve().parents[1]
def table(value):
    return ''.join(json.dumps(k,ensure_ascii=False)+' = '+json.dumps(v,ensure_ascii=False)+';\n' for k,v in sorted(value.items())).encode('utf-8')
def resources():
    catalog=json.loads((root/'localization/catalog.json').read_text())
    return {f'{lang}.lproj/Vitrine.strings':table({k:k if lang=='en' else v for k,v in catalog.items()}) for lang in ('en','vi')}
if __name__=='__main__':
    with zipfile.ZipFile(sys.argv[1],'a',compression=zipfile.ZIP_DEFLATED) as ipa:
        for path,data in resources().items():
            name=sys.argv[2].rstrip('/')+'/'+path
            if name in ipa.namelist():raise ValueError('Refusing duplicate localization table')
            ipa.writestr(name,data)
