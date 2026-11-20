'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const filename = path.resolve(__dirname, '../SourceReadSwiftTests/Fixtures/syiism/source.json');
const definition = JSON.parse(fs.readFileSync(filename, 'utf8'));
const origin = 'https://syiism.fixture.invalid';
const bookID = 'syiism-book-fixture';
const itemIDs = ['syiism-item-1', 'syiism-item-2'];
const paragraphs = [['第一章的来源标识必须保持原样。', '这一段只属于第一章。'],
    ['第二章的来源标识同样来自搜索行。', '这一段只属于第二章。']];
let savedVariable = JSON.stringify({
    host: origin, origin: 'fq_novel', origin_zh: '番茄小说', category: 'fq',
    tab_type: '3', tone_id: '0', module: '小说', apikey: 'fixture-api-key',
    agg_search: '0', showPara: false, showChap: false, syncBubble: 0, introBeautify: false
});
const registry = JSON.stringify({t: 1795132800000, list: [
    {id: 'fq_novel', name: '番茄小说', category: 'fq', media: 'text'},
    {id: 'qq_luomu', name: 'QQ阅读', category: 'qq', media: 'text'}
]});

// Every callable is created in the VM realm; user scripts receive no host callbacks.
function installBridge() {
    let variable = fixtureVariable;
    const stored = {};
    globalThis.source = {
        getVariable() { return variable; },
        setVariable(value) { variable = String(value); },
        putVariable(value) { variable = String(value); },
        getLoginInfoMap() { return {}; }
    };
    globalThis.calls = [];
    globalThis.java = {
        get(key) { return stored[key] || ''; },
        put(key, value) { stored[key] = String(value); },
        log() {}, toast() {}, longToast() {},
        ajax() { calls.push('unexpected'); throw new Error('Unregistered subrequest in offline source replay'); }
    };
    globalThis.cache = {get(key) { return key === 'syiism_origins' ? fixtureRegistry : ''; }};
    globalThis.cookie = {getCookie() { return ''; }};
    globalThis.book = {name: '聚合行来源回放', author: '夹具作者', bookUrl: fixtureBookURL,
        getVariable() { return ''; }, setVariable() {}, putVariable() {}};
    globalThis.chapter = {index: 0, title: '第一章 来源'};
}

function execute(script, bindings = {}, isTemplate = false) {
    const realm = vm.createContext(Object.create(null), {codeGeneration: {strings: false, wasm: false}});
    const seeds = {fixtureVariable: savedVariable, fixtureRegistry: registry,
        fixtureBookURL: origin + '/qq_luomu/detail', result: '', baseUrl: origin, key: 'fixture', page: 1, ...bindings};
    for (const [name, value] of Object.entries(seeds)) {
        vm.runInContext('globalThis[' + JSON.stringify(name) + ']=' + JSON.stringify(value), realm);
    }
    vm.runInContext('(' + installBridge.toString() + ')()', realm, {timeout: 1000});
    vm.runInContext(definition.jsLib, realm, {timeout: 1000});
    let output;
    if (isTemplate) {
        const segments = script.split('@js:');
        output = segments[0].trim().replace(/{{([\s\S]*?)}}/g, (_, expression) =>
            String(vm.runInContext(expression, realm, {timeout: 1000})));
        if (segments.length > 1) {
            vm.runInContext('result=' + JSON.stringify(output), realm);
            output = vm.runInContext(segments.slice(1).join('@js:'), realm, {timeout: 1000});
        }
    } else {
        let body = script.trim().replace(/^@js:/, '');
        if (body.startsWith('<js>')) body = body.slice(4, body.lastIndexOf('</js>'));
        output = vm.runInContext(body, realm, {timeout: 1000});
    }
    savedVariable = vm.runInContext('source.getVariable()', realm, {timeout: 1000});
    assert.equal(vm.runInContext('calls.length', realm, {timeout: 1000}), 0);
    return output;
}

function assertAddress(address, pathname, expectedQuery) {
    const parsed = new URL(address);
    assert.equal(parsed.origin, origin);
    assert.equal(parsed.pathname, pathname);
    const query = Object.fromEntries(parsed.searchParams);
    assert.deepEqual(query, {api_key: 'fixture-api-key', ...expectedQuery});
    assert.equal([...parsed.searchParams].length, Object.keys(query).length);
}

const searchURL = execute(definition.searchUrl);
assertAddress(searchURL, '/fq_novel/search', {query: 'fixture', page: '1'});
const searchResponse = {bookList: [{bookId: bookID, source: 'qq_luomu',
    name: '聚合行来源回放', author: '夹具作者', intro: '离线来源传播夹具'}]};
const rows = execute(definition.ruleSearch.bookList, {result: JSON.stringify(searchResponse)});
assert.equal(rows.length, 1);
assert.equal(typeof rows[0], 'string');
const row = JSON.parse(rows[0]);
const detailURL = execute(definition.ruleSearch.bookUrl, {$: row}, true);
assertAddress(detailURL, '/qq_luomu/detail', {bookId: bookID, tabType: '3'});
const detail = {bookId: bookID, name: row.name, author: row.author,
    intro: row.intro, bookType: 'text', bookTypeCode: 8};
const intro = execute(definition.ruleBookInfo.intro, {result: JSON.stringify(detail), baseUrl: detailURL});
assert.ok(intro.includes(detail.intro));
assert.equal(JSON.parse(savedVariable).bookId, bookID);
const catalogURL = execute(definition.ruleBookInfo.tocUrl, {$: detail, baseUrl: detailURL}, true);
assertAddress(catalogURL, '/qq_luomu/chapter', {bookId: bookID, tabType: '3'});
// These direct property selections are explicit adapters, not a Swift JSONPath implementation.
assert.equal(definition.ruleToc.chapterList, '$.chapterList');
const catalog = {chapterList: itemIDs.map((itemId, index) => ({itemId, title: index === 0 ? '第一章 来源' : '第二章 保真'}))};
for (const [index, chapter] of catalog.chapterList.entries()) {
    const chapterURL = execute(definition.ruleToc.chapterUrl, {$: chapter, baseUrl: catalogURL}, true);
    assertAddress(chapterURL, '/qq_luomu/content', {bookId: bookID, tabType: '3', toneId: '0', itemId: itemIDs[index]});
    const response = {contentType: 'text', data: {content: paragraphs[index].join('\n')}};
    const content = execute(definition.ruleContent.content, {result: JSON.stringify(response), baseUrl: chapterURL});
    assert.equal(content, paragraphs[index].join('\n'));
}
process.stdout.write(JSON.stringify({index: 2, assertions: 'passed', originalLibrary: true,
    searchRows: rows.length, independentChapters: catalog.chapterList.length, registryCache: 'explicitly populated',
    boundary: 'Node VM only; templates/selectors use explicit test adapters, not Swift/JSCore/HTTP/App'}) + '\n');
