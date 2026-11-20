// Raw source-rule smoke; this does not run Swift selectors or native transport.
// All inputs and responses are synthetic fixtures in this directory.
'use strict';
const fs=require('node:fs');const vm=require('node:vm');
const path=require('node:path'); const fixtures={5:JSON.parse(fs.readFileSync(path.join(__dirname,'guangyu-pipeline.json'),'utf8')),6:JSON.parse(fs.readFileSync(path.join(__dirname,'dahuilang-pipeline.json'),'utf8'))};const originals={5:fixtures[5].source,6:fixtures[6].source};
function makeRealm(index,responses){
 const configuration=JSON.parse(fixtures[index].configurationJSON);
 const realm=vm.createContext(Object.create(null),{codeGeneration:{strings:false,wasm:false}});
 const run=function(code){return new vm.Script(code).runInContext(realm,{timeout:1000});};
 run('globalThis.__variable='+JSON.stringify(JSON.stringify(configuration))+';globalThis.__responses='+JSON.stringify(responses)+';');
 run([
 "globalThis.__requests=[];globalThis.__notices=[];globalThis.__bag={};globalThis.key='fixture';globalThis.page=2;",
 "globalThis.__b64enc=function(value){var chars='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';var input=unescape(encodeURIComponent(String(value)));var output='';for(var i=0;i<input.length;i+=3){var a=input.charCodeAt(i),b=input.charCodeAt(i+1),c=input.charCodeAt(i+2);var bits=(a<<16)|((b||0)<<8)|(c||0);output+=chars[(bits>>>18)&63]+chars[(bits>>>12)&63]+(isNaN(b)?'=':chars[(bits>>>6)&63])+(isNaN(c)?'=':chars[bits&63]);}return output;};",
 "globalThis.source={getVariable:function(){return __variable;},setVariable:function(v){__variable=String(v);},putVariable:function(v){__variable=String(v);},getLoginInfoMap:function(){return {};}};",
 "globalThis.cache={get:function(){return '';},put:function(){}};",
 "globalThis.cookie={getCookie:function(){return '';},getKey:function(){return '';},setCookie:function(){throw new Error('Unexpected cookie write');},removeCookie:function(){throw new Error('Unexpected cookie removal');}};",
 "globalThis.book={type:0,order:0,durChapterIndex:0,name:'Fixture book',author:'Fixture author',readConfig:{useReplaceRule:false},getVariable:function(){return '';},setUseReplaceRule:function(){throw new Error('Unexpected book change');}};globalThis.chapter={index:0,title:'Fixture chapter'};",
 "globalThis.java={qread:function(){return '0';},androidId:function(){return '';},deviceID:function(){throw new Error('Fixture has no device ID');},getWebViewUA:function(){return 'Fixture/1.0';},getCookie:function(){return '';},base64Encode:__b64enc,hexDecodeToString:function(value){var output='';for(var i=0;i<value.length;i+=2)output+=String.fromCharCode(parseInt(value.slice(i,i+2),16));return decodeURIComponent(escape(output));},put:function(k,v){__bag[k]=v;},get:function(k){return __bag[k];},toast:function(v){__notices.push(String(v));},longToast:function(v){__notices.push(String(v));},log:function(){},ajax:function(request){__requests.push(String(request));for(var path in __responses){if(String(request).indexOf(path)>=0)return JSON.stringify(__responses[path]);}throw new Error('Unmatched fixture request');}};"
 ].join('\n'));
 run("globalThis.JavaImporter=function(){this.importClass=function(){throw new Error('Unsupported fixture import');};};");run(originals[index].jsLib);return {realm,run};
}
function execute(context,text,input,baseUrl){
 context.run('globalThis.result='+JSON.stringify(input)+';globalThis.baseUrl='+JSON.stringify(baseUrl||'')+';');
 let body=text,selector='';
 if(text.startsWith('<js>')){const end=text.indexOf('</js>');body=text.slice(4,end);selector=text.slice(end+5).trim();}else{body=text.replace(/^@js:\s*/,'');}
 return {value:context.run('{'+body+'}'),selector};
}
function carrier(url){const match=url.match(/^data:;base64,([^,]+),([\s\S]+)$/);if(!match)throw new Error('Expected original generated carrier');const decoded=Buffer.from(match[1],'base64').toString('utf8');return {hex:Buffer.from(decoded,'utf8').toString('hex'),payload:JSON.parse(decoded),metadata:JSON.parse(match[2])};}
function selectData(stage,wantsArray){if(stage.selector!=='$.data')throw new Error('Unexpected manual selector');const root=typeof stage.value==='string'?JSON.parse(stage.value):stage.value;const value=root&&root.data;if(wantsArray&&!Array.isArray(value))return [];return value;}
function shapeRequests(context){return JSON.parse(context.run('JSON.stringify(__requests)')).map(function(request){const separator=request.lastIndexOf(',{');const uri=new URL(separator<0?request:request.slice(0,separator));const options=separator<0?{}:JSON.parse(request.slice(separator+1));let body=options.body;const bodyKind=typeof body;if(typeof body==='string'){try{body=JSON.parse(body);}catch{}}return {hostIsFixture:/\.fixture\.invalid$/.test(uri.hostname),path:uri.pathname,query:Object.fromEntries(uri.searchParams),method:options.method||'GET',bodyKind,body,headerNames:Object.keys(options.headers||{}).sort()};});}

const assert=require('node:assert/strict');
for(const index of [5,6]){
 const fixture=fixtures[index],source=fixture.source;
 const responses=Object.fromEntries(fixture.routes.filter(route=>route.path!=='/content').map(route=>[route.path+(Object.keys(route.query).length?'?':''),JSON.parse(route.response.body)]));
 const context=makeRealm(index,responses);
 const searchUrl=execute(context,source.searchUrl,'').value;
 let rows;
 if(index===5){rows=selectData(execute(context,source.ruleSearch.bookList,carrier(searchUrl).hex,searchUrl),true);}
 else{rows=JSON.parse(context.run('java.ajax('+JSON.stringify(searchUrl.replace('{{page}}','2'))+')')).data;}
 assert.equal(rows.length,1);
 const detailUrl=execute(context,source.ruleSearch.bookUrl,rows[0]).value;
 const detail=carrier(detailUrl);assert.deepEqual(detail.payload,fixture.expected.detail.payload);assert.equal(detail.metadata.type,fixture.expected.detail.type);
 const info=selectData(execute(context,source.ruleBookInfo.init,detail.hex,detailUrl),false);
 execute(context,source.ruleBookInfo.intro,info,detailUrl);
 const catalogUrl=execute(context,source.ruleBookInfo.tocUrl,info,detailUrl).value;
 const catalog=carrier(catalogUrl);assert.deepEqual(catalog.payload,fixture.expected.catalog.payload);assert.equal(catalog.metadata.type,fixture.expected.catalog.type);
 const chapters=selectData(execute(context,source.ruleToc.chapterList,catalog.hex,catalogUrl),true);
 assert.equal(chapters.length,2);assert.deepEqual(JSON.parse(JSON.stringify(chapters.map(item=>item.title))),fixture.expected.chapterTitles);
 const contentRoutes=fixture.routes.filter(route=>route.path==='/content');
 for(let position=0;position<chapters.length;position++){
  context.run('globalThis.chapter.index='+position+';globalThis.chapter.title='+JSON.stringify(chapters[position].title)+';__responses["/content"]='+contentRoutes[position].response.body+';');
  const address=execute(context,source.ruleToc.chapterUrl,chapters[position],catalogUrl).value;
  const envelope=carrier(address);assert.deepEqual(envelope.payload,fixture.expected.contents[position].payload);assert.equal(envelope.metadata.type,fixture.expected.contents[position].type);
  if(source.ruleContent.title)execute(context,source.ruleContent.title,envelope.hex,address);
  const output=execute(context,source.ruleContent.content,envelope.hex,address);assert.equal(output.selector,'$.content');
  assert.equal(JSON.parse(output.value).content,fixture.expected.paragraphs[position].join('\n'));
 }
 const requests=shapeRequests(context);assert.equal(requests.length,fixture.routes.length);
 requests.forEach((request,position)=>{
  const route=fixture.routes[position];assert.equal(request.hostIsFixture,true);assert.equal(request.path,route.path);assert.equal(request.method,route.method);assert.deepEqual(request.query,route.query);
  const expectedBody=route.body?JSON.parse(route.body):undefined;
  if(route.method==='GET')assert.ok(request.body===undefined||(typeof request.body==='object'&&Object.keys(request.body).length===0),'GET descriptors may contain an empty body; native builder must remove it');
  else assert.deepEqual(request.body,expectedBody);
 });
 console.log(JSON.stringify({index,searchRows:rows.length,chapters:chapters.length,contentBodies:contentRoutes.length,httpRequests:requests.length,bodyKinds:requests.map(request=>request.bodyKind),originalLibraryBytes:Buffer.byteLength(source.jsLib),boundary:'Node raw-rule smoke; native Swift/JavaScriptCore and encrypted transport not verified',passed:true}));
}
