from pathlib import Path
r=Path(__file__).resolve().parents[2]; here=Path(__file__).parent
for name in ['watch_ci.py','graph.py','package_release.py','download_ipa.py','verify_delivery.py']:
 source=(r/'docs/reader-toc-121'/name).read_text(encoding='utf8')
 source=source.replace('F:/SourceReadSwift/reader-toc-121','F:/SourceReadSwift/release-1.1.1')
 source=source.replace('de82995c7c9848f48e5c242508b5d82c410be8c2','f808c790ae6d78a24ae599a72d79060fb140974d')
 if name=='download_ipa.py':
  source=source.replace("== '1.1.0'","== '1.1.1'").replace("== '121'","== '122'")
  source=source.replace('SourceReadSwift-1.1.0-build121-unsigned.ipa','SourceReadSwift-1.1.1-build122-unsigned.ipa')
 (here/name).write_text(source,encoding='utf8')
