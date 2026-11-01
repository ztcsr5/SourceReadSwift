import Foundation

/// Capture rendered DOM or a direct JSON document, never embedded script state.
enum WebsitePageCapture {
    static let script = """
    (()=>{
      const body=document.body;
      const first=body&&body.firstElementChild;
      const isDirectJSON=document.contentType.includes('json')||
        (body&&body.children.length===1&&first&&first.tagName==='PRE');
      if(isDirectJSON){
        const raw=body.innerText.trim();
        if(raw.length>2000000)throw new Error('响应过大，请打开具体目录或章节');
        if(raw.startsWith('{')||raw.startsWith('['))return JSON.stringify(JSON.parse(raw));
      }
      const root=document.documentElement.cloneNode(true);
      root.querySelectorAll('script,style,noscript,form,input,textarea,[hidden]').forEach(n=>n.remove());
      const html=root.outerHTML;
      if(html.length>2000000)throw new Error('网页过大，请打开具体目录或章节');
      return html;
    })()
    """
}
