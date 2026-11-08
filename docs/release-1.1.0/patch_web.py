from pathlib import Path
R=Path(__file__).resolve().parents[2]
p=R/'SourceReadSwift/Features/Discover/SourceWritingView.swift';s=p.read_text(encoding='utf8')
a=s.index('    :root {',s.index('private func getWebPageHtml'));b=s.index('    * { box-sizing',a)
s=s[:a]+'''    :root {
      color-scheme: light dark;
      --bg: #f5f5f7; --card-bg: #ffffff; --card-border: #e6e6ec;
      --text: #20202a; --text-muted: #70717e; --primary: #594fdb;
      --primary-hover: #4840bb; --success: #237c5c; --warning: #ad711b;
      --danger: #c94150; --editor-bg: #fafafd;
    }
    @media (prefers-color-scheme: dark) {
      :root { --bg: #17171d; --card-bg: #23232d; --card-border: #383844;
        --text: #f0f0f5; --text-muted: #aaaab8; --primary: #a19aff;
        --primary-hover: #8880ec; --editor-bg: #1c1c24; }
    }
'''+s[b:]
override='''
    /* InPage workbench: system typography, quiet grouped surfaces and a
       segmented navigation. Entirely local assets; no CDN/font dependency. */
    body { padding: 44px 28px; letter-spacing: -.012em; }
    .container { max-width: 1180px; }
    .header { border: 0; padding: 0 4px 28px; margin: 0; gap: 24px; }
    .header h1 { font-size: 30px; font-weight: 650; letter-spacing: -.045em; }
    .header p { margin-top: 10px !important; line-height: 1.7; }
    .brand-kicker { font-size: 11px; font-weight: 650; letter-spacing: .18em; color: var(--primary); margin-bottom: 9px; }
    .status-badge { background: color-mix(in srgb, var(--success) 10%, transparent); color: var(--success); padding: 8px 14px; flex-shrink: 0; }
    .tabs { width: fit-content; max-width: 100%; padding: 4px; gap: 4px; border: 0; border-radius: 14px; background: rgba(128,128,150,.12); margin-bottom: 30px; }
    .tab-btn { flex: none; min-height: 42px; padding: 9px 22px; font-weight: 550; white-space: nowrap; border-radius: 11px; }
    .tab-btn.active { color: var(--text); background: var(--card-bg); box-shadow: 0 2px 7px rgba(30,30,50,.09); }
    .card { border-radius: 22px; padding: 26px; border-color: var(--card-border); box-shadow: 0 8px 32px rgba(30,30,55,.025); }
    .card-title { font-size: 17px; gap: 16px; flex-wrap: wrap; margin-bottom: 20px; }
    .card-title > div { flex-wrap: wrap; }
    .btn { min-height: 38px; border-radius: 10px; padding: 9px 14px; font-weight: 550; transition: background .15s, transform .15s; }
    .btn:active { transform: scale(.97); }
    .btn-primary { background: #594fdb; color: #fff; }
    .btn-outline { background: rgba(128,128,150,.065); }
    .btn:focus-visible, .tab-btn:focus-visible, .input:focus-visible, textarea:focus-visible { outline: 3px solid var(--primary); outline-offset: 3px; }
    .input { background: var(--editor-bg); color: var(--text); border-radius: 9px; min-height: 40px; }
    .editor-wrapper { border-radius: 15px; overflow: hidden; border: 1px solid var(--card-border); }
    .code-editor { background: var(--editor-bg); color: var(--text); min-height: 440px; line-height: 1.65; padding: 22px; font-size: 13px; }
    .terminal { background: var(--editor-bg); color: var(--text); border-radius: 14px; border: 1px solid var(--card-border); }
    .book-card { background: var(--editor-bg); border-radius: 13px; }
    .book-card h4 { color: var(--primary); }
    .toast { color: var(--text); border-radius: 14px; box-shadow: 0 8px 32px rgba(20,20,40,.14); }
    #current-source-title, #debug-content-card { color: var(--text) !important; }
    #debug-toc-list, #debug-content-card { background: var(--editor-bg) !important; border-radius: 12px !important; }
    @media (max-width: 640px) {
      body { padding: 24px 14px; }
      .header { flex-direction: column; align-items: flex-start; gap: 16px; padding-bottom: 24px; }
      .header h1 { font-size: 27px; }
      .tabs { width: 100%; overflow-x: auto; }
      .tab-btn { flex: 1; padding: 9px 13px; font-size: 13px; }
      .card { padding: 18px; border-radius: 18px; }
      .card-title > div { width: 100%; }
      .code-editor { min-height: 360px; padding: 15px; }
    }
    @media (prefers-reduced-motion: reduce) { * { transition: none !important; animation: none !important; } }
'''
s=s.replace('  </style>',override+'  </style>',1)
s=s.replace('<title>SourceRead 书源工作台 · 编写 · 调试 · 管理</title>','<title>纸间 · 书源工作台</title>')
s=s.replace('<h1>📖 SourceRead 书源工作台</h1>','<div class="brand-kicker">INPAGE / WORKSPACE</div>\n        <h1>纸间 · 书源工作台</h1>')
s=s.replace('✍️ 书源编辑与推送','书源编辑').replace('🧪 在线实时调试控制台','解析调试').replace('📚 手机源库诊断与管理','源库管理')
p.write_text(s,encoding='utf8')
# Browser preview is an exact extraction, never a separately designed mock.
a=s.index('<!DOCTYPE html>',s.index('private func getWebPageHtml'));b=s.index('"""#',a) if '"""#' in s[a:] else s.index('"""',a)
(R/'docs/release-1.1.0/workbench-preview.html').write_text(s[a:b],encoding='utf8')
