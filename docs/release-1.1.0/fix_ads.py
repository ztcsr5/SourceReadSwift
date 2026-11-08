from pathlib import Path
p=Path(__file__).resolve().parents[2]/'SourceReadSwift/Features/Discover/WebReadingSession.swift'
s=p.read_text(encoding='utf8')
s=s.replace('\\\\\\\\.', '\\\\.')
p.write_text(s,encoding='utf8')
