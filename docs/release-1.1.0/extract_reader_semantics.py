"""Read-only focused semantic review of committed reader baseline."""
from pathlib import Path
import hashlib
import json
import subprocess

ROOT = Path('D:/Gemini反重力/SourceReadSwift2')
BASE = '71156be1ac148d6328dccc2844ed2555a41313b0'
READER = 'SourceReadSwift/Features/Reader/'
GATEWAY = 'SourceReadSwift/Features/Bookshelf/BookshelfReaderGatewayView.swift'
DETAIL = 'SourceReadSwift/Features/Discover/BookDetailView.swift'
files = [READER + n for n in ['ReaderView.swift', 'NativeReaderTextView.swift',
    'ReaderPagedNavigationPolicy.swift', 'ReaderChapterWindow.swift', 'ReaderPageSelection.swift',
    'ReaderPageTextView.swift', 'ReaderTextPagePaginator.swift', 'WebScrollReaderView.swift',
    'WebReaderDocument.swift']] + [GATEWAY, DETAIL,
    'SourceReadSwift/Core/Models/BookshelfModels.swift',
    'SourceReadSwift/Core/Storage/BookshelfStore.swift']
blobs = {p: subprocess.check_output(['git', 'show', BASE + ':' + p], cwd=ROOT) for p in files}

def ev(file, start, end=None):
    return {'file': str(ROOT / file).replace('\\', '/'), 'line': start, 'end_line': end or start,
            'commit': BASE}

nodes = []
def node(id, label, file, line, rationale=None):
    n = {'id': id, 'label': label, 'file_type': 'code', 'source_file': file,
         'source_location': str(line), 'source_url': None, 'captured_at': None,
         'author': None, 'contributor': None}
    if rationale: n['rationale'] = rationale
    nodes.append(n)

node('reader_toc_scroll', 'ReaderView.scrollTocToCurrentChapter', READER+'ReaderView.swift', 4894)
node('reader_toc_list', 'ReaderView.tocList', READER+'ReaderView.swift', 4738)
node('reader_chapter_select', 'ReaderView.selectChapter', READER+'ReaderView.swift', 5249)
node('reader_activate', 'ReaderView.activateWindowChapter', READER+'ReaderView.swift', 5138)
node('reader_jump', 'ReaderView.jumpToWindowChapter', READER+'ReaderView.swift', 5151)
node('reader_jump_flat', 'ReaderView.jumpToWindowFlat', READER+'ReaderView.swift', 5124)
node('reader_visible', 'ReaderView.updateVisibleParagraphInScroll', READER+'ReaderView.swift', 2513)
node('reader_flat_layout', 'ReaderChapterWindowPolicy.Layout', READER+'ReaderChapterWindow.swift', 201)
node('reader_web_bridge', 'WebScrollReaderView.Coordinator', READER+'WebScrollReaderView.swift', 286)
node('reader_web_update', 'WebScrollReaderView.Coordinator.update', READER+'WebScrollReaderView.swift', 158)
node('reader_web_content', 'WebScrollReaderView.Coordinator.pushContent', READER+'WebScrollReaderView.swift', 216)
node('reader_web_jump', 'WebScrollReaderView.evaluateScrollTarget', READER+'WebScrollReaderView.swift', 244)
node('reader_js_scroll', 'WebReaderDocument.scrollToFlat', READER+'WebReaderDocument.swift', 1158)
node('reader_js_visible', 'WebReaderDocument.onScroll', READER+'WebReaderDocument.swift', 1041)
node('reader_js_content', 'WebReaderDocument.setContent', READER+'WebReaderDocument.swift', 911)
node('reader_js_tap', 'WebReaderDocument pointer-up tap arbitration', READER+'WebReaderDocument.swift', 1102)
node('reader_tap', 'ReaderView.handleReaderTap', READER+'ReaderView.swift', 5329)
node('reader_page_selection', 'ReaderPageTextView.updateUIView selection', READER+'ReaderPageTextView.swift', 230)
node('reader_native_selection', 'NativeReaderTextView.updateSelection', READER+'NativeReaderTextView.swift', 407,
     'Legacy/native surface must not be confused with the current WebScrollReaderView route.')
node('reader_heading', 'ReaderView.chapterHeadingStyle', READER+'ReaderView.swift', 219,
     'Default is header, not inline; scroll HTML still renders a chapter h1/h2.')
node('reader_text_paginator', 'ReaderTextPagePaginator.paginate', READER+'ReaderTextPagePaginator.swift', 22)
node('reader_page_restore', 'ReaderPageRestoration.index', READER+'ReaderPageSelection.swift', 61)
node('reader_paged_policy', 'ReaderPagedNavigationPolicy', READER+'ReaderPagedNavigationPolicy.swift', 188)
node('reader_gateway', 'BookshelfReaderGatewayView.localReader', GATEWAY, 236)
node('reader_detail_sheet', 'BookshelfReaderGatewayView book detail sheet', GATEWAY, 57)
node('reader_detail_local', 'BookDetailView local metadata load', DETAIL, 766)
node('reader_detail_links', 'BookDetailView local reader destinations', DETAIL, 109)
node('reader_local_resolver', 'BookshelfStore.localBook', 'SourceReadSwift/Core/Storage/BookshelfStore.swift', 46)

edges = []
def edge(source, target, relation, file, line, confidence='EXTRACTED', score=1.0):
    edges.append({'source': source, 'target': target, 'relation': relation,
                  'confidence': confidence, 'confidence_score': score, 'source_file': file,
                  'source_location': str(line), 'weight': 1.0})

edge('reader_toc_list', 'reader_toc_scroll', 'calls', READER+'ReaderView.swift', 4851)
edge('reader_toc_list', 'reader_chapter_select', 'calls', READER+'ReaderView.swift', 4798)
edge('reader_chapter_select', 'reader_activate', 'calls', READER+'ReaderView.swift', 5256)
edge('reader_activate', 'reader_jump', 'calls', READER+'ReaderView.swift', 5145)
edge('reader_jump', 'reader_jump_flat', 'calls', READER+'ReaderView.swift', 5161)
edge('reader_jump_flat', 'reader_web_jump', 'shares_data_with', READER+'ReaderView.swift', 5129)
edge('reader_web_update', 'reader_web_content', 'calls', READER+'WebScrollReaderView.swift', 176)
edge('reader_web_content', 'reader_js_content', 'calls', READER+'WebScrollReaderView.swift', 222)
edge('reader_web_jump', 'reader_js_scroll', 'calls', READER+'WebScrollReaderView.swift', 247)
edge('reader_js_scroll', 'reader_web_bridge', 'references', READER+'WebReaderDocument.swift', 1171)
edge('reader_js_visible', 'reader_web_bridge', 'references', READER+'WebReaderDocument.swift', 1055)
edge('reader_web_bridge', 'reader_visible', 'calls', READER+'ReaderView.swift', 1627)
edge('reader_visible', 'reader_flat_layout', 'shares_data_with', READER+'ReaderView.swift', 2514)
edge('reader_js_content', 'reader_flat_layout', 'shares_data_with', READER+'WebReaderDocument.swift', 922)
edge('reader_js_tap', 'reader_tap', 'calls', READER+'WebScrollReaderView.swift', 333)
edge('reader_page_selection', 'reader_tap', 'conceptually_related_to', READER+'ReaderView.swift', 826, 'INFERRED', .94)
edge('reader_native_selection', 'reader_page_selection', 'semantically_similar_to', READER+'NativeReaderTextView.swift', 407, 'INFERRED', .87)
edge('reader_heading', 'reader_text_paginator', 'shares_data_with', READER+'ReaderView.swift', 6213)
edge('reader_page_restore', 'reader_flat_layout', 'conceptually_related_to', READER+'ReaderPageSelection.swift', 61, 'INFERRED', .86)
edge('reader_paged_policy', 'reader_page_restore', 'semantically_similar_to', READER+'ReaderPagedNavigationPolicy.swift', 188, 'INFERRED', .82)
edge('reader_gateway', 'reader_detail_sheet', 'references', GATEWAY, 267)
edge('reader_detail_sheet', 'reader_detail_local', 'calls', GATEWAY, 59)
edge('reader_detail_local', 'reader_local_resolver', 'calls', DETAIL, 35)
edge('reader_detail_links', 'reader_gateway', 'calls', DETAIL, 111)
edge('reader_detail_local', 'reader_detail_links', 'shares_data_with', DETAIL, 782)

findings = [
 {'id':'R110-TOC-001','severity':'P1','claim':'目录初次拖动回弹具有明确源码原因：打开目录后仍有多次无条件自动定位，最晚 1.6 秒，会覆盖用户已发生的拖动。',
  'confidence':'INFERRED','confidence_score':.98,'observed':'EXTRACTED scheduling of six delayed scrollTo calls; user gesture competition not reproduced on a device here.',
  'evidence':[ev(READER+'ReaderView.swift',4848,4860),ev(READER+'ReaderView.swift',4894,4912)],
  'recommended_fix':'每次目录展示只执行一次受展示 generation 保护的初始定位；若需布局重试，在用户开始拖动/更换筛选/离开目录时取消任务，禁止无条件计时重定位。',
  'verification':['iOS 16: 打开 1000 章目录，在 0.1/0.4/0.9 秒开始拖动，持续超过 1.6 秒，确认不被拉回。','目录定位应命中当前章；搜索/倒序仍能合理定位；离开后待执行任务不得触发。']},
 {'id':'R110-JUMP-002','severity':'P1','claim':'滚动桥接只传可变 flat index，缺内容 revision 与章节本地坐标，旧 DOM visible 消息可能在新窗口映射中写回错误章节；任何 visible 还会清除未落地的跳转。',
  'confidence':'INFERRED','confidence_score':.95,'observed':'Bridge payload and unconditional request clearing are explicit source; reported 29 -> 22 transition is not locally reproduced.',
  'evidence':[ev(READER+'WebScrollReaderView.swift',158,181),ev(READER+'WebReaderDocument.swift',1041,1056),ev(READER+'WebScrollReaderView.swift',307,311),ev(READER+'ReaderView.swift',1623,1627),ev(READER+'ReaderView.swift',2513,2525)],
  'recommended_fix':'DOM setContent 与 visible 带相同 content revision；visible 同时返回 chapter key/local paragraph，Swift 校验 revision 后按稳定坐标解析。显式跳章等待匹配的落地回执，不被旧 visible 清除。',
  'verification':['构造旧内容 visible 在窗口重排后到达，断言新 chapter cursor 不变。','29 章跳转过程中注入旧 22 章 visible；目标必须保留，落地后第一次滑动仍在 29 章。','目录连续 A/B 快速跳章并伴随后台预取、上方章节裁剪；校验可见章节/进度/缓存游标一致。']},
 {'id':'R110-JUMP-003','severity':'P1','claim':'scroll-applied 回执没有携带 request ID；旧请求 A 回执会被视为当前 pending B 已完成并清空 B。',
  'confidence':'EXTRACTED','confidence_score':1.0,
  'evidence':[ev(READER+'WebScrollReaderView.swift',235,248),ev(READER+'WebReaderDocument.swift',1158,1171),ev(READER+'WebScrollReaderView.swift',334,338)],
  'recommended_fix':'scrollToFlat 参数包含 request key/content revision，scroll-applied 原样回传；Swift 仅当两者与当前 pending 匹配时清空。异步 smooth 滚动在真正到达目标后再 ack，或明确区分 accepted/landed。',
  'verification':['pending A -> pending B -> ack A：B 必须仍 pending；ack B 仅完成一次。','scroll-miss、content-ready 重试也必须匹配同一请求与内容 revision。']},
 {'id':'R110-SELECT-004','severity':'P1','claim':'文字选择开启并未成为点击区的统一优先级条件。分页 SpatialTapGesture 和 handleReaderTap 不检查选择状态；滚动只检查当前非折叠 selection，尚未形成选区的多次轻点仍可触发翻页。',
  'confidence':'INFERRED','confidence_score':.96,
  'evidence':[ev(READER+'ReaderView.swift',825,834),ev(READER+'ReaderView.swift',2772,2775),ev(READER+'ReaderView.swift',5329,5353),ev(READER+'WebReaderDocument.swift',1102,1123)],
  'recommended_fix':'建立共享手势仲裁策略：开启正文选择时，正文区 UIKit/WebKit 选择手势优先，屏蔽正文页切换点击；菜单使用独立明确按钮或非正文带，不用全屏抢手势。保留滑动翻页与文本选中拖柄的边界策略。',
  'verification':['iOS 16: 四种阅读模式测试长按、双击选词、拖动选择句柄、复制。','选择关闭时 3x3 点击区回归；开启选择时正文轻点/双击不得翻页，菜单仍可通过明确入口打开。']},
 {'id':'R110-TITLE-005','severity':'P2','claim':'分页大标题缺失是默认 heading=.header 的显式行为，滚动 h1/h2 与分页不一致；不是分页正文测量失效。',
  'confidence':'EXTRACTED','confidence_score':1.0,
  'evidence':[ev(READER+'ReaderView.swift',219),ev(READER+'ReaderView.swift',258,259),ev(READER+'ReaderTextPagePaginator.swift',22,25),ev(READER+'ReaderView.swift',3063,3074)],
  'recommended_fix':'用户期望首章/新章正文大标题时，将默认及旧默认迁移为 inline；保留显式选择页眉模式。正文大标题只在章首，续页仍可显示小页眉。先明确迁移键避免覆盖用户已有偏好。',
  'verification':['全新安装与从 119 升级：滚动/覆盖/平移/仿真首章大标题一致。','超长标题跨页及 Unicode/RTL 守恒回归，不重复/不漏标题，原 119 正文行高和底部不裁字测试不削弱。']},
 {'id':'R110-LOCAL-006','severity':'P1','claim':'用户报告本地详情闪退尚无本地崩溃栈证实根因。可确认入口复用完整 BookDetailView，包含重新进入重型本地 reader 的 NavigationLink；不能归咎于 local:// 走网络或 id 未解析。',
  'confidence':'AMBIGUOUS','confidence_score':.25,
  'evidence':[ev(GATEWAY,57,60),ev(GATEWAY,267,269),ev(DETAIL,30,43),ev(DETAIL,109,119),ev(DETAIL,672,679),ev(DETAIL,766,791)],
  'recommended_fix':'安全隔离：新增轻量只读 LocalBookMetadataSheet(snapshot) 用于阅读器右上详情，只呈现书名/作者/格式/章节数/字数/导入信息，不附 reader NavigationLink、不注入全文、不重建 gateway。书架入口保留完整详情功能。若详情内需跳章，通过受控回调关闭 sheet 后向既有 reader 发显式跳转，不创建第二个 reader。',
  'verification':['iOS 16 原生 UI: TXT/EPUB/单章节 localContent 及超大本地书，阅读器详情反复开关 20 次，不触发新 reader 实例/分页任务。','使用 crash log/内存警告/主线程栈区分 stack overflow、jetsam、watchdog；未收集前不得宣称确定根因。','保留书架完整详情的继续阅读/章节导航与本地 id 兼容测试。']}
]

hyperedges = [
 {'id':'reader_jump_protocol','label':'Chapter jump atomicity across native model / web document / acknowledgement',
  'nodes':['reader_jump_flat','reader_web_jump','reader_js_scroll','reader_web_bridge','reader_visible','reader_flat_layout'],
  'relation':'participate_in','confidence':'EXTRACTED','confidence_score':1.0,'source_file':READER+'WebScrollReaderView.swift'},
 {'id':'reader_selection_arbitration','label':'Selection-first gesture arbitration in paged and web surfaces',
  'nodes':['reader_page_selection','reader_tap','reader_js_tap','reader_native_selection'],
  'relation':'participate_in','confidence':'INFERRED','confidence_score':.93,'source_file':READER+'ReaderView.swift'},
 {'id':'reader_local_detail_boundary','label':'Local reader -> detail -> reader navigation isolation boundary',
  'nodes':['reader_gateway','reader_detail_sheet','reader_detail_links','reader_detail_local'],
  'relation':'form','confidence':'EXTRACTED','confidence_score':1.0,'source_file':GATEWAY}
]

old = json.loads((ROOT/'docs/audit-20261030-build118/graph.json').read_text(encoding='utf-8'))
old_nodes = old.get('nodes', [])
old_edges = old.get('links', old.get('edges', []))
orientation = [n for n in old_nodes if any(t in str(n.get('label', '')) for t in ['ReaderView','ReaderChapterWindow','BookDetailView'])][:12]

ids = {n['id'] for n in nodes}
assert all(e['source'] in ids and e['target'] in ids for e in edges)
assert all(all(n in ids for n in h['nodes']) for h in hyperedges)
for f in findings:
    for e in f['evidence']:
        relative = Path(e['file']).relative_to(ROOT).as_posix()
        assert 1 <= e['line'] <= e['end_line'] <= len(blobs[relative].splitlines()), e

result = {'schema':'graphify-semantic-fragment-v1','baseline_commit':BASE,
 'scope':'Focused read-only semantic extraction; not a device crash reproduction or performance result.',
 'nodes':nodes,'edges':edges,'hyperedges':hyperedges,'findings':findings,
 'source_manifest':[{'file':p,'sha256_git_blob_content':hashlib.sha256(b).hexdigest(),
                     'lines':len(b.splitlines())} for p,b in blobs.items()],
 'prior_graph_orientation':{'file':'docs/audit-20261030-build118/graph.json',
     'nodes':len(old_nodes),'edges':len(old_edges),'matching_nodes':orientation},
 'validation':{'dangling_node_references':0,'evidence_line_ranges':'verified against committed source',
     'swift_files_modified':False,'device_tests':'NOT RUN'},
 'input_tokens':0,'output_tokens':0,'token_accounting':'Tool/runtime does not expose exact subtask token usage; zero means unavailable, not free.'}
output = ROOT/'docs/release-1.1.0/graph-reader.json'
output.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'output':str(output),'nodes':len(nodes),'edges':len(edges),'hyperedges':len(hyperedges),
                  'findings':len(findings),'baseline':BASE,'business_code_modified':False},ensure_ascii=False))
