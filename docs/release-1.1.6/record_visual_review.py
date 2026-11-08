import hashlib, json
import ci
folder=ci.OUT/'native-evidence'/ci.ci.HEAD
names=[f'{runtime}-{sheet}.jpg' for runtime in ['ios18-ui','ios26-ui'] for sheet in ['themes','reader-and-navigation','regression']]
assert len(json.loads((folder/'screen-index.json').read_text(encoding='utf8')))==54
checks=json.loads((folder/'visual-pixel-checks.json').read_text(encoding='utf8'))
assert checks['head']==ci.ci.HEAD and len(checks['checks'])==28
record={
 'head':ci.ci.HEAD, 'status':'PASS',
 'review':'Assistant visually inspected the six contact sheets after viewing actual current-commit tool images. No synthetic UI composition.',
 'scope':'50 mounted UIKit/SwiftUI screenshots on iOS18 and iOS26 summarized by six contact sheets; four additional real WebKit snapshots retained. 28 scale-correct pixel checks. This is selected-fixture visual QA, not every app screen or physical-device performance acceptance.',
 'findings':[
  'All six themes render distinct paper/card/geometry/typography in real light and dark appearances.',
  'Reader white and bamboo have visible body text; menu top and safe area mask body; no global bottom tab leaks into these reader fixtures.',
  '320-point legacy tabs retain three labels and detached search without collision.',
  'Home/settings/source regressions retain compact layout; accessibility labels wrap rather than clipping the viewed primary rows.',
  'iOS26 home retains native single bottom-tab chrome; native runtime suite verifies ownership/teardown.',
  'Reading illustrations and Settings vector brand mark are visible. P5 competitor homepage has not been implemented.'
 ],
 'sheets':[{'path':str(folder/name),'sha256':hashlib.sha256((folder/name).read_bytes()).hexdigest()} for name in names]
}
(folder/'visual-review.json').write_text(json.dumps(record,ensure_ascii=False,indent=2),encoding='utf8')
print('Recorded current-commit visual review:',folder/'visual-review.json')
