"""Auxiliary Python fixtures only; native NSRegularExpression tests remain required."""
from pathlib import Path
import json, re, yaml
root=Path(__file__).resolve().parents[2]
text=(root/'SourceReadSwift/Core/Storage/PurifyRuleStore.swift').read_text(encoding='utf8')
tail=text[text.index('id: "navigation-lines"'):text.index('\n    ]\n}')]
patterns=[]
for line in tail.splitlines():
    value=line.strip().rstrip(',')
    if value.startswith('"') and value.endswith('"'):
        decoded=json.loads(value)
        if decoded.endswith('##'): patterns.append(decoded[:-2])
assert len(patterns)==6
compiled=[re.compile(p) for p in patterns]
def apply(value):
    for regex in compiled: value=regex.sub('',value)
    return value
fixtures=[
 ('正文甲\r\n上一章\r\n下一页\r\n（第 1 / 3 页）\r\n正文乙\r\n下一章','正文甲\r\n正文乙\r\n'),
 ('正文\n手机用户请访问：https://example.invalid/book\n&nbsp;<br />\n这是&nbsp;原文\n末\x01段\n','正文\n这是&nbsp;原文\n末段\n'),
 ('“下一章。”\n他说上一页。\n下一章 他回家了\n正文 https://example.invalid\n','“下一章。”\n他说上一页。\n下一章 他回家了\n正文 https://example.invalid\n')
]
for raw, expected in fixtures: assert apply(raw)==expected, repr(apply(raw))
workflow=yaml.safe_load((root/'.github/workflows/ios.yml').read_text(encoding='utf8'))
assert 'jobs' in workflow and 'native-tabs' in workflow['jobs']
print('PASS auxiliary Python regex fixtures:',len(fixtures),'patterns:',len(patterns),'workflow YAML parsed. NOT native runtime proof.')
