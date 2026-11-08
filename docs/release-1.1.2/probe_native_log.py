import ci
try:
    b=ci.ci.signed_download('actions/jobs/124788537262/logs')
    (ci.OUT/'native-in-progress.log').write_bytes(b)
    print('Downloaded bytes',len(b))
    print('\n'.join(b.decode('utf8',errors='replace').splitlines()[-40:]))
except Exception as e: print(type(e).__name__,str(e)[:200])
