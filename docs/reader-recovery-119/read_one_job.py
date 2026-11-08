import re,sys
from ci_status import OUT,signed_download
job=int(sys.argv[1])
data=signed_download(f'actions/jobs/{job}/logs')
path=OUT/f'job-{job}.log';path.write_bytes(data)
for line in data.decode('utf8',errors='replace').splitlines():
    if re.search(r'PAGE_DIAGNOSTIC|PAGE_LINE|error:|Test Case .* failed|Executed \d+ tests, with [1-9]|Test Suite .All tests.|\*\* (TEST|BUILD)',line):print(line)
