import json
import re
from pathlib import Path

root = Path(__file__).resolve().parents[2]
source = root / 'SourceReadSwift/Features/Discover/WebReadingSession.swift'
text = source.read_text(encoding='utf-8')
raw = text.split('static let json = #"', 1)[1].split('"#', 1)[0]
rules = json.loads(raw)
pattern = rules[0]['trigger']['url-filter']
urls = ['https://doubleclick.net/ad.js', 'https://ads.doubleclick.net/ad.js',
        'https://googlesyndication.com/pagead.js', 'https://adservice.google.com/ad.js']
result = {'file': str(source), 'decoded_pattern_repr': repr(pattern),
          'raw_backslash_count': raw.count(chr(92)), 'decoded_backslash_count': pattern.count(chr(92)),
          'domain_tests': [{'url': url, 'matched': bool(re.search(pattern, url))} for url in urls]}
print(json.dumps(result, indent=2, ensure_ascii=False))
