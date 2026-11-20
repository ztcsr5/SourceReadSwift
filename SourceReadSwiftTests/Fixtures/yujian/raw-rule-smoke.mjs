import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';

// This smoke uses a deliberately limited manual selector/template adapter.
// It executes the retained JS rules, not Swift, JavaScriptCore, or the native pipeline.
const fixtureDirectory = new URL('./', import.meta.url);
const sourceBytes = readFileSync(new URL('source.json', fixtureDirectory));
const pipelineBytes = readFileSync(new URL('pipeline.json', fixtureDirectory));
const source = JSON.parse(sourceBytes);
const fixture = JSON.parse(pipelineBytes);
const provenance = JSON.parse(readFileSync(new URL('provenance.json', fixtureDirectory)));
const digest = value => createHash('sha256').update(value).digest('hex');
assert.equal(digest(sourceBytes), provenance.fixtureSHA256);
assert.equal(digest(pipelineBytes), provenance.pipelineSHA256);
assert.equal(digest(source.jsLib), provenance.fixtureLibrarySHA256);
assert.notEqual(provenance.originalLibrarySHA256, provenance.fixtureLibrarySHA256);
for (const [field, expected] of Object.entries(provenance.unmodifiedFieldSHA256)) {
  assert.equal(digest(JSON.stringify(source[field])), expected, 'Unmodified source field: ' + field);
}

const sourceAdapter = {
  getVariable: () => fixture.sourceVariableJSON,
  getLoginInfo: () => '',
  getLoginHeader: () => '',
  get: () => ''
};
const forbiddenBridgeRequest = () => { throw new Error('Real network and comment/signing paths are excluded'); };
const context = vm.createContext({
  source: sourceAdapter,
  java: { getSource: () => sourceAdapter, ajax: forbiddenBridgeRequest, ajaxAll: forbiddenBridgeRequest }
});
vm.runInContext(source.jsLib, context, { timeout: 1000 });
assert.equal(source.jsLib.split('function YuJianContent(').length - 1, 2);
assert.equal(vm.runInContext("String(YuJianContent).includes('contextUrl, response')", context), true);

function selectJSONPath(rule, input) {
  assert.equal(rule.startsWith('$.'), true, 'Only authored fixture JSONPaths are supported');
  const root = typeof input === 'string' ? JSON.parse(input) : input;
  let selected = root;
  for (const component of rule.slice(2).split('.')) {
    const name = component.replace(/\[\*\]$/, '');
    selected = selected?.[name];
    if (component.endsWith('[*]') && selected !== undefined) assert.equal(Array.isArray(selected), true);
  }
  return selected;
}

function evaluateRule(rule, input, bindings = {}) {
  if (!rule) return '';
  if (rule.startsWith('@js:')) {
    context.result = input;
    Object.assign(context, bindings);
    return vm.runInContext(rule.slice(4), context, { timeout: 1000 });
  }
  if (rule.startsWith('{{') && rule.endsWith('}}')) {
    for (const candidate of rule.slice(2, -2).split('||')) {
      const selected = selectJSONPath(candidate, input);
      if (selected !== undefined && selected !== null && selected !== '') return selected;
    }
    return '';
  }
  return selectJSONPath(rule, input);
}

const requests = [];
function replayResponse(address) {
  const separator = address.indexOf(',{');
  const url = separator < 0 ? address : address.slice(0, separator);
  const options = separator < 0 ? {} : JSON.parse(address.slice(separator + 1));
  const response = fixture.responses[url];
  assert.notEqual(response, undefined, 'Every request must match an exact offline fixture route');
  const headers = { ...JSON.parse(evaluateRule(source.header, '')), ...options.headers };
  const method = options.method || 'GET';
  const body = options.body ?? null;
  assert.equal(method, response.method);
  assert.equal(body, response.requestBody);
  assert.equal(headers.Accept, 'application/json');
  assert.equal(headers['X-Reader-Token'], fixture.readerToken);
  requests.push(url);
  return { url, body: response.body };
}

const searchAddress = evaluateRule(source.searchUrl, '', { key: fixture.keyword, page: fixture.page });
const searchResponse = replayResponse(searchAddress);
const searchOptions = JSON.parse(searchAddress.slice(searchAddress.indexOf(',{') + 1));
assert.equal(JSON.parse(searchOptions.body).keyword, fixture.keyword);
assert.equal(JSON.parse(searchOptions.body).page, fixture.page);
const books = evaluateRule(source.ruleSearch.bookList, searchResponse.body);
assert.equal(books.length, 1);
const firstBook = books[0];
assert.equal(evaluateRule(source.ruleSearch.name, firstBook), fixture.searchName);
assert.equal(evaluateRule(source.ruleSearch.author, firstBook), fixture.searchAuthor);
assert.equal(evaluateRule(source.ruleSearch.kind, firstBook), fixture.searchKind);
assert.equal(evaluateRule(source.ruleSearch.coverUrl, firstBook), fixture.searchCoverURL);
const detailAddress = evaluateRule(source.ruleSearch.bookUrl, firstBook);
assert.equal(detailAddress, fixture.detailURL);
assert.equal(detailAddress.includes('%2F'), true);

const detailResponse = replayResponse(detailAddress);
assert.equal(evaluateRule(source.ruleBookInfo.name, detailResponse.body), fixture.detailName);
assert.equal(evaluateRule(source.ruleBookInfo.author, detailResponse.body), fixture.detailAuthor);
assert.equal(evaluateRule(source.ruleBookInfo.kind, detailResponse.body), fixture.detailKind);
assert.equal(evaluateRule(source.ruleBookInfo.coverUrl, detailResponse.body), fixture.detailCoverURL);
assert.equal(evaluateRule(source.ruleBookInfo.lastChapter, detailResponse.body), fixture.chapters.at(-1).title);
const tocAddress = evaluateRule(source.ruleBookInfo.tocUrl, detailResponse.body);
assert.equal(tocAddress, fixture.tocURL);
const tocResponse = replayResponse(tocAddress);
const chapters = evaluateRule(source.ruleToc.chapterList, tocResponse.body);
assert.equal(chapters.length, 2);

for (const [index, row] of chapters.entries()) {
  const expected = fixture.chapters[index];
  const title = evaluateRule(source.ruleToc.chapterName, row);
  const address = evaluateRule(source.ruleToc.chapterUrl, row, { baseUrl: tocResponse.url });
  const vip = evaluateRule(source.ruleToc.isVip, row);
  assert.equal(title, expected.title);
  assert.equal(address, expected.url);
  assert.equal(Boolean(vip), expected.isVip);
  assert.equal(evaluateRule(source.ruleToc.updateTime, row).startsWith(expected.updatePrefix), true);
  const query = new URL(address).searchParams;
  assert.equal([...query].length, 4);
  assert.equal(query.get('bookId'), fixture.bookID);
  assert.equal(query.get('chapterId'), expected.id);
  assert.equal(query.get('vip'), expected.isVip ? '1' : '0');
  assert.equal(query.get('chapterTime'), expected.chapterTime);
  const contentResponse = replayResponse(address);
  const bindings = { baseUrl: contentResponse.url, title, chapter: { title, url: address } };
  const content = evaluateRule(source.ruleContent.content, contentResponse.body, bindings);
  assert.deepEqual(content.split(/\r?\n/).map(paragraph => paragraph.trim()).filter(Boolean), expected.paragraphs);
  assert.equal(evaluateRule(source.ruleContent.title, contentResponse.body, bindings), expected.title);
}

assert.deepEqual(requests, fixture.requestOrder);
process.stdout.write(JSON.stringify({
  result: 'NODE_RAW_RULE_SMOKE_PASS',
  source: 'index 1',
  requests: requests.length,
  chapters: chapters.length,
  fixture: fileURLToPath(fixtureDirectory),
  boundary: 'Manual selector/template adapter; not Swift or XCTest. No real networking, signing, login or comments verified.'
}) + '\n');
