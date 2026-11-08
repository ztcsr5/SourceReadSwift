"""Explicit HTTPS route to the api.github.com address observed from DNS earlier.

Does not modify hosts/system proxy or weaken certificate/SNI verification.
Credentials stay on stdin and are never included in command output.
"""
import json,subprocess
API_IP='20.205.243.168'
def request(url,headers):
    args=['curl.exe','--noproxy','*','--resolve',f'api.github.com:443:{API_IP}',
          '--http1.1','--connect-timeout','15','--max-time','60','-sS','-i','--config','-','--url',url]
    config=''.join('header = '+json.dumps(k+': '+v)+'\n' for k,v in headers.items())
    p=subprocess.run(args,input=config.encode(),capture_output=True)
    if p.returncode:raise OSError('curl transport failed: '+p.stderr.decode(errors='replace'))
    head,body=p.stdout.split(b'\r\n\r\n',1)
    lines=head.decode('iso-8859-1').splitlines();status=int(lines[0].split()[1])
    response_headers=dict(line.split(': ',1) for line in lines[1:] if ': ' in line)
    return status,response_headers,body
