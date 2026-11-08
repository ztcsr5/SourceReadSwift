import json,hashlib
from pathlib import Path
root=Path(__file__).resolve().parents[2]
src=Path('F:/SourceReadSwift/release-1.1.6/source-audit/comic-sources.json')
rows=json.loads(src.read_text(encoding='utf8'))
# The reviewed 31-source subset contains author configuration, not saved login
# state. Even comments can be executable configuration: one base64 JS rule
# checks source.bookSourceComment. Preserve the exact reviewed author fields.
# Fail closed if a later export adds unreviewed state/credential fields.
keys={'bookSourceComment','bookSourceGroup','bookSourceName','bookSourceType','bookSourceUrl','bookUrlPattern','customButton','customOrder','enabled','enabledCookieJar','enabledExplore','eventListener','exploreUrl','header','jsLib','lastUpdateTime','loginUi','loginUrl','respondTime','ruleBookInfo','ruleContent','ruleExplore','ruleSearch','ruleToc','searchUrl','weight'}
assert all(set(row) <= keys for row in rows), 'Review new fields before copying source definitions'
projected=rows
out=root/'SourceReadSwiftTests/Fixtures/comic-sources-20261101.json'
out.write_text(json.dumps(projected,ensure_ascii=False,indent=2),encoding='utf8')
print('Comic rule fixtures',len(projected),'bytes',out.stat().st_size,'sha256',hashlib.sha256(out.read_bytes()).hexdigest())
