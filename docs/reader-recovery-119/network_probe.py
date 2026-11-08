import os,socket,urllib.request,urllib.parse,json

proxies=urllib.request.getproxies()
print('PROXY', {k:('configured' if '@' in v else v) for k,v in proxies.items()})
for host in ['api.github.com','github.com']:
    try:print('DNS',host,sorted(set(x[4][0] for x in socket.getaddrinfo(host,443))))
    except OSError as e:print(type(e).__name__)
for port in [7890,7897,10809]:
    try:
        with socket.create_connection(('127.0.0.1',port),timeout=0.5):print('LOCAL_PROXY_PORT',port,'OPEN')
    except OSError:pass
