from pathlib import Path
import hashlib,json,subprocess
root=Path(__file__).resolve().parents[2]
out=Path('F:/SourceReadSwift/release-1.1.7')
head=subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip()
receipt=json.loads((out/'CHECKPOINT.json').read_text(encoding='utf-8'))
assert receipt['head']==head
assert len(receipt['native'])==3 and all(j['status']=='completed' and j['conclusion']=='success' for j in receipt['native'])
assert any(j['counts']==['1540','2','0'] for j in receipt['native'])
assert any(j['counts']==['108','','0'] for j in receipt['native'])
html=root/'SourceReadSwift/Resources/LANWorkbench.html'
preview=out/'lan-ui/index.html'
assert html.read_bytes()==preview.read_bytes()
main=json.loads((out/'lan-ui/VERIFICATION.json').read_text(encoding='utf-8'))
extra=json.loads((out/'lan-ui/VERIFICATION-files-cli.json').read_text(encoding='utf-8'))
assert len(main['checks'])==27 and len(extra['checks'])==10
receipt['automated_checkpoint_items']=[14,15,16]
receipt['browser_fixture_checks']=37
receipt['html_sha256']=hashlib.sha256(html.read_bytes()).hexdigest()
receipt['next_item']=17
receipt['next_scope']='Global theme collaboration including source login center, rule health/playground, purification, all secondary pages; actual OS capability gating. Then18 backgrounds,19 custom wallpaper,20 home reading hero.'
receipt['native_screenshots']=str(out/'native-evidence'/head/'release117-screen-index.json')
receipt['new_screenshot_pixel_review']='Pending; automated geometry assertions and screenshot creation are not pixel acceptance.'
(out/'CHECKPOINT.json').write_text(json.dumps(receipt,ensure_ascii=False,indent=2),encoding='utf-8')
(root/'docs/release-1.1.7/LATEST-VERIFIED.json').write_text(json.dumps(receipt,ensure_ascii=False,indent=2),encoding='utf-8')
with (out/'VERIFICATION.txt').open('a',encoding='utf-8') as stream:
 stream.write('\nAutomated checkpoint items14–16 passed;37 local fake-API browser/file/CLI checks.\n')
 stream.write('Final HTML SHA256 '+receipt['html_sha256']+'\n')
 stream.write('Latest native screenshots saved, pixel acceptance pending. Next item17; not a formal IPA release.\n')
print('PASS final checkpoint',head,'native1540/2skip/0fail; iOS26 108/0fail; browser37; next17')
