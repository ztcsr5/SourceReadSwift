"""Executable translations of source-level invariants; NOT Swift/UIKit tests."""
import json
from pathlib import Path

def content_signature(chapter, title, paragraphs):
    # Actual code uses hashValue on endpoints. Equal endpoints necessarily hash equally.
    return chapter, title, len(paragraphs), paragraphs[0], paragraphs[-1]

def page_key(chapter, ordinal, first, speech, layout_theme_revision):
    return f'b-{chapter}-{ordinal}-{first}|{speech}|{layout_theme_revision}'

results = []
old = ['first', 'OLD MIDDLE', 'last']
new = ['first', 'NEW MIDDLE', 'last']
assert old != new and content_signature(2, 'title', old) == content_signature(2, 'title', new)
results.append({'check':'middle-edit-cache-collision','result':'REPRODUCED','old':old,'new':new})

key_before = page_key(2, 0, 0, '-1-0', 'same-layout-theme')
key_after = page_key(2, 0, 0, '-1-0', 'same-layout-theme')
old_pages = ['ABCD', 'EFGH']
new_pages = ['ABCDEF', 'GH']
cache = {key_before: old_pages[0]}
rendered_first = cache.get(key_after, new_pages[0])
assert rendered_first == 'ABCD' and rendered_first != new_pages[0]
results.append({'check':'geometry-repagination-stale-render-key','result':'REPRODUCED',
                'old_partition':old_pages,'new_partition':new_pages,'first_page_returned':rendered_first,
                'note':'ABCD/ABCDEF are illustrative partitions, not TextKit output.'})

radius = 5
eligible_for_placeholder = [i for i in range(-radius, radius+1) if abs(i) > radius]
assert eligible_for_placeholder == []
results.append({'check':'synchronous-radius-equals-window','result':'REPRODUCED',
                'loaded_chapters':11,'deferred_inside_window':0})

line_spacing, paragraph_spacing, boundaries = 18, 0, 10
engine_gap = paragraph_spacing
builder_contract_gap = line_spacing + max(0, paragraph_spacing-line_spacing)
assert builder_contract_gap - engine_gap == 18
results.append({'check':'spacing-contract-with-paragraph-less-than-line','result':'MODEL_ONLY',
                'excess_for_10_boundaries':boundaries*(builder_contract_gap-engine_gap),
                'note':'Uses the TextKit spacing contract asserted by repository tests; UIKit measurement NOT RUN.'})

viewport_height, top, bottom = 200, 59, 34
body_top = top + 34
footer_top = viewport_height-max(bottom,14)-14
body_bottom = max(footer_top-10,body_top+1)
content_height = max(body_bottom-body_top,120)
assert body_top+content_height > footer_top
results.append({'check':'minimum-body-height-overlaps-footer','result':'REPRODUCED',
                'body_end':body_top+content_height,'footer_top':footer_top})

output={'runtime':'Python source-level model; no Swift/UIKit execution','checks':results}
print(json.dumps(output,ensure_ascii=False,indent=2))
Path(__file__).with_name('pagination-model-results.json').write_text(json.dumps(output,ensure_ascii=False,indent=2),encoding='utf-8')
