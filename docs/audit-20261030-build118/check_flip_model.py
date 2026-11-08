"""Read-only source assertions + translated model witnesses, not iOS runtime tests."""
from pathlib import Path
import hashlib,json,re
ROOT=Path(__file__).resolve().parents[2]
OUT=Path(__file__).resolve().parent
paths=['SourceReadSwift/Features/Reader/CoverPageReaderView.swift',
       'SourceReadSwift/Features/Reader/ReaderView.swift',
       'SourceReadSwift/Features/Reader/ReaderPagedNavigationPolicy.swift',
       'SourceReadSwift/Features/Reader/ReaderSettingsModels.swift',
       'SourceReadSwift/Features/Reader/PageCurlReaderView.swift']
src={p:(ROOT/p).read_text(encoding='utf-8') for p in paths}
cover,reader,policy,settings,curl=[src[p] for p in paths]
checks={
 'apply_guard_ignores_neighbours':'guard identityChanged || revisionChanged || styleChanged || !didInstallContent else { return }' in cover,
 'five_slot_content_size':'width: width * CGFloat(slotCount)' in cover,
 'no_target_offset_clamp':'scrollViewWillEndDragging' not in cover,
 'commits_one_step_each_direction':'commit(-1, width: width)' in cover and 'commit(1, width: width)' in cover,
 'page_curl_legacy_only_declaration':reader.count('pageCurlReaderContent')==1,
 'translation_cover_same_route':'case .cover, .pageTurn:' in reader,
 'legacy_prewarm_guard_before_enqueue':'guard !isUserInteracting else { return }' in curl,
}
assert all(checks.values()),checks
def outcome(shift,width,prev=True,nxt=True):
 width=max(width,1)
 if shift < -width*.5:return 'previous' if prev else 'springBack'
 if shift > width*.5 and nxt:return 'next'
 return 'springBack'
witnesses=[]
for slot in (0,1,2,3,4):
 decision=outcome((slot-2)*390,390)
 logical_delta={'previous':-1,'springBack':0,'next':1}[decision]
 witnesses.append(dict(physical_slot=slot,visible_page_delta=slot-2,settle=decision,committed_delta=logical_delta,agrees=(slot-2)==logical_delta))
before=['P-2','P-1','P','placeholder+1','placeholder+2']
after=['P-2','P-1','P','real+1','real+2']
guard_enters=(before[2]!=after[2]) or False or False or False
assert not guard_enters and before!=after
test_files=list((ROOT/'SourceReadSwiftTests').rglob('*.swift'))
controller_tests=[str(p.relative_to(ROOT)).replace('\\','/') for p in test_files if 'CoverPageHostController' in p.read_text(encoding='utf-8')]
result={'method':'Python translation of source predicates + static assertions; NOT Swift/UIKit execution',
 'source_assertions':checks,'neighbour_change_witness':{'before':before,'requested_after':after,'guard_enters':guard_enters,'installed_after':before},
 'slot_landing_witnesses':witnesses,'test_files_naming_cover_host':controller_tests,
 'source_sha256':{p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in paths}}
(OUT/'flip-model-results.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(result,ensure_ascii=False,indent=2))
