from pathlib import Path
root=Path(__file__).resolve().parents[2]
here=Path(__file__).parent
for name in ['ci.py','watch_ci.py','download_ipa.py','package_release.py','syntax_compare.py']:
    source=(root/'docs/release-1.1.0'/name).read_text(encoding='utf-8')
    source=source.replace('F:/SourceReadSwift/release-1.1.0','F:/SourceReadSwift/reader-toc-121')
    source=source.replace('71156be1ac148d6328dccc2844ed2555a41313b0','de82995c7c9848f48e5c242508b5d82c410be8c2')
    source=source.replace('71156be','de82995')
    source=source.replace('docs/release-1.1.0/RECOVERY.md','docs/reader-toc-121/RECOVERY.md')
    if name=='download_ipa.py':
        source=source.replace("== '120'","== '121'").replace('SourceReadSwift-1.1.0-unsigned.ipa','SourceReadSwift-1.1.0-build121-unsigned.ipa')
    (here/name).write_text(source,encoding='utf-8')
print('Isolated build121 helpers created; release120 artifacts unchanged.')
