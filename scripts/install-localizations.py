#!/usr/bin/env python3
"""Add Vitrine's own table to the unsigned IPA, preserving Spotify tables and branding."""
import json,pathlib,sys,zipfile,plistlib,subprocess,tempfile,shutil,os
root=pathlib.Path(__file__).resolve().parents[1]
def table(value):
    return ''.join(json.dumps(k,ensure_ascii=False)+' = '+json.dumps(v,ensure_ascii=False)+';\n' for k,v in sorted(value.items())).encode('utf-8')
def resources():
    catalog=json.loads((root/'localization/catalog.json').read_text())
    shortcuts=json.loads((root/'localization/app-shortcuts.json').read_text())
    return {f'{lang}.lproj/{name}.strings':table({k:k if lang=='en' else v for k,v in mapping.items()})
            for lang in ('en','vi') for name,mapping in (('Vitrine',catalog),('AppShortcuts',shortcuts))}
def merge_table(before,addition):
    # Existing Spotify tables can be binary/XML or OpenStep .strings. plutil handles all
    # Apple formats on the macOS build host; unrelated entries remain intact.
    try: current=plistlib.loads(before)
    except plistlib.InvalidFileException:
        with tempfile.NamedTemporaryFile(suffix='.strings') as source:
            source.write(before);source.flush()
            current=plistlib.loads(subprocess.check_output(['plutil','-convert','xml1','-o','-',source.name]))
    if not isinstance(current,dict):raise ValueError('Expected a strings dictionary')
    import re
    for key,value in re.findall(r'("(?:[^"\\]|\\.)*")\s*=\s*("(?:[^"\\]|\\.)*");',addition.decode()):
        current[json.loads(key)]=json.loads(value)
    return plistlib.dumps(current,fmt=plistlib.FMT_BINARY,sort_keys=True)
def install(path,app):
    path=pathlib.Path(path);new={app.rstrip('/')+'/'+name:data for name,data in resources().items()}
    with tempfile.NamedTemporaryFile(dir=path.parent,suffix='.ipa',delete=False) as temp:replacement=pathlib.Path(temp.name)
    try:
        with zipfile.ZipFile(path) as original,zipfile.ZipFile(replacement,'w',compression=zipfile.ZIP_DEFLATED) as output:
            if len(original.namelist())!=len(set(original.namelist())):raise ValueError('Duplicate IPA members')
            for info in original.infolist():
                if info.filename in new:
                    output.writestr(info,merge_table(original.read(info),new.pop(info.filename)))
                else:
                    with original.open(info) as src,output.open(info,'w') as dst:shutil.copyfileobj(src,dst)
            for name,data in new.items():output.writestr(name,data)
        os.replace(replacement,path)
    finally:replacement.unlink(missing_ok=True)
if __name__=='__main__':
    install(sys.argv[1],sys.argv[2])
