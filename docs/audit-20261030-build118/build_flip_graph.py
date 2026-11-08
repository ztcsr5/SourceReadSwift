from pathlib import Path
import json
OUT=Path(__file__).resolve().parent
BASE='SourceReadSwift/Features/Reader/'
nodes=[];edges=[]
def node(i,label,file,loc,rationale=''):
 d=dict(id=i,label=label,file_type='code',source_file=BASE+file,source_location=loc,confidence='EXTRACTED',confidence_score=1.0)
 if rationale:d['rationale']=rationale
 nodes.append(d)
def edge(a,b,relation,file,loc,confidence='EXTRACTED',score=1.0):
 edges.append(dict(source=a,target=b,relation=relation,source_file=BASE+file,source_location=loc,confidence=confidence,confidence_score=score))
node('flip:route','ReaderView.pagedReaderContent','ReaderView.swift','2551-2563')
node('flip:cover','ReaderView.coverPagedReaderContent','ReaderView.swift','2721-2775')
node('flip:simulated','ReaderView.flipPagedReaderContent','ReaderView.swift','2579-2630')
node('flip:legacy','ReaderView.pageCurlReaderContent (unreferenced declaration)','ReaderView.swift','2632-2666')
node('flip:host','CoverPageHostController','CoverPageReaderView.swift','131-528')
node('flip:apply','CoverPageHostController.apply','CoverPageReaderView.swift','223-335','Current identity/revision/style gate precedes neighbour identity comparison.')
node('flip:revision','ReaderView.readerPageRevisionKey','ReaderView.swift','689-701','Excludes neighbouring window sections so prefetch does not invalidate existing pages.')
node('flip:frames','CoverPageHostController.installFramesIfNeeded','CoverPageReaderView.swift','395-430')
node('flip:settle','CoverPageHostController.settle','CoverPageReaderView.swift','469-488')
node('flip:policy','ReaderCoverSettlePolicy.outcome(shift:)','ReaderPagedNavigationPolicy.swift','262-275')
node('flip:commit','ReaderView.commitCoverTurn','ReaderView.swift','2785-2807')
node('flip:prewarm','CoverPageHostController.prewarmNeighbourSlots','CoverPageReaderView.swift','353-360')
node('flip:gesture','CoverPageHostController.scrollViewWillBeginDragging','CoverPageReaderView.swift','446-453')
node('flip:transform','ReaderFlipTransitionPolicy.rotationAngle','ReaderFlipTransitionPolicy.swift','13-15')
node('flip:legacy-prewarm','PageCurlReaderView.Coordinator.prewarm','PageCurlReaderView.swift','254-319')
edge('flip:route','flip:cover','routes_cover_and_pageTurn_to','ReaderView.swift','2558-2559')
edge('flip:route','flip:simulated','routes_pageCurl_to','ReaderView.swift','2560-2561')
edge('flip:cover','flip:host','creates_via_UIViewControllerRepresentable','ReaderView.swift','2739-2762')
edge('flip:simulated','flip:host','creates_with_flip_style','ReaderView.swift','2592-2616')
edge('flip:cover','flip:revision','uses_as_contentRevision','ReaderView.swift','2741')
edge('flip:simulated','flip:revision','uses_as_contentRevision','ReaderView.swift','2594')
edge('flip:host','flip:apply','owns','CoverPageReaderView.swift','223-335')
edge('flip:apply','flip:frames','calls','CoverPageReaderView.swift','330')
edge('flip:apply','flip:prewarm','calls','CoverPageReaderView.swift','332-333')
edge('flip:settle','flip:policy','calls','CoverPageReaderView.swift','475-480')
edge('flip:settle','flip:commit','invokes_indirectly_via_onCommit','CoverPageReaderView.swift','481-494')
edge('flip:host','flip:transform','calls','CoverPageReaderView.swift','439')
edge('flip:frames','flip:commit','five_slot_visible_delta_can_disagree_with_single_step_commit','CoverPageReaderView.swift','401-404;481-484','INFERRED',0.95)
edge('flip:gesture','flip:prewarm','can_overlap_queued_main_thread_warmup','CoverPageReaderView.swift','353-359;446-452','INFERRED',0.85)
edge('flip:prewarm','flip:legacy-prewarm','shares_execution_time_interaction_guard_gap','CoverPageReaderView.swift','353-359','INFERRED',0.92)
result=dict(nodes=nodes,edges=edges,hyperedges=[],input_tokens=0,output_tokens=0,metadata={'scope':'Read-only manual semantic extraction; no runtime reproduction; no separate LLM API cost measured','source_baseline':'flip-model-results.json'})
ids={n['id'] for n in nodes}
assert all(e['source'] in ids and e['target'] in ids for e in edges)
assert all('confidence_score' in x and 'source_file' in x and 'source_location' in x for x in nodes+edges)
(OUT/'graph-flip.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
print(f'graph-flip.json: {len(nodes)} nodes, {len(edges)} edges; schema checks passed')
