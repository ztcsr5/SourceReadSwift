from pathlib import Path
p=Path(__file__).resolve().parents[2]/'SourceReadSwift/Features/Discover/LANWorkbenchDocument.swift'
s=p.read_text(encoding='utf-8')
s=s.replace("signal,token=state.token}={})", "signal,token=state.token,allowFailedResult=false}={})")
s=s.replace("if(!response.ok||data.ok===false)","if(!response.ok||(data.ok===false&&!allowFailedResult))")
p.write_text(s,encoding='utf-8')
