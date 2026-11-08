from pathlib import Path
import shutil
root=Path(__file__).resolve().parents[2]
out=Path('F:/SourceReadSwift/release-1.1.7/pre-item15-16')
names=['SourceReadSwift/App/AppState.swift','SourceReadSwift/App/RootTabView.swift',
       'SourceReadSwift/Features/Discover/DiscoverView.swift','SourceReadSwift/Features/Settings/SettingsView.swift',
       'SourceReadSwift/Shared/DesignSystem/LegacyTabBar.swift']
for name in names:
 target=out/name;target.parent.mkdir(parents=True,exist_ok=True)
 if not target.exists():shutil.copyfile(root/name,target)
def modify(name,old,new):
 p=root/name;s=p.read_text(encoding='utf-8');assert s.count(old)==1,(name,old,s.count(old));p.write_text(s.replace(old,new),encoding='utf-8')
modify(names[0],'    let sourceStore: SourceStore','    let readingNote = ReadingNoteCatalog.launchNote\n    let sourceStore: SourceStore')
modify(names[1],'Label("发现", systemImage: "square.grid.2x2")','Label(AppNavigationLabels.findBooks, systemImage: AppNavigationLabels.findBooksSymbol)')
modify(names[4],'tab(1, title: "发现", icon: "square.grid.2x2")','tab(1, title: AppNavigationLabels.findBooks, icon: AppNavigationLabels.findBooksSymbol)')
p=root/names[3];s=p.read_text(encoding='utf-8')
start=s.index('            HStack(spacing: 12) {',s.index('    private var settingsHeroSection:'))
end=s.index('            .listRowBackground(Color.clear)',start)
s=s[:start]+'            SettingsBrandHeader(readingNote: appState.readingNote)\n'+s[end:]
p.write_text(s,encoding='utf-8')
modify(names[2],'.navigationTitle("发现")','.navigationTitle(AppNavigationLabels.findBooks)')
modify(names[2],'case explore = "分类发现"','case explore = "分类寻书"')
modify(names[2],'当前启用的书源中未配置分类发现规则(exploreUrl)。','当前启用的书源中未配置分类寻书规则(exploreUrl)。')
modify(names[2],'展开全部发现书源列表','展开全部寻书书源列表')
modify(names[2],'全部发现书源 (','全部寻书书源 (')
print('Added launch-scoped settings note; native and legacy navigation share book discovery label/icon.')
