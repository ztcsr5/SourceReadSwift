from pathlib import Path
import re,sys
sys.stdout.reconfigure(encoding='utf-8')
terms=re.compile(r'prewarm|readerPageRevisionKey|commitCoverTurn|CoverSettle|FlipTransition|coverPageSlot|enum ReaderMode|pageCurlReaderContent|CoverPageHostController|cover.*[Ss]ettle|flip.*[Tt]ransition')
for base in ('SourceReadSwift/Features/Reader','SourceReadSwiftTests'):
 for p in Path(base).rglob('*.swift'):
  for i,line in enumerate(p.read_text(encoding='utf-8').splitlines(),1):
   if terms.search(line):print(f'{p}:{i}: {line[:250]}')
