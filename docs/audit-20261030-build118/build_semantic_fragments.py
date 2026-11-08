"""Encode reviewed relationships; not automatic correctness findings."""
import json
from pathlib import Path

OUT=Path(__file__).resolve().parent
READER='SourceReadSwift/Features/Reader/'

def fragment(name, definitions, relationships):
    nodes=[{'id':i,'label':label,'file_type':kind,'source_file':source,'source_location':location} for i,label,source,location,kind in definitions]
    edges=[{'source':a,'target':b,'relation':relation,'confidence':'EXTRACTED','confidence_score':1.0,'source_file':source,'source_location':location,'weight':1.0} for a,b,relation,source,location in relationships]
    (OUT/name).write_text(json.dumps({'nodes':nodes,'edges':edges,'hyperedges':[]},ensure_ascii=False,indent=2),encoding='utf8')

def main():
    fragment('graph-pagination.json',[
        ('review_reader','ReaderView',READER+'ReaderView.swift','7','code'),
        ('review_paginator','ReaderChapterPaginator',READER+'ReaderChapterPaginator.swift','1-213','code'),
        ('review_geometry','ReaderPageGeometry',READER+'ReaderPageGeometry.swift','64-229','code'),
        ('review_identity','ReaderPageIdentity',READER+'ReaderPageSelection.swift','1-32','code'),
        ('review_textcache','ReaderPageTextCache',READER+'ReaderView.swift','6704-6779','code'),
        ('review_textview','ReaderPageTextView',READER+'ReaderPageTextView.swift','173-224','code'),
        ('review_mapping','ReaderPositionMapping',READER+'ReaderPositionMapping.swift','1-121','code'),
        ('review_pagination_report','Pagination audit','docs/audit-20261030-build118/pagination-audit.md','1-152','document'),
    ],[
        ('review_reader','review_paginator','calls',READER+'ReaderView.swift','6567-6599'),
        ('review_reader','review_geometry','references',READER+'ReaderView.swift','573-593'),
        ('review_reader','review_identity','references',READER+'ReaderView.swift','2866-2868'),
        ('review_reader','review_textcache','calls',READER+'ReaderView.swift','2871-2876'),
        ('review_reader','review_textview','references',READER+'ReaderView.swift','2830-2834'),
        ('review_reader','review_mapping','references',READER+'ReaderView.swift','6252-6260'),
        ('review_pagination_report','review_textcache','references','docs/audit-20261030-build118/pagination-audit.md','13-30'),
        ('review_pagination_report','review_paginator','references','docs/audit-20261030-build118/pagination-audit.md','45-64'),
    ])
    fragment('graph-project.json',[
        ('review_app','SourceReadSwiftApp','SourceReadSwift/App/SourceReadSwiftApp.swift','1','code'),
        ('review_root','RootTabView','SourceReadSwift/App/RootTabView.swift','1','code'),
        ('review_appstate','AppState','SourceReadSwift/App/AppState.swift','163-258','code'),
        ('review_reader','ReaderView',READER+'ReaderView.swift','7','code'),
        ('review_webscroll','WebScrollReaderView',READER+'WebScrollReaderView.swift','1','code'),
        ('review_cover','CoverPageReaderView',READER+'CoverPageReaderView.swift','1','code'),
        ('review_ci','iOS unit-test workflow','.github/workflows/ios.yml','54-69','document'),
        ('review_package','Independent IPA workflow','.github/workflows/unsigned-ipa.yml','7-38','document'),
        ('review_project','XcodeGen project','project.yml','1-101','document'),
        ('review_project_report','Project audit','docs/audit-20261030-build118/project-audit.md','1-116','document'),
    ],[
        ('review_app','review_root','references','SourceReadSwift/App/SourceReadSwiftApp.swift','1'),
        ('review_reader','review_appstate','references',READER+'ReaderView.swift','8'),
        ('review_reader','review_webscroll','references',READER+'ReaderView.swift','1584-1588'),
        ('review_reader','review_cover','references',READER+'ReaderView.swift','2553-2614'),
        ('review_ci','review_project','references','.github/workflows/ios.yml','54-69'),
        ('review_package','review_project','references','.github/workflows/unsigned-ipa.yml','7-38'),
        ('review_project_report','review_appstate','references','docs/audit-20261030-build118/project-audit.md','54-60'),
        ('review_project_report','review_ci','references','docs/audit-20261030-build118/project-audit.md','22-28'),
    ])
    print('semantic fragments: pagination/project written')

if __name__=='__main__':main()
