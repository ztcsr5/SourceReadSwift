from pathlib import Path
root=Path(__file__).resolve().parents[2]
p=root/'SourceReadSwift/Features/SourceManager/SourceOrganizationView.swift'
s=p.read_text(encoding='utf8')
start=s.index('                Section("管理分组") {')
end=s.index('                if let error = store.lastError',start)
block=s[start:end]
body=block[block.index('\n')+1:block.rfind('                }')]
s=s[:start]+s[end:]
target='                ForEach(SourcePlacement.allCases) { placement in'
replacement='                Section {\n                    DisclosureGroup("管理分组") {\n'+body+'                    }\n                }\n'+target
s=s.replace(target,replacement,1)
p.write_text(s,encoding='utf8')
print('Moved group controls above long source list, collapsed by default')
