from pathlib import Path
R=Path(__file__).resolve().parents[2]
def edit(n,old,new):
    p=R/n;s=p.read_text(encoding='utf8');assert old in s,n;s=s.replace(old,new);p.write_text(s,encoding='utf8')
p=R/'SourceReadSwift/Core/Rules/ContentParser.swift'
s=p.read_text(encoding='utf8');a=s.index('        // Preserve <img> tags');b=s.index('        output = output.replacingOccurrences(of: "(?i)<br',a)
s=s[:a]+'        output = ContentImageNormalizer.tokens(in: output)\n'+s[b:];p.write_text(s,encoding='utf8')
edit('SourceReadSwift/Features/Reader/ReaderView.swift',
     '            .padding(.top, readerTopSafeInset + 4)',
     '            .padding(.top, readerTopSafeInset + 4)\n            .background(readerThemeBackground.ignoresSafeArea(edges: .top))')
edit('project.yml','MARKETING_VERSION: 1.1.5','MARKETING_VERSION: 1.1.6')
edit('project.yml','CURRENT_PROJECT_VERSION: 126','CURRENT_PROJECT_VERSION: 127')
for name in ['ios.yml','unsigned-ipa.yml']:
    p=R/'.github/workflows'/name;s=p.read_text(encoding='utf8');s=s.replace('release-1.1.5','release-1.1.6');p.write_text(s,encoding='utf8')
