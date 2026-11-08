from pathlib import Path
from PIL import Image
import hashlib,json,shutil,subprocess,sys
import ci

O,H=ci.OUT,ci.ci.HEAD
folder=O/'native-evidence'/H
screens=[]
for runtime in ['ios18-ui','ios26-ui']:
    p=folder/runtime
    manifest=json.loads((p/'manifest.json').read_text(encoding='utf8'))
    for test in manifest:
        for attachment in test['attachments']:
            f=p/attachment['exportedFileName']
            screens.append({'runtime':runtime,'name':attachment['suggestedHumanReadableName'],
                'path':str(f),'sha256':hashlib.sha256(f.read_bytes()).hexdigest()})
    named=p/'density-settings-dark.png'
    im=Image.open(named).convert('RGBA')
    pixel=im.getpixel((round(im.width*.025),round(im.width*.4)))
    assert pixel[3]>200 and sum(pixel[:3])<240,(runtime,pixel)
assert len(screens)==20
visual={'head':H,'status':'PASS','screenshots':screens,
    'reviewed_contact_sheet':str(folder/'final-layout-review.jpg'),
    'scope':'Agent inspected final representative full home and organization screens, narrow source screens, dark settings and large-text source header on a contact sheet. 20 full screenshot attachments retained, not 20 manual interaction tests.',
    'observations':['Narrow source actions use two columns; accessibility actions stack vertically.',
        'Home has one tab bar, no duplicate empty accessory; content-sized continue card leaves more space for shelf.',
        'Source organization has reachable collapsed group controls, separate pin partitions and visible drag handles.',
        'Both runtime dark screenshots have opaque dark backgrounds; UIKit traits are asserted by XCTest.',
        'Accessibility header key icon stays within its touch target; brand version wraps rather than truncating.'],
    'limitations':['No physical iOS16/17 device acceptance or manual end-to-end drag/swipe performance claim.']}
(folder/'visual-review.json').write_text(json.dumps(visual,ensure_ascii=False,indent=2),encoding='utf8')
ipa=json.loads((O/'IPA_VERIFICATION.json').read_text(encoding='utf8'))
source=Path(ipa['path']);dest=Path('C:/Users/Edc21/Desktop/SourceReadSwift-1.1.5-build126-unsigned.ipa')
assert hashlib.sha256(source.read_bytes()).hexdigest()==ipa['sha256']
if dest.exists(): assert hashlib.sha256(dest.read_bytes()).hexdigest()==ipa['sha256'],'Refusing to replace another build126 IPA'
else: shutil.copyfile(source,dest)
ipa['path']=str(dest)
(O/'IPA_VERIFICATION.json').write_text(json.dumps(ipa,ensure_ascii=False,indent=2),encoding='utf8')
subprocess.run([sys.executable,'-X','utf8',str(Path(__file__).with_name('finalize.py'))],cwd=ci.ROOT,check=True)
checkpoint=f'''# Current verified release

- Project: D:/Gemini反重力/SourceReadSwift2
- Branch: codex/release-1.1.5
- HEAD: {H}
- Release: 1.1.5 / Build126
- IPA: {dest}
- SHA256: {ipa['sha256']}
- Evidence: {O}
- Full suite: 1472 tests, 2 iOS26-only skips, 0 failures (iOS18).
- Native iOS26: 41 tests, 0 skips, 0 failures.
- Changes: compact main app layout; TOC sort goes to first row without current-chapter recenter, both projections cached; source pin/custom ordering/group management persisted independently of parser rules.
- Visual QA: final contact sheet plus real dark/light raster checks; 20 mounted screenshot attachments across both runtimes. Not physical-device acceptance.
- Old 1.1.4 / Build125 IPA preserved. Reader page rendering, exit swipe and delay logic unchanged; previous teardown/tab/exit/header regression tests passed.
- Remaining: user physical iOS16/17 acceptance, including original iOS17.0 iPhone15Pro crash reproduction.
- Helpers: docs/release-1.1.5/*.py (local untracked tooling); tracked RECOVERY.md is initial intent/checkpoint, final truth is delivery-verification.json in evidence folder.
'''
(O/'RECOVERY-COMPLETE.md').write_text(checkpoint,encoding='utf8')
Path('F:/SourceReadSwift/RECOVERY-CURRENT.md').write_text(checkpoint,encoding='utf8')
print('PASS final release, visuals, rollback artifacts and preserved build125')
