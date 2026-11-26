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
        source['searchUrl'] = search.replace('m.webtoons.com/undefined/', 'm.webtoons.com/zh-hant/')
        content['content'] = CONTENT
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
