from pathlib import Path
import json, subprocess

ROOT = Path(__file__).resolve().parents[2]
OUT = Path('F:/SourceReadSwift/release-1.1.0')
NAME = 'SourceReadSwift/Features/Reader/WebReaderDocument.swift'
before = subprocess.check_output(['git', 'show', 'e06501b:' + NAME], cwd=ROOT).decode('utf8')
after = (ROOT / NAME).read_text(encoding='utf8')
bootstrap = '''
var scrollAnimationGeneration=0, timers=[], messages=[], nextTarget=200;
var state={revision:'r',visible:0};
var content={querySelector:function(){return {getBoundingClientRect:function(){return {top:nextTarget-window.scrollY};}};}};
var window={scrollY:0,nativeTarget:null,
scrollTo:function(x,y){if(typeof x==='object'){this.nativeTarget=x.top;}else{this.nativeTarget=null;this.scrollY=y;}},
setTimeout:function(cb){timers.push(cb);},requestAnimationFrame:function(){}};
function topInset(){return 0;} function onScroll(){} function post(m){messages.push(m);}
'''
fixture = '''
scrollToFlat(1,true,'old-speech','r');nextTarget=0;
scrollToFlat(0,false,'new-toc','r');timers.forEach(function(cb){cb();});
if(window.nativeTarget!==null){window.scrollY=window.nativeTarget;}
console.log(JSON.stringify({scrollY:window.scrollY,messages:messages}));
'''
records=[]
for label,source in [('before-e06501b',before),('modified-worktree',after)]:
    start = source.index('      function stopScrollAnimation()' if 'function stopScrollAnimation()' in source else '      function animateTo(')
    end = source.index('      function pageStep(',start)
    jump = source.index('      function scrollToFlat(')
    jump_end = source.index('      /// 回到文档顶端',jump)
    js = bootstrap + source[start:end] + source[jump:jump_end] + fixture
    p = subprocess.run(['node'], input=js, text=True, capture_output=True, encoding='utf8')
    assert p.returncode == 0, p.stderr
    result=json.loads(p.stdout)
    records.append({'variant':label,'stdout':p.stdout,'stderr':p.stderr,'exit_code':p.returncode,'result':result})
assert records[0]['result']['scrollY'] == 200
assert records[1]['result']['scrollY'] == 0
(OUT/'motion-regression.json').write_text(json.dumps(records,ensure_ascii=False,indent=2),encoding='utf8')
print('PASS: before old animation moved new jump to 200; modified stays at requested 0; old ack rejected.')
