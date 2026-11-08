from pathlib import Path
import hashlib,json,subprocess
O=Path('F:/SourceReadSwift/release-1.1.6')
r=json.loads((O/'delivery-verification.json').read_text(encoding='utf8'))
for key,path in r['artifacts'].items(): assert Path(path).exists(),(key,path)
assert hashlib.sha256(Path(r['ipa']['path']).read_bytes()).hexdigest()==r['ipa']['sha256']
assert not subprocess.check_output(['git','diff','--name-only']).strip()
assert not subprocess.check_output(['git','diff','--cached','--name-only']).strip()
(O/'RECOVERY-LATEST.md').write_bytes((O/'RECOVERY-COMPLETE.md').read_bytes())
(O/'RECOVERY-IN-PROGRESS.md').write_text('Superseded by RECOVERY-COMPLETE.md. Release1.1.6 build127 delivered; consult delivery-verification.json for real scope and remaining failures.\n',encoding='utf8')
print('PASS desktop IPA, four artifacts, exact SHA, clean tracked worktree, current recovery checkpoint.')
