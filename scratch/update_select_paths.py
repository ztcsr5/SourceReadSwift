path = r"D:\Gemini反重力\SourceReadSwift2\scripts\verify_reader_quality.py"
with open(path, "r", encoding="utf-8") as f:
    text = f.read().replace("\r\n", "\n")

old = '{".github/workflows/ios.yml", ".github/workflows/unsigned-ipa.yml", ".github/workflows/reader-diagnostics.yml", "project.yml", "SourceReadSwift/App/Info.plist",'
new = '{".github/workflows/ios.yml", ".github/workflows/unsigned-ipa.yml", ".github/workflows/reader-diagnostics.yml", ".github/workflows/floating-desk.yml", "project.yml", "SourceReadSwift/App/Info.plist", "CHANGELOG.md",'

assert old in text, "old pattern not found"
text = text.replace(old, new, 1)

with open(path, "w", encoding="utf-8", newline="\n") as f:
    f.write(text)
print("SUCCESS: verify_reader_quality.py updated!")
