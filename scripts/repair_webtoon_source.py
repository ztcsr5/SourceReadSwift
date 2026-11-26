"""Repair WEBTOON rules in a private source export without changing other sources."""
import argparse
import copy
import json
from pathlib import Path
from urllib.parse import urlparse

CONTENT = r'''@js:
(function () {
  var pages = String(java.getString('@css:#_imageList img[data-url], img._images[data-url], .viewer_img img[data-url]@data-url') || '')
    .split(/\r?\n/).map(function (url) { return url.trim(); })
    .filter(function (url) { return /^https?:\/\//i.test(url); });
  if (pages.length) return pages.join('\n');
  var body = String(result || '');
  var first = body.indexOf('var imageList');
  if (first < 0) return '';
  var section = body.substring(first);
  var end = section.indexOf('];');
  if (end >= 0) section = section.substring(0, end + 1);
  var urls = /url\s*:\s*["']([^"']+)["']/g;
  for (var match; (match = urls.exec(section)) !== null;) {
    if (/^https?:\/\//i.test(match[1])) pages.push(match[1]);
  }
  return pages.join('\n');
})()'''

EXPLORE_LIST = r'''@js:
(function () {
  var address = String(baseUrl || '');
  var item = 'a.link._titleItem[href*="/list?title_no="]';
  var container = '.webtoon_list ';
  var match;
  if (/\/canvas\/list(?:[?#]|$)/i.test(address)) {
    match = address.match(/[?&]genre=([A-Za-z_-]+)(?:&|$)/i);
    container = '._genreTitleList_' + (match ? match[1].toUpperCase().replace(/-/g, '_') : 'ALL') + ' ';
    item = 'a.link[href*="/list?title_no="]';
  } else if ((match = address.match(/\/originals\/([A-Za-z_-]+)(?:[?#]|$)/i))) {
    container = '.originals_' + match[1].toUpperCase().replace(/-/g, '_') + '_list ';
  } else if ((match = address.match(/\/genres\/([A-Za-z_-]+)(?:[?#]|$)/i))) {
    container = '.genre_' + match[1].toUpperCase().replace(/-/g, '_') + '_list ';
  } else if (/\/new(?:[?#]|$)/i.test(address)) {
    container = '.webtoon_scroll_list ';
  }
  return java.getElements('@css:' + container + item);
})()'''

TOC_URL = r'''@js:
(function () {
  var address = typeof baseUrl === 'undefined' ? '' : String(baseUrl || '');
  var bookAddress = typeof book === 'undefined' || !book ? '' : String(book.bookUrl || '');
  var api = /\/api\/v1\/(?:canvas|webtoon)\/\d+\/episodes(?:[?#]|$)/;
  if (api.test(address)) return address;
  if (api.test(bookAddress)) return bookAddress;
  if (!/title_no=\d+/.test(address)) address = bookAddress || address;
  var match = address.match(/[?&]title_no=(\d+)(?:&|$)/) || address.match(/\/t(\d+)\//);
  if (!match) return address;
  var kind = /\/canvas\//i.test(address) ? 'canvas' : 'webtoon';
  return 'https://m.webtoons.com/api/v1/' + kind + '/' + match[1] + '/episodes?pageSize=9999';
})()'''

SEARCH_BOOK_URL = r'''@js:
(function () {
  var ident = String(java.getString('$.titleNo') || '');
  if (!/^\d+$/.test(ident)) return '';
  var variable = typeof source === 'undefined' ? '' : String(source.getVariable() || '').toUpperCase();
  var kind = variable.indexOf('CANVAS') >= 0 ? 'canvas' : 'wt';
  return 'https://m.webtoons.com/zh-hant/' + kind + '/t' + ident + '/list?title_no=' + ident;
})()'''


def remove_static_cookie(header):
    """Keep authored headers while allowing the app's current login cookie to apply."""
    parsed = header
    if isinstance(header, str):
        try:
            parsed = json.loads(header)
        except json.JSONDecodeError:
            return header
    if not isinstance(parsed, dict):
        return header
    names = [key for key in parsed if key.lower() == 'cookie']
    if not names:
        return header
    cleaned = {key: value for key, value in parsed.items() if key not in names}
    return json.dumps(cleaned, ensure_ascii=False) if isinstance(header, str) else cleaned


def repair_sources(sources):
    """Copy the export, preserving identity, authored settings and all other sources."""
    if not isinstance(sources, list) or not all(isinstance(s, dict) for s in sources):
        raise ValueError('Expected a JSON array of book-source objects')
    repaired = copy.deepcopy(sources)
    matches = 0
    for source in repaired:
        address = source.get('bookSourceUrl', '')
        if not isinstance(address, str):
            continue
        host = urlparse(address).hostname
        if host not in ('m.webtoons.com', 'www.webtoons.com'):
            continue
        search = source.get('searchUrl')
        if not isinstance(search, str):
            raise ValueError('WEBTOON source has no search rule')
        content = source.setdefault('ruleContent', {})
        if not isinstance(content, dict):
            raise ValueError('WEBTOON source has an invalid content rule object')
        explore = source.setdefault('ruleExplore', {})
        if not isinstance(explore, dict):
            raise ValueError('WEBTOON source has an invalid explore rule object')
        detail = source.setdefault('ruleBookInfo', {})
        if not isinstance(detail, dict):
            raise ValueError('WEBTOON source has an invalid book-info rule object')
        search_rules = source.setdefault('ruleSearch', {})
        if not isinstance(search_rules, dict):
            raise ValueError('WEBTOON source has an invalid search rule object')
        source['searchUrl'] = search.replace('m.webtoons.com/undefined/', 'm.webtoons.com/zh-hant/')
        if 'header' in source:
            source['header'] = remove_static_cookie(source['header'])
        content['content'] = CONTENT
        explore['bookList'] = EXPLORE_LIST
        explore['bookUrl'] = '@href'
        detail['tocUrl'] = TOC_URL
        search_rules['bookUrl'] = SEARCH_BOOK_URL
        matches += 1
    if not matches:
        raise ValueError('No WEBTOON source was found in this export')
    return repaired


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    if args.source.resolve() == args.output.resolve():
        parser.error('Use a new output path; the original export is preserved')
    sources = json.loads(args.source.read_text(encoding='utf-8-sig'))
    repaired = repair_sources(sources)
    with args.output.open('x', encoding='utf-8') as target:
        json.dump(repaired, target, ensure_ascii=False, indent=2)
    print(json.dumps({'sources': len(repaired), 'output': str(args.output)}, ensure_ascii=False))
