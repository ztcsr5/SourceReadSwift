import ci
try:
    data=ci.ci.signed_download('actions/jobs/124835066127/logs')
except Exception as e:
    print('Running job log unavailable:',type(e).__name__)
else:
    path=ci.OUT/'running-test.log';path.write_bytes(data)
    lines=data.decode('utf8',errors='replace').splitlines()
    print('\n'.join(lines[-45:]))
