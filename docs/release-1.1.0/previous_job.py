import re
import ci
job = 124523418327
path = ci.OUT / f'job-{job}.log'
if not path.exists(): path.write_bytes(ci.ci.signed_download(f'actions/jobs/{job}/logs'))
lines = path.read_text(encoding='utf8', errors='replace').splitlines()
for line in lines:
    if re.search(r'Test Case .* failed|error:|Executed \d+ tests|\*\* (TEST|BUILD)', line): print(line)
print('\n'.join(lines[-8:]))
