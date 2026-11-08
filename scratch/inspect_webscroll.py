with open(r"D:\Gemini反重力\SourceReadSwift2\SourceReadSwift\Features\Reader\WebScrollReaderView.swift", "r", encoding="utf-8") as f:
    lines = f.readlines()

for i, l in enumerate(lines):
    if 'case "visible":' in l:
        print("".join(lines[i:i+70]))
        break
