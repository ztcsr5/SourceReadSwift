from pathlib import Path
root=Path(__file__).resolve().parents[2]
p=root/'SourceReadSwift/Features/Discover/LANWorkbenchDocument.swift'
s=p.read_text(encoding='utf-8')
html=s.split('static let html = #"""\n',1)[1].rsplit('\n"""#',1)[0]
target=root/'SourceReadSwift/Resources/LANWorkbench.html'
target.write_text(html+'\n',encoding='utf-8')
p.write_text('''import Foundation

/// One bundled, offline document shared by the phone server and UI tests.
/// The HTML stays a normal resource so CSS/JS tooling can validate it directly.
enum LANWorkbenchDocument {
    static let html: String = {
        guard let url = Bundle.main.url(forResource: "LANWorkbench", withExtension: "html"),
              let document = try? String(contentsOf: url, encoding: .utf8) else {
            // An explicit packaging error, not a partially working editor.
            return "<!doctype html><html lang='zh-CN'><meta charset='utf-8'><title>资源缺失</title><h1>工作台资源缺失</h1><p>请重新安装完整应用。</p></html>"
        }
        return document
    }()
}
''',encoding='utf-8')
p=root/'docs/release-1.1.7/lan_ui_test.py'
s=p.read_text(encoding='utf-8')
old='''source=(ROOT/'SourceReadSwift/Features/Discover/LANWorkbenchDocument.swift').read_text(encoding='utf-8')
html=source.split('static let html = #"""\\n',1)[1].rsplit('\\n"""#',1)[0]'''
assert old in s
s=s.replace(old,"html=(ROOT/'SourceReadSwift/Resources/LANWorkbench.html').read_text(encoding='utf-8')")
p.write_text(s,encoding='utf-8')
print('Extracted standard HTML asset; document native test now also checks resource packaging.')
