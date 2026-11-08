from pathlib import Path
R=Path(__file__).resolve().parents[2]
p=R/'SourceReadSwift/Features/Reader/ReaderView.swift';s=p.read_text(encoding='utf8')
a=s.index('    /// Fixed top scrim for scroll mode')
b=s.index('    private var readerFooter: some View',a)
s=s[:a]+'''    private var readerHeader: some View {
        TimelineView(.everyMinute) { context in
            VStack(spacing: 0) {
                ReaderScrollChapterHeader(
                    title: chapterHeadingStyle == .hidden ? nil : currentDisplayChapterTitle,
                    geometry: scrollChromeGeometry,
                    horizontalPadding: CGFloat(pagePadding),
                    foreground: readerThemeTextColor,
                    paper: readerThemeBackground
                ) {
                    // Keep explicit top-clock/battery preferences; the default
                    // bottom-status layout leaves only the chapter name here.
                    if statusPosition == "top" || statusPosition == "both" {
                        HStack(spacing: 8) {
                            if footerShowTime {
                                Text(context.date, format: .dateTime.hour().minute())
                            }
                            if footerShowBatteryIcon { Image(systemName: batterySymbolName) }
                            if footerShowBatteryPercent { Text(batteryPercentageText) }
                        }
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(readerThemeTextColor.opacity(0.55))
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

'''+s[b:];p.write_text(s,encoding='utf8')
p=R/'SourceReadSwiftTests/ReaderAutomationPolicyTests.swift';s=p.read_text(encoding='utf8')
s=s.replace('ReaderScrollChromePolicy.statusScrimHeight(safeTop: 59, headerVisible: false)','ReaderScrollChromeGeometry(safeTop: 59, headerVisible: false, showSystemStatusBar: true).protectedHeight').replace('ReaderScrollChromePolicy.statusScrimHeight(safeTop: 59, headerVisible: true)','ReaderScrollChromeGeometry(safeTop: 59, headerVisible: true, showSystemStatusBar: true).protectedHeight').replace('ReaderScrollChromePolicy.statusScrimHeight(safeTop: 0, headerVisible: false)','ReaderScrollChromeGeometry(safeTop: 0, headerVisible: false, showSystemStatusBar: true).protectedHeight')
s=s.replace('// Dynamic Island portrait: 59pt safe area + 10pt fade.','// Opaque protection ends at the actual safe-area boundary; no fade.').replace('            69,','            59,').replace('// With the in-reader header: add headerTopGap (2) + band (22).','// Header: safe59 + top gap2 + band22 + body gap6.').replace('            93,','            89,').replace('            30,','            20,')
p.write_text(s,encoding='utf8')
for n in ['project.yml','SourceReadSwift/Shared/AppVersion.swift']:
 p=R/n;s=p.read_text(encoding='utf8');assert '1.1.2' in s
 s=s.replace('1.1.2','1.1.3').replace('"123"','"124"');p.write_text(s,encoding='utf8')
print('Scroll chrome and version updated')
