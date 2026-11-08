"""Apply reviewed theme page boundaries, preserving bodies/actions. Usage: python -X utf8 scripts/release117_theme_pages.py [--apply]"""
from pathlib import Path
import json,re,sys
ROOT=Path(__file__).resolve().parents[1]
OUT=Path('F:/SourceReadSwift/release-1.1.7/theme17')
names=[
 'Features/Settings/'+n+'.swift' for n in ['SettingsView','CookieManagerView','CustomFontManagementView',
 'PrivacyLegalView','ReaderDataManagementViews','RecentDiagnosticsView','SourceProxySettingsView','TTSSettingsView','WebDAVSyncView','AIGeneratedSourceReviewView']
]+['Features/SourceManager/'+n+'.swift' for n in ['SourceLoginCenterView','SourceLoginView',
 'SourceRuleEditorView','SourceOrganizationView','SourceDiagnosticHistoryView','RSSSourceEditorView','SourceManagerView','WebsiteSourceBuilderView']]
names+=['Features/Verification/VerificationCodeSheet.swift','Features/RSS/RSSArticlesView.swift']
changes=[]
for name in names:
    p=ROOT/'SourceReadSwift'/name;before=p.read_bytes();text=before.decode('utf-8')
    lines=text.splitlines(keepends=True);result=[];added=[]
    for index,line in enumerate(lines):
        if '.navigationTitle(' in line and '.pageBackground()' not in line:
            # Adjacent modifiers may already own the page background. Do not
            # attach a second surface to the same view.
            start=index-1
            while start>=0 and lines[start].lstrip().startswith('.') :start-=1
            chain=''.join(lines[max(start,0):index])
            if '.pageBackground()' not in chain:
                indent=re.match(r'\s*',line).group();ending='\r\n' if line.endswith('\r\n') else '\n'
                result.append(indent+'.pageBackground()'+ending);added.append(index+1)
        result.append(line)
    if added:
        backup=OUT/'BASELINE'/p.relative_to(ROOT)
        assert backup.exists() and backup.read_bytes()==before,p
        changes.append({'path':str(p.relative_to(ROOT)),'navigation_title_lines':added})
        if '--apply' in sys.argv:p.write_bytes(''.join(result).encode('utf-8'))
(OUT/'page-boundaries.json').write_text(json.dumps(changes,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(changes,ensure_ascii=False,indent=2))
