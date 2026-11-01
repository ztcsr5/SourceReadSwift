import Foundation

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
