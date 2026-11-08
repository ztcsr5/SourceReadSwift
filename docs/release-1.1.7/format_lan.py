from pathlib import Path
root=Path(__file__).resolve().parents[2]
p=root/'SourceReadSwift/Features/Discover/LANWorkbenchDocument.swift'
html=Path('F:/SourceReadSwift/release-1.1.7/lan-ui/index.html').read_text(encoding='utf-8').rstrip()
assert html.startswith('<!doctype html>') or html.startswith('<!DOCTYPE html>')
assert 'X-SourceRead-Token' in html and 'allowFailedResult' in html
p.write_text('''import Foundation

/// One offline document shared by the phone server and browser regression
/// fixtures. No fonts, editor SDKs, analytics or other CDN requests.
enum LANWorkbenchDocument {
    static let html = #"""
'''+html+'\n"""#\n}\n',encoding='utf-8')
test=root/'SourceReadSwiftTests/LANWorkbenchTests.swift'
s=test.read_text(encoding='utf-8').replace('html.contains("slice(start,start+20)")','html.contains("每页 20 条")')
test.write_text(s,encoding='utf-8')
print('Formatted embedded HTML/CSS/JS for maintainability; no dependency added to phone or page.')
