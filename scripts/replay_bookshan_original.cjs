'use strict';

// Offline raw-rule smoke test; selectors and data-envelope transport below are explicit test adapters.
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const path=require('node:path');
const filename=path.resolve(__dirname,'../SourceReadSwiftTests/Fixtures/bookshan/source.json');
const raw=fs.readFileSync(filename,'utf8');
const source=JSON.parse(raw.replace(/^\uFEFF/,''));
const isFanqie=process.argv.includes('--fanqie');
if(process.argv.slice(2).some(argument=>argument!=='--fanqie'))throw new Error('Usage: node scripts/replay_bookshan_original.cjs [--fanqie]');
const origin='https://bookshan.fixture.invalid',fixedNow=1795132800000;
const sourceName=isFanqie?'番茄小说':'fixture-novel';
function installBridge(){
 globalThis.calls=[];globalThis.toasts=[];globalThis.browsers=[];const stored={};let variable=JSON.stringify([{host:fixtureOrigin,gender:'male',tag:'all',yunpara:'0',lastUpdateCheck:fixtureNow}]);
 globalThis.source={getVariable:function(){return variable;},setVariable:function(v){variable=String(v);},getLoginInfoMap:function(){return{};},getLoginHeader:function(){return JSON.stringify({authorization:'fixture-only'});},loginUrl:fixtureLoginUrl};
 globalThis.book={name:'书山合成样本',author:'Fixture Author',bookUrl:'data:fixture',order:0,durChapterIndex:-1,getVariable:function(){return '关闭段评';},setVariable:function(){}};
 globalThis.chapter={index:0,title:'第一章·合成起点'};
 globalThis.cookie={getCookie:function(){return '';},getKey:function(){return '';},setCookie:function(){},removeCookie:function(){}};
 globalThis.cache={getFromMemory:function(){return '';},putMemory:function(){},get:function(){return '';},put:function(){}};
 globalThis.java={deviceID:function(){return '';},androidId:function(){return 'fixture-android-id';},getWebViewUA:function(){return'fixture-user-agent';},log:function(){},toast:function(message){toasts.push(String(message));},longToast:function(message){toasts.push(String(message));},startBrowser:function(url){browsers.push(String(url));},get:function(k){return stored[k]||'';},put:function(k,v){stored[k]=v;},getCookie:function(){return '';},
  hexDecodeToString:function(hex){let encoded='';for(let i=0;i<hex.length;i+=2)encoded+='%'+hex.slice(i,i+2);return decodeURIComponent(encoded);},
  base64Encode:function(value){const bytes=unescape(encodeURIComponent(String(value))),table='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';let result='';for(let i=0;i<bytes.length;i+=3){const a=bytes.charCodeAt(i),hb=i+1<bytes.length,hc=i+2<bytes.length,b=hb?bytes.charCodeAt(i+1):0,c=hc?bytes.charCodeAt(i+2):0,v=(a<<16)|(b<<8)|c;result+=table[(v>>>18)&63]+table[(v>>>12)&63]+(hb?table[(v>>>6)&63]:'=')+(hc?table[v&63]:'=');}return result;},
  ajax:function(descriptor){calls.push(String(descriptor));const address=String(descriptor).split(',{')[0];if(!address.startsWith(fixtureOrigin+'/'))throw new Error('Unexpected external request');const path=address.slice(fixtureOrigin.length).split('?')[0];if(!(path in fixtureResponses))throw new Error('Unstubbed local request '+path);return JSON.stringify(fixtureResponses[path]);}
 };
 Date.now=function(){return fixtureNow;};
}
function execute(rule,seed={}){
 const context=vm.createContext(Object.create(null),{codeGeneration:{strings:true,wasm:false}});
 const bindings={fixtureOrigin:origin,fixtureNow:fixedNow,fixtureLoginUrl:source.loginUrl,fixtureResponses:{'/details':{code:0,data:{source:sourceName,book_url:origin+'/books/1',title:'书山合成样本·详情',author:'Fixture Detail Author',bookid:'fixture-book-id',tab:'novel',cover:origin+'/cover.png',desc:'离线详情合成简介'}},'/catalog':{code:0,data:[{cid:'fixture-volume',title:'第一卷',isVolume:true},{cid:'fixture-chapter-1',title:'第一章·合成起点',url:origin+'/chapters/1?item_id=1000000000000000001'},{cid:'fixture-chapter-2',title:'第二章·合成终点',url:origin+'/chapters/2?item_id=1000000000000000002'}]},'/content':{code:0,data:{content:'第一段合成正文。\n第二段合成正文。',tab:'novel'}}},result:'',baseUrl:origin,key:'fixture',page:1,...seed};
 for(const[name,value]of Object.entries(bindings))vm.runInContext('globalThis.'+name+'='+JSON.stringify(value)+';',context);
 vm.runInContext('('+installBridge.toString()+')()',context,{timeout:1000});
 vm.runInContext(source.jsLib,context,{timeout:1000});assert.equal(vm.runInContext('calls.length',context),0);
 const rawHeader=vm.runInContext(source.header.replace(/^@js:/,''),context,{timeout:1000});
 const header=typeof rawHeader==='string'?JSON.parse(rawHeader):rawHeader;
 let script=rule;const first=rule.indexOf('<js>'),last=rule.lastIndexOf('</js>');if(first>=0&&last>=0)script=rule.slice(first+4,last);else script=rule.replace(/^@js:/,'');
 const result=vm.runInContext(script,context,{timeout:1000});
 return{result,calls:JSON.parse(vm.runInContext('JSON.stringify(calls)',context)),headerKeys:Object.keys(header).sort(),browserCount:vm.runInContext('browsers.length',context)};
}
function parseDataURL(url){const prefix=url.slice(0,url.indexOf(';base64,'));const encoded=url.slice(url.indexOf(';base64,')+8).split(',{')[0];return{prefix,payload:JSON.parse(Buffer.from(encoded,'base64').toString('utf8'))};}
function descriptorShape(value){const split=value.indexOf(',{'),address=split<0?value:value.slice(0,split),options=split<0?{}:JSON.parse(value.slice(split+1));const url=new URL(address);return{path:url.pathname,queryKeys:[...new Set(url.searchParams.keys())].sort(),method:options.method||'GET',bodyKeys:Object.keys(options.body||{}).sort(),headerKeys:Object.keys(options.headers||{}).sort()};}
const search=execute(source.searchUrl);assert.equal(typeof search.result,'string');assert.ok(search.result.startsWith(origin+'/search?'));assert.equal(search.calls.length,0);
const searchItem={source:sourceName,book_url:origin+'/books/1',title:'书山合成样本',author:'Fixture Author',cover:origin+'/cover.png',desc:'离线搜索合成简介'};
const bookURL=execute(source.ruleSearch.bookUrl,{result:searchItem});const detailData=parseDataURL(bookURL.result);assert.equal(detailData.prefix,'data:detailsUrl');assert.equal(detailData.payload.source,sourceName);
const detail=execute(source.ruleBookInfo.init,{result:Buffer.from(JSON.stringify(detailData.payload)).toString('hex'),baseUrl:bookURL.result});assert.equal(detail.calls.length,1);const detailItem=JSON.parse(detail.result).data;assert.equal(detailItem.title,'书山合成样本·详情');
const tocURL=execute(source.ruleBookInfo.tocUrl,{result:detailItem});const catalogData=parseDataURL(tocURL.result);assert.equal(catalogData.prefix,'data:catalogUrl');assert.equal(catalogData.payload.bookid,'fixture-book-id');
const toc=execute(source.ruleToc.chapterList,{result:Buffer.from(JSON.stringify(catalogData.payload)).toString('hex'),baseUrl:tocURL.result});assert.equal(toc.calls.length,1);assert.equal(toc.result.length,3);assert.equal(toc.result[0].url,'');const chapterData=parseDataURL(toc.result[1].url);assert.equal(chapterData.prefix,'data:chapterUrl');assert.equal(chapterData.payload.source,sourceName);assert.equal(chapterData.payload.cid,'fixture-chapter-1');
if(isFanqie){assert.equal(chapterData.payload.book_id,'fixture-book-id');assert.equal(chapterData.payload.item_id,'1000000000000000001');assert.equal(chapterData.payload.commentUrl,origin+'/idea_comment?book_id=fixture-book-id&item_id=1000000000000000001&sessionid=');}
const content=execute(source.ruleContent.content,{result:Buffer.from(JSON.stringify(chapterData.payload)).toString('hex'),baseUrl:toc.result[1].url});assert.equal(content.calls.length,1);assert.equal(content.result,'第一段合成正文。\n第二段合成正文。');assert.equal(content.browserCount,0);
const subContent=execute(source.ruleContent.subContent,{result:Buffer.from(JSON.stringify(chapterData.payload)).toString('hex'),baseUrl:toc.result[1].url});assert.equal(subContent.result,'');assert.equal(subContent.calls.length,0);
process.stdout.write(JSON.stringify({index:3,fixtureSHA256:crypto.createHash('sha256').update(raw).digest('hex'),scenario:isFanqie?'fanqie':'novel',originalLibrary:false,originalStageRules:true,originalRules:['searchUrl','ruleSearch.bookUrl','ruleBookInfo.init','ruleBookInfo.tocUrl','ruleToc.chapterList','ruleContent.content','ruleContent.subContent'],assertions:'passed',searchTemplateRetainsKeyAndPage:search.result.includes('{{encodeURIComponent(key)}}')&&search.result.includes('{{page}}'),sourceHeaderKeys:search.headerKeys,requestShapes:[...detail.calls,...toc.calls,...content.calls].map(descriptorShape),catalogEntries:toc.result.length,volumeURLIsEmpty:toc.result[0].url==='',chapterPayloadKeys:Object.keys(chapterData.payload).sort(),contentCharacters:content.result.length,subContentIsEmpty:subContent.result==='',boundary:'Node VM only; outer transport/data URL/JSONPath/JSCore/App not executed'})+'\n');
