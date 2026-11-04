import io,json,pathlib,sys,zipfile,struct
root=pathlib.Path(sys.argv[1]);root.mkdir(parents=True,exist_ok=True)
record={'type':'vitrine.translation','schemaVersion':1,'track':'fixture','language':'vi','lines':{'Original':'Dịch'}}
for name,method in [('good-stored',zipfile.ZIP_STORED),('good-deflated',zipfile.ZIP_DEFLATED)]:
 with zipfile.ZipFile(root/f'{name}.zip','w',compression=method) as z:z.writestr('track.json',json.dumps(record))
for name,entry in [('bad-traversal','../track.json'),('bad-absolute','/track.json'),('bad-backslash','a\\track.json'),('bad-not-json','track.txt')]:
 with zipfile.ZipFile(root/f'{name}.zip','w') as z:z.writestr(entry,json.dumps(record))
with zipfile.ZipFile(root/'bad-schema.zip','w') as z:z.writestr('track.json','{}')
with zipfile.ZipFile(root/'bad-symlink.zip','w') as z:
 i=zipfile.ZipInfo('track.json');i.create_system=3;i.external_attr=0o120777<<16;z.writestr(i,'/etc/passwd')
raw=(root/'good-deflated.zip').read_bytes();(root/'bad-truncated.zip').write_bytes(raw[:-12])
bad=bytearray(raw);local=bad.find(b'PK\x03\x04');central=bad.find(b'PK\x01\x02');struct.pack_into('<H',bad,local+6,1);struct.pack_into('<H',bad,central+8,1);(root/'bad-encrypted.zip').write_bytes(bad)
bad=bytearray(raw);struct.pack_into('<I',bad,central+24,9*1024*1024);(root/'bad-oversize.zip').write_bytes(bad)
(root/'good-json.json').write_text(json.dumps(record));(root/'bad-json.json').write_text('{incomplete')
