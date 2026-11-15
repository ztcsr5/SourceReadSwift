import Foundation

/// Validates a guest launch link copied from LiveContainer; never manufactures a link or opens it automatically.
enum LiveContainerLaunchLink {
    static func url(from input: String) -> URL? {
        let clean = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.utf8.count <= 2_048, !clean.contains(where: \.isNewline),
              let components = URLComponents(string: clean),
              let scheme = components.scheme?.lowercased(),
              scheme.range(of: #"^livecontainer[1-9]?$"#, options: .regularExpression) != nil,
              components.host?.lowercased() == "livecontainer-launch",
              components.path.isEmpty || components.path == "/",
              components.user == nil, components.password == nil,
              components.port == nil, components.fragment == nil,
              let parameters = components.queryItems else { return nil }
        let allowed = Set(["bundle-name", "container-folder-name", "jit"])
        guard parameters.allSatisfy({ allowed.contains($0.name) }),
              Set(parameters.map(\.name)).count == parameters.count,
              let bundle = parameters.first(where: { $0.name == "bundle-name" })?.value,
              bundle != "ui", isSafeName(bundle) else { return nil }
        if let folder = parameters.first(where: { $0.name == "container-folder-name" }), !isSafeName(folder.value ?? "") { return nil }
        if let jit = parameters.first(where: { $0.name == "jit" }), !["true", "false"].contains(jit.value ?? "") { return nil }
        return components.url
    }

    private static func isSafeName(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 255 && !value.contains(where: \.isNewline)
            && !value.contains("/") && !value.contains("\\") && !value.contains("..")
    }
}
