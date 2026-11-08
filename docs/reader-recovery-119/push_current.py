import urllib.request
from commit_and_push import run
proxy=urllib.request.getproxies().get('https')
args=['git']
if proxy:args+=['-c','http.proxy='+proxy]
run(args+['push','-u','origin','HEAD:codex/reader-recovery-119'])
