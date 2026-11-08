"""Focused, fixed-commit reader review. Never writes application sources."""
from pathlib import Path
import hashlib
import json
import re
import subprocess

ROOT = Path('D:/Gemini反重力/SourceReadSwift2')
BEFORE = '71156be1ac148d6328dccc2844ed2555a41313b0'
AFTER = subprocess.check_output(['git', 'rev-parse', '64c7296'], cwd=ROOT, text=True).strip()
P = 'SourceReadSwift/Features/Reader/'
names = ['ReaderView.swift','ReaderTextPagePaginator.swift','ReaderPageTextView.swift',
         'WebScrollReaderView.swift','WebReaderDocument.swift','ReaderWebMessagePolicy.swift']
sources = {name:subprocess.check_output(['git','show',AFTER+':'+P+name],cwd=ROOT).decode('utf-8') for name in names}

def loc(name, needle, span=1):
    lines = sources[name].splitlines()
    start = next(i for i,line in enumerate(lines,1) if needle in line)
    return {'file':str(ROOT/P/name).replace('\\','/'),'line':start,'end_line':start+span-1,
            'commit':AFTER,'excerpt':'\n'.join(lines[start-1:start-1+span])}

js = sources['WebReaderDocument.swift']
start = js.index('      function scrollToFlat(')
end = js.index('\n      }', start) + len('\n      }')
function = js[start:end]
probe = '''
var state = {revision:'revision-1',visible:2};
var durations = [], messages = [];
var content = {querySelector: function(){return {getBoundingClientRect:function(){return {top:200};}};}};
var window = {scrollY:0,requestAnimationFrame:function(){}};
function topInset(){return 0;}
function animateTo(target,duration){durations.push({target:target,duration:duration});}
function onScroll(){}
function post(body){messages.push(body);}
'''+function+'''
scrollToFlat(0,true,'jump-key','revision-1');
console.log(JSON.stringify({requestedAnimated:true,durations:durations,messages:messages}));
'''
run = subprocess.run(['node'],input=probe,text=True,capture_output=True,check=True)
animation_probe = json.loads(run.stdout)
assert animation_probe['durations'] == [{'target':200,'duration':0}]

findings = [
 {'id':'REVALIDATE-110-001','severity':'P2','confidence':'EXTRACTED','confidence_score':1.0,
  'claim':'原子化目录跳转误作用于所有 scrollToFlat：animated 参数不再生效，自动滚屏与朗读也变成逐段瞬移。',
  'evidence':[loc('WebReaderDocument.swift','function scrollToFlat(',20),
              loc('ReaderView.swift','animatedScrollDuration: autoScrollEnabled',1),
              loc('WebScrollReaderView.swift','let animated = view.animatedScrollDuration',3)],
  'reproduction':{'status':'executed JavaScript function with deterministic stubs, not iOS UI',
                  'result':animation_probe},
  'recommended_fix':'只对明确目录/书签/首次定位使用 atomic 模式；自动滚屏/朗读保留其动画。保留 revision/requestKey 校验，动画中延迟进度发布/完成回执，不删除时序保护。',
  'verification':['新增带 animated=true 的 JS 行为测试，不只断言源字符串。',
                  'iOS 16 自动滚屏连续运动；目录切章仍一次落地，不经过中间章节进度。']},
 {'id':'REVALIDATE-110-002','severity':'P2','confidence':'INFERRED','confidence_score':.96,
  'claim':'几何缩进在续页片段内遇到内嵌换行时与测量文档不一致：isContinuation 将整个 entry（含随后新逻辑段）的 firstLineHeadIndent 都设为 0。',
  'evidence':[loc('ReaderPageTextView.swift','paragraphStyle.firstLineHeadIndent =',3),
              loc('ReaderTextPagePaginator.swift','paragraphs: display.map',2),
              loc('ReaderTextPagePaginator.swift','chunkIndex: chunks[paragraphCursor]',4),
              loc('ReaderView.swift','let paragraphs = page.paragraphs.map',9)],
  'reproduction':{'status':'source-level style contradiction; native UIKit layout NOT RUN',
                  'fixture':'一个源 paragraph = 长正文跨页 + "\\n后续逻辑段正文"；在含后续换行的 continuation entry 内，对换行后的字取 .paragraphStyle。',
                  'measured_style':'完整 document 对该源 paragraph 每个逻辑段使用 firstLineIndent。',
                  'rendered_style':'续页 entry 对整个子串使用 0，包括内部换行后的新逻辑段。'},
  'recommended_fix':'续页只对片段开头所属的第一个逻辑段取消首行缩进；遇到片段内部换行后恢复对应段样式。不要拆改源 paragraph 编号或 UTF16 offset。',
  'verification':['原生属性测试：跨页 entry 内第一逻辑段 indent=0，后续换行后的逻辑段 indent=40。',
                  '使用同一具换行长段 fixture 比较原 document container 行区间与重建页 actual UITextView，继续要求高度<=contentHeight+0.5 和每个源 UTF16 范围首尾相接。']}
]

result = {
 'schema':'graphify-focused-semantic-validation-v1', 'baseline_commit':BEFORE,'reviewed_commit':AFTER,
 'business_code_modified':False,
 'scope':'固定比较 71156be -> 64c7296；不包括 64c7296 之后其他执行者的未提交改动。',
 'findings':findings,
 'reviewed_contracts':[
  {'contract':'UTF16 conservation','assessment':'未发现本次 diff 引入字符截断/重复；仍以 document.length 完成并保存 sourceUTF16Offset。删除人工 U+3000 前缀后，测试期望改为源原文是相应契约变化，不应回退旧空格前缀。','confidence':'EXTRACTED'},
  {'contract':'119 minimum font line height','assessment':'minimumLineHeight=font.lineHeight/max=0 保留，未发现本次 diff 破坏已修正文裁切根因；必须继续跑原生 actual UITextView 矩阵。','confidence':'EXTRACTED'},
  {'contract':'ordinary continuation indent','assessment':'不含内嵌换行的普通续页 indent=0 与完整 document 后续行一致，不建议另起分页重写。','confidence':'INFERRED','confidence_score':.97},
  {'contract':'revision/requestKey','assessment':'新增 expected revision 拒绝旧 DOM 消息，scroll-applied 匹配 pending requestKey；旧 A ack 直接清 B 的原问题已封堵，不重复报旧缺陷。','confidence':'EXTRACTED'},
  {'contract':'TOC recenter cancellation','assessment':'六次无条件定时滚动已改为单次可取消 task，拖动会取消，原明确回弹原因已移除。','confidence':'EXTRACTED'}],
 'nodes':[
  {'id':'full_document_style','label':'Full-document paragraph firstLineIndent','file_type':'code','source_file':P+'ReaderTextPagePaginator.swift','source_location':'23'},
  {'id':'page_fragment_style','label':'Continuation fragment paragraph style','file_type':'code','source_file':P+'ReaderPageTextView.swift','source_location':'76'},
  {'id':'scroll_jump','label':'WebReaderDocument.scrollToFlat','file_type':'code','source_file':P+'WebReaderDocument.swift','source_location':'1159'},
  {'id':'automation_duration','label':'ReaderView automatic scroll/speech duration','file_type':'code','source_file':P+'ReaderView.swift','source_location':str(findings[0]['evidence'][1]['line'])}],
 'edges':[
  {'source':'full_document_style','target':'page_fragment_style','relation':'shares_data_with','confidence':'EXTRACTED','confidence_score':1.0,'source_file':P+'ReaderTextPagePaginator.swift'},
  {'source':'automation_duration','target':'scroll_jump','relation':'shares_data_with','confidence':'EXTRACTED','confidence_score':1.0,'source_file':P+'WebScrollReaderView.swift'}],
 'hyperedges':[],
 'source_manifest':[{'file':P+n,'sha256':hashlib.sha256(s.encode('utf-8')).hexdigest()} for n,s in sources.items()],
 'tests':{'node_version':subprocess.check_output(['node','--version'],text=True).strip(),
          'javascript_animation_probe':'passed (confirmed animated=true currently results in duration=0)',
          'ios_simulator_and_device':'NOT RUN in this Windows review task'},
 'input_tokens':0,'output_tokens':0,'token_accounting':'Exact runtime usage unavailable.'
}
out = ROOT/'docs/release-1.1.0/reader-validation.json'
out.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'output':str(out),'findings':len(findings),'reviewed_commit':AFTER,'js_probe':animation_probe},ensure_ascii=False))
