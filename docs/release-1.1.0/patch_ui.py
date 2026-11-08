from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
p=ROOT/'SourceReadSwift/Features/SourceManager/SourceManagerView.swift'
s=p.read_text(encoding='utf8');start=s.index('        HStack(alignment: .top, spacing: 12) {',s.index('    private func sourceCard<'))
end=s.index('        .padding(14)',start)
s=s[:start]+'''        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.headline).foregroundStyle(.primary).lineLimit(2)
                    Text([subtitle, group].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Menu { actions() } label: {
                    Image(systemName: "ellipsis.circle").font(.title3)
                        .foregroundStyle(.secondary).frame(width: 44, height: 44)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    statusBadge(enabled ? "启用" : "停用", color: enabled ? .green : .gray)
                    ForEach(badges, id: \\.self) { badge in statusBadge(badge, color: AppTheme.accent) }
                }
            }
            if let health {
                Label("\\(health.status.title) · \\(health.testedAt.formatted(date: .abbreviated, time: .shortened))", systemImage: health.status.systemImage)
                    .font(.caption2.weight(.semibold)).foregroundStyle(health.status.color).lineLimit(1)
                Text(health.message).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            }
            if onLogin != nil || primaryAction != nil {
                HStack(spacing: 12) {
                    if let onLogin, loginHost != nil {
                        Button(action: onLogin) {
                            Label(isLoggedIn ? "已登录" : "登录", systemImage: isLoggedIn ? "checkmark.seal.fill" : "key.fill")
                        }
                    }
                    if let primaryAction {
                        Button(action: primaryAction) { Label("详情", systemImage: "info.circle") }
                    }
                }
                .font(.caption.weight(.semibold)).buttonStyle(.bordered).tint(AppTheme.accent)
                .labelStyle(.titleAndIcon).lineLimit(1).fixedSize(horizontal: false, vertical: true)
            }
        }
''' + s[end:]
s=s.replace('''        Text(text)
            .font(.caption2.weight(.bold))''','''        Text(text)
            .font(.caption2.weight(.bold))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)''',1)
p.write_text(s,encoding='utf8')
