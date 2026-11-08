from pathlib import Path

p = Path("F:/SourceReadSwift/reader-quality-137/verification/snapshots-c906860/native-reader-gesture-test.log")
lines = p.read_text(encoding="utf8", errors="ignore").splitlines()
start = False
for l in lines:
    if "testReaderSystemReturnCanCancelWithReducedMotion" in l and "started" in l:
        start = True
    if start:
        print(l)
        if "testReaderSystemReturnCanCancelWithReducedMotion" in l and "failed" in l:
            break
