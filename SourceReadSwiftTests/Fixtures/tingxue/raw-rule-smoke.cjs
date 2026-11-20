// Raw source-rule smoke only. This does not implement Swift selectors or native transport.
// Run with Node's permission model and allow filesystem reads only for this directory.
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const crypto = require('node:crypto');
const assert = require('node:assert/strict');
const fixture = JSON.parse(fs.readFileSync(path.join(__dirname, 'pipeline.json'), 'utf8'));
const canonical = value => Array.isArray(value) ? value.map(canonical) : value && typeof value === 'object'
  ? Object.fromEntries(Object.keys(value).sort().map(key => [key, canonical(value[key])])) : value;
for (const [field, expected] of Object.entries(fixture.provenance.fixtureFieldSHA256)) {
  const value = fixture.source[field];
  const text = typeof value === 'string' ? value : JSON.stringify(canonical(value));
  assert.equal(crypto.createHash('sha256').update(text).digest('hex'), expected, 'Fixture field hash: ' + field);
}
assert.equal(Buffer.byteLength(fixture.source.jsLib), fixture.provenance.fixtureLibraryUTF8Bytes);
assert.equal(Buffer.from(fixture.loginHeader, 'base64').toString('utf8'), fixture.loginText);
const realm = vm.createContext(Object.create(null), { codeGeneration: { strings: false, wasm: false } });
const run = script => new vm.Script(script).runInContext(realm, { timeout: 1500 });
const fixedEpoch = 1805673600;
const device = 'fixture-device';
const signatureInput = fixture.loginText + device + fixedEpoch;
const signature = crypto.createHash('md5').update(signatureInput).digest('hex');
run('globalThis.__fixture=' + JSON.stringify(fixture) + ';' +
    'globalThis.__signatureInput=' + JSON.stringify(signatureInput) + ';' +
    'globalThis.__signature=' + JSON.stringify(signature) + ';');
run([
  'globalThis.__requests=[];globalThis.__consumed={};globalThis.__writes=0;globalThis.__variable=__fixture.configurationJSON;',
  'globalThis.key="fixture";globalThis.page=2;Date.now=function(){return ' + fixedEpoch + '000;};',
  'globalThis.__b64enc=function(value){var chars="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";var input=unescape(encodeURIComponent(String(value)));var output="";for(var i=0;i<input.length;i+=3){var a=input.charCodeAt(i),b=input.charCodeAt(i+1),c=input.charCodeAt(i+2);var bits=(a<<16)|((b||0)<<8)|(c||0);output+=chars[(bits>>>18)&63]+chars[(bits>>>12)&63]+(isNaN(b)?"=":chars[(bits>>>6)&63])+(isNaN(c)?"=":chars[bits&63]);}return output;};',
  'globalThis.__b64dec=function(value){var chars="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";var output="",bits=0,buffer=0;for(var i=0;i<value.length;i++){var digit=chars.indexOf(value[i]);if(digit<0)continue;buffer=(buffer<<6)|digit;bits+=6;if(bits>=8){bits-=8;output+=String.fromCharCode((buffer>>>bits)&255);}}return decodeURIComponent(escape(output));};',
  'globalThis.__canonical=function(value){if(Array.isArray(value))return value.map(__canonical);if(value&&typeof value==="object"){var result={};Object.keys(value).sort().forEach(function(key){result[key]=__canonical(value[key]);});return result;}return value;};',
  'globalThis.__same=function(left,right){return JSON.stringify(__canonical(left))===JSON.stringify(__canonical(right));};',
  'globalThis.__ajax=function(descriptor){var split=String(descriptor).lastIndexOf(",{ ");if(split<0)split=String(descriptor).lastIndexOf(",{");var address=split<0?String(descriptor):String(descriptor).slice(0,split);var options=split<0?{}:JSON.parse(String(descriptor).slice(split+1));if(address.indexOf(__fixture.origin+"/")!==0)throw new Error("External fixture request denied");var tail=address.slice(__fixture.origin.length);var parts=tail.split("?");var pathname=parts[0],query={};if(parts[1])parts[1].split("&").forEach(function(part){var pair=part.split("=");var key=decodeURIComponent(pair.shift());if(Object.prototype.hasOwnProperty.call(query,key))throw new Error("Duplicate fixture query key");query[key]=decodeURIComponent(pair.join("="));});var method=options.method||"GET";var body=options.body===undefined?undefined:JSON.parse(options.body);if(method==="POST"&&typeof options.body!=="string")throw new Error("Original POST descriptor must retain String body");var headers={};Object.keys(options.headers||{}).forEach(function(key){headers[key.toLowerCase()]=String(options.headers[key]);});if(headers["x-novel-token"]!==__fixture.loginHeader||headers["x-novel-public"]!==__signature||headers["x-novel-deviceid"]!=="fixture-device"||headers["x-novel-version"]!=="10")throw new Error("Synthetic normal-auth headers changed");var found=-1;for(var i=0;i<__fixture.routes.length;i++){var route=__fixture.routes[i];var expected=route.body===undefined?undefined:JSON.parse(route.body);if(!__consumed[i]&&method===route.method&&pathname===route.path&&__same(query,route.query)&&__same(body,expected)){found=i;break;}}if(found<0)throw new Error("Unknown, duplicate or mismatched fixture route: "+method+" "+pathname);__consumed[found]=true;__requests.push({method:method,path:pathname,bodyKind:typeof options.body});return __fixture.routes[found].response.body;};',
  'globalThis.source={getVariable:function(){return __variable;},setVariable:function(value){__variable=String(value);__writes++;},getLoginHeader:function(){return __fixture.loginHeader;},getLoginInfoMap:function(){return {get:function(){return "";}};}};',
  'globalThis.book={type:0,order:0,durChapterIndex:0,getVariable:function(){return "";}};globalThis.chapter={index:0,title:""};',
  'globalThis.cookie={getCookie:function(){return "";}};globalThis.cache={get:function(){return "";},put:function(){throw new Error("Unexpected fixture cache write");}};',
  'globalThis.java={ajax:__ajax,deviceID:function(){return "";},androidId:function(){return "fixture-device";},getWebViewUA:function(){return "Fixture/1.0";},base64Encode:__b64enc,base64Decode:__b64dec,hexDecodeToString:function(value){var output="";for(var i=0;i<value.length;i+=2)output+=String.fromCharCode(parseInt(value.slice(i,i+2),16));return decodeURIComponent(escape(output));},md5Encode:function(value){if(String(value)!==__signatureInput)throw new Error("Unexpected signature input");return __signature;},toast:function(){},log:function(){},createSymmetricCrypto:function(){throw new Error("Cipher path is outside plaintext fixture scope");}};'
].join('\n'));
run(fixture.source.jsLib);
function execute(rule, input, baseURL) {
  run('globalThis.result=' + JSON.stringify(input) + ';globalThis.baseUrl=' + JSON.stringify(baseURL || '') + ';');
  let script = rule;
  let selector = '';
  if (script.startsWith('<js>')) {
    const end = script.indexOf('</js>');
    assert.ok(end >= 0);
    selector = script.slice(end + 5).trim();
    script = script.slice(4, end);
  } else {
    script = script.replace(/^@js:\s*/, '');
  }
  return { value: run('{' + script + '}'), selector };
}
function jsonStage(stage, expectedSelector) {
  assert.equal(stage.selector, expectedSelector);
  let value = typeof stage.value === 'string' ? JSON.parse(stage.value) : stage.value;
  for (const field of expectedSelector.slice(2).split('.')) value = value[field];
  return value;
}
function carrier(address, expected) {
  const match = String(address).match(/^data:[^,]*;base64,([^,]+),([\s\S]+)$/);
  assert.ok(match, 'Expected an original generated typed carrier');
  assert.equal(JSON.parse(match[2]).type, 'qingci');
  const text = Buffer.from(match[1], 'base64').toString('utf8');
  assert.deepEqual(JSON.parse(text), expected);
  return Buffer.from(text).toString('hex');
}
const source = fixture.source;
const searchAddress = execute(source.searchUrl, '').value.replace('{{key}}', 'fixture').replace('{{page}}', '2');
const headers = JSON.parse(execute(source.header, '').value);
const searchResponse = run('java.ajax(' + JSON.stringify(searchAddress + ',' + JSON.stringify({ method: 'GET', headers })) + ')');
const books = jsonStage(execute(source.ruleSearch.bookList, searchResponse, searchAddress), '$.data.list');
assert.equal(books.length, 1);
assert.equal(books[0].title, fixture.expected.name);
const detailAddress = execute(source.ruleSearch.bookUrl, books[0], searchAddress).value;
const detail = jsonStage(execute(source.ruleBookInfo.init, carrier(detailAddress, fixture.expected.detail), detailAddress), '$.data');
assert.equal(detail.title, fixture.expected.name);
const catalogAddress = execute(source.ruleBookInfo.tocUrl, detail, detailAddress).value;
const chapters = jsonStage(execute(source.ruleToc.chapterList, carrier(catalogAddress, fixture.expected.catalog), catalogAddress), '$.data');
assert.equal(chapters.length, 2);
assert.deepEqual(JSON.parse(JSON.stringify(chapters.map(chapter => chapter.title))), fixture.expected.chapterTitles);
for (let index = 0; index < chapters.length; index++) {
  const address = execute(source.ruleToc.chapterUrl, chapters[index], catalogAddress).value;
  const hex = carrier(address, fixture.expected.contents[index]);
  assert.equal(fixture.expected.contents[index].chapter_index, index);
  run('chapter.index=' + index + ';chapter.title=' + JSON.stringify(chapters[index].title) + ';');
  const lyric = execute(source.ruleContent.subContent, hex, address);
  assert.equal(lyric.selector, '');
  assert.equal(lyric.value, '', 'Non-audio original subContent must not request lyrics');
  const content = execute(source.ruleContent.content, hex, address);
  assert.equal(content.selector, '');
  assert.equal(content.value, fixture.expected.paragraphs[index].join('\n'));
}
const requests = JSON.parse(run('JSON.stringify(__requests)'));
assert.equal(requests.length, fixture.routes.length);
assert.deepEqual(requests.map(request => request.path), fixture.routes.map(route => route.path));
assert.deepEqual(requests.map(request => request.bodyKind), ['undefined', 'string', 'string', 'string', 'string']);
const normalizedConfig = JSON.parse(run('__variable'));
assert.ok(Array.isArray(normalizedConfig));
assert.equal(normalizedConfig[0].gender, 'boy');
assert.equal(normalizedConfig[0].host, fixture.origin);
assert.ok(run('__writes') >= 1, 'Normal ensureConfig must persist its default through source.setVariable');
console.log(JSON.stringify({ originalIndex: 0, searchRows: books.length, chapters: chapters.length,
  contentBodies: 2, httpRequests: requests.length, originalRuleSelectors: true,
  normalAuthWithSyntheticLogin: true, nonAudioSubContent: 'empty', sanitizedCipherLiterals: 8,
  boundary: 'Node raw-rule smoke; native Swift/JavaScriptCore and encrypted transport not verified', passed: true }));
