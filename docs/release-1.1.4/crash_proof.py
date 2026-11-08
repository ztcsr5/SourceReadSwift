from pathlib import Path
import hashlib,json,shutil,struct,uuid,zipfile
src=Path('D:/QQ游戏/SourceReadSwift-2026-11-01-191131.ips')
out=Path('F:/SourceReadSwift/release-1.1.4/ios17-video');shutil.copy2(src,out/src.name)
raw=src.read_text(encoding='utf8');decoder=json.JSONDecoder();parts=[]
while raw.strip():
 obj,end=decoder.raw_decode(raw.lstrip());parts.append(obj);raw=raw.lstrip()[end:]
h,b=parts[0],parts[-1]
app=next(x for x in b['usedImages'] if x.get('name')=='SourceReadSwift')
ipa=Path('C:/Users/Edc21/Desktop/SourceReadSwift-1.1.3-build124-unsigned.ipa')
with zipfile.ZipFile(ipa) as z:data=z.read('Payload/SourceReadSwift.app/SourceReadSwift')
assert data[:4]==b'\xcf\xfa\xed\xfe'
count=struct.unpack_from('<I',data,16)[0];offset=32;image_uuid=None
for _ in range(count):
 cmd,size=struct.unpack_from('<II',data,offset)
 if cmd==0x1b:image_uuid=str(uuid.UUID(bytes=data[offset+8:offset+24]))
 offset+=size
assert image_uuid==app['uuid'],(image_uuid,app['uuid'])
record={'input':str(src),'sha256':hashlib.sha256(src.read_bytes()).hexdigest(),
 'version':h['app_version'],'build':h['build_version'],'os':h['os_version'],'device':b['modelCode'],
 'exception':b['exception'],'termination':b['termination'],
 'ipa_uuid_verified':image_uuid,'ipa_path':str(ipa),
 'fault_thread':b['faultingThread'],
 'chain':[f.get('symbol',b['usedImages'][f['imageIndex']]['name']+'+'+str(f['imageOffset'])) for f in b['threads'][b['faultingThread']]['frames'][:24]],
 'observed':'Swift exclusivity abort during synchronous handlePageInteraction callback from cover controller dismantle.',
 'fix_plan':'Separate terminal teardown from reusable interaction cancellation; detach callbacks before stopping animation and suppress queued work.'}
(out/'crash-proof.json').write_text(json.dumps(record,ensure_ascii=False,indent=2),encoding='utf8')
print(json.dumps(record,ensure_ascii=False,indent=2))
