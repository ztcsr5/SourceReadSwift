from pathlib import Path
R=Path(__file__).resolve().parents[2]
def edit(n,f):
 p=R/n;s=p.read_text(encoding='utf-8');p.write_text(f(s),encoding='utf-8')
def once(s,a,b):
 assert s.count(a)==1,(a[:80],s.count(a));return s.replace(a,b,1)
def models(s):
 s=once(s,'    case kraft      //','    case kraftTexture\n    case parchmentTexture\n    case linen\n    case kraft      //')
 s=once(s,'            .paper,      //','            .kraftTexture, .parchmentTexture, .linen,\n            .paper,      //')
 s=once(s,'        case .kraft: return "牛皮纸"','        case .kraft: return "牛皮色"\n        case .kraftTexture: return "牛皮纸纹"\n        case .parchmentTexture: return "羊皮纸纹"\n        case .linen: return "亚麻纸纹"')
 s=s.replace('case .paper: return 0x','case .paper, .parchmentTexture: return 0x').replace('case .kraft: return 0x','case .kraft, .kraftTexture: return 0x')
 s=once(s,'        case .green: return 0xC2D8AA','        case .linen: return 0xF1EBDD\n        case .green: return 0xC2D8AA')
 s=once(s,'        case .green: return 0x596C44','        case .linen: return 0x38342F\n        case .green: return 0x596C44')
 s=once(s,'case .kraft, .green, .lavender, .azure:', 'case .kraft, .kraftTexture, .linen, .green, .lavender, .azure:')
 s=once(s,'case .paper, .kraft: return 0xDCDFE1','case .paper, .kraft, .parchmentTexture, .kraftTexture, .linen: return 0xDCDFE1')
 s=once(s,'case .paper, .kraft, .white, .gray, .eink,','case .paper, .kraft, .parchmentTexture, .kraftTexture, .linen, .white, .gray, .eink,')
 s=s.replace('    var color: Color {','    var hasTexture: Bool { self == .kraftTexture || self == .parchmentTexture || self == .linen }\n\n    var color: Color {',1)
 return s
edit('SourceReadSwift/Features/Reader/ReaderSettingsModels.swift',models)
def reader(s):
 s=s.replace('ReaderBackground.paper.rawValue','ReaderBackground.white.rawValue')
 s=s.replace('            } else {\n                readerThemeBackground\n            }','            } else if background.hasTexture {\n                ReaderPaperTextureView(background: background, night: readerIsNight)\n            } else {\n                readerThemeBackground\n            }',1)
 s=once(s,'        } else {\n            readerThemeBackground\n        }\n    }\n\n    /// 页眉','        } else if background.hasTexture {\n            ReaderPaperTextureView(background: background, night: readerIsNight)\n        } else {\n            readerThemeBackground\n        }\n    }\n\n    /// 页眉')
 s=once(s,'surfaceColor: background == .custom ? .clear', 'surfaceColor: background == .custom || background.hasTexture ? .clear')
 return s
edit('SourceReadSwift/Features/Reader/ReaderView.swift',reader)
def parser(s):
 a=s.index('        let trimmed = rule?.trimmingCharacters',s.index('    func list('))
 b=s.index('        guard !trimmed.isEmpty',a)
 s=s[:a]+'''        let raw = rule?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // Legado list modifiers apply before JS/JSONPath dispatch. Passing the
        // '+' into the JS pipeline evaluated a nonexistent '+' JSON property;
        // '-$..comic_chapter[*]' likewise never reached the descendant path.
        if raw.hasPrefix("+") || raw.hasPrefix("-") {
            let rows = list(from: object, rule: String(raw.dropFirst()), variables: variables)
            return raw.hasPrefix("-") ? Array(rows.reversed()) : rows
        }
        let trimmed = raw
'''+s[b:];return s
edit('SourceReadSwift/Core/Rules/JSONRuleExtractor.swift',parser)
edit('project.yml',lambda s:s.replace('MARKETING_VERSION: "1.1.0"','MARKETING_VERSION: "1.1.1"').replace('CURRENT_PROJECT_VERSION: "121"','CURRENT_PROJECT_VERSION: "122"'))
edit('SourceReadSwift/Shared/AppVersion.swift',lambda s:s.replace('raw ?? "1.1.0"','raw ?? "1.1.1"').replace('?? 120','?? 122'))
print('paper textures, defaults, list modifier fixes patched')
