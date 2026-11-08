import json, subprocess, sys
import ci
job=int(sys.argv[1]); data=ci.ci.api(f'actions/jobs/{job}')
assert data['status']=='completed' and data['conclusion']=='failure'
assert data['head_sha']==ci.ci.HEAD
config='request = "POST"\n'+''.join('header = '+json.dumps(k+': '+v)+'\n' for k,v in ci.ci.HEADERS.items())
url='https://api.github.com/repos/'+ci.ci.REPO+f'/actions/jobs/{job}/rerun'
p=subprocess.run(['curl.exe','--noproxy','*','--resolve','api.github.com:443:20.205.243.168',
    '--http1.1','--connect-timeout','15','--max-time','60','-sS','-i','--config','-','--url',url],input=config.encode(),capture_output=True,check=True)
head,body=p.stdout.split(b'\r\n\r\n',1);code=int(head.splitlines()[0].split()[1])
record={'job':job,'status':code,'body':json.loads(body or b'{}')}
(ci.OUT/f'rerun-{job}.json').write_text(json.dumps(record,indent=2),encoding='utf8')
print('Job rerun HTTP',code)
if code not in [201,202]: print(body.decode()[:400]);raise SystemExit(1)
