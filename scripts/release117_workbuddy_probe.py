"""Call the explicitly selected local WorkBuddy gateway with synthetic fixtures only.
Usage: WORKBUDDY_API_KEY=<in-memory secret> python -X utf8 scripts/release117_workbuddy_probe.py
Writes no credentials; no proxy, redirect, automatic retry, or repository upload.
"""
from pathlib import Path
from datetime import datetime, timezone
import argparse
import base64
import hashlib
import io
import json
import os
import re
from urllib.parse import urlsplit

import requests
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
MAXIMUM_RESPONSE_BYTES = 2_000_000


def build_cases():
    swift = (ROOT / "SourceReadSwift/Core/AI/AIChatClient.swift").read_text(encoding="utf-8")
    system = re.search(r'var wire: .*?"content": "([^"\n]+)"', swift)
    if system is None:
        raise ValueError("Cannot locate the production system message; do not invent a replacement")
    prose = "\n".join(f"第{index}段。山谷的风从纸页间穿过，这是合成回归文本，不是真实用户资料。" for index in range(8))
    source = {"bookSourceName": "WorkBuddy合成回归", "bookSourceUrl": "https://fixture.example",
              "ruleBookInfo": {"name": "h1@text"},
              "ruleToc": {"chapterList": "#chapters a", "chapterName": "text", "chapterUrl": "href"},
              "ruleContent": {"content": "#content@html", "title": "h1@text"}}
    chapter = "<h1>第二章 山谷</h1><div id='content'>" + "".join("<p>" + line + "</p>" for line in prose.splitlines()) + "</div>"
    catalog = "<h1>合成书籍</h1><div id='chapters'><a href='/chapter/1'>第一章 起风</a><a href='/chapter/2'>第二章 山谷</a></div>"
    attachments = [
        {"name": "source.json", "text": json.dumps(source, ensure_ascii=False)},
        {"name": "chapter.html", "text": chapter},
        {"name": "purification.json", "text": '[{"name":"合成广告行","pattern":"^广告行$","enabled":false}]'},
    ]
    question = "只输出一个 Legado BookSource JSON 对象，不要说明文字。保留 source.json 的源名、URL 和声明式 CSS 规则；不要添加搜索接口、JavaScript、网络请求或未知字段。chapter.html 和 purification.json 仅是复核资料，不执行任何规则。"
    picture = io.BytesIO()
    Image.new("RGB", (16, 16), (40, 100, 180)).save(picture, format="JPEG", quality=85)
    cases = [
        {"name": "source-files-purification", "text": question, "attachments": attachments, "supportsImages": False},
        {"name": "synthetic-image", "text": "请用一句中文描述图片的主要颜色。图片为合成色块，不包含文字。",
         "attachments": [{"name": "solid-color.jpg", "jpegBase64": base64.b64encode(picture.getvalue()).decode("ascii")}], "supportsImages": True},
    ]
    return system[1], cases, {"catalog": catalog, "chapter": chapter}


def build_request(system, case, model):
    text = case["text"]
    images = []
    for attachment in case["attachments"]:
        if "text" in attachment:
            text += "\n\n--- 附件：" + attachment["name"] + " ---\n" + attachment["text"] + "\n--- 附件结束 ---"
        else:
            images.append({"type": "image_url", "image_url": {"url": "data:image/jpeg;base64," + attachment["jpegBase64"], "detail": "auto"}})
    content = [{"type": "text", "text": text}] + images if images else text
    return {"model": model, "messages": [{"role": "system", "content": system}, {"role": "user", "content": content}], "stream": False}


def request_once(session, method, url, payload=None):
    credential = session.headers["Authorization"].removeprefix("Bearer ")
    with session.request(method, url, json=payload, timeout=(8, 90), allow_redirects=False, stream=True) as response:
        body = bytearray()
        for chunk in response.iter_content(16_384):
            body.extend(chunk)
            if len(body) > MAXIMUM_RESPONSE_BYTES:
                raise ValueError("Gateway response exceeds2MB")
        if credential.encode() in body:
            raise ValueError("Gateway echoed a credential; response will not be saved")
        return response.status_code, bytes(body)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--endpoint", default="http://127.0.0.1:8788/v1")
    parser.add_argument("--model", default="workbuddy/deepseek-v4.1-flash")
    parser.add_argument("--output", type=Path, default=Path("F:/SourceReadSwift/release-1.1.7/workbuddy/provider-fixture.json"))
    arguments = parser.parse_args()
    parts = urlsplit(arguments.endpoint)
    if parts.hostname not in ("127.0.0.1", "localhost", "::1") or parts.scheme not in ("http", "https") or parts.username or parts.password or parts.query or parts.fragment:
        raise ValueError("This probe is limited to an explicit credential-free local gateway URL")
    credential = os.environ.get("WORKBUDDY_API_KEY", "").strip()
    if not credential or "\n" in credential or "\r" in credential:
        raise ValueError("WORKBUDDY_API_KEY is required in process memory")
    session = requests.Session()
    session.trust_env = False
    session.headers["Authorization"] = "Bearer " + credential
    base = arguments.endpoint.rstrip("/")
    status, model_body = request_once(session, "GET", base + "/models")
    if status != 200:
        raise RuntimeError(f"Gateway model discovery returned HTTP{status}; no chat request made")
    models = [entry.get("id", "") for entry in json.loads(model_body).get("data", [])]
    if arguments.model not in models:
        safe_matches = [model for model in models if "deepseek" in model.lower()][:12]
        print(json.dumps({"requested_model_available": False, "advertised_deepseek_models": safe_matches}, ensure_ascii=False))
        raise RuntimeError("Requested WorkBuddy model is not advertised; no substitute or chat request used")
    system, cases, samples = build_cases()
    receipt = {"recordedAtUTC": datetime.now(timezone.utc).isoformat(), "endpoint": base + "/chat/completions",
               "model": arguments.model, "scope": "Real local gateway requests with synthetic fixtures only; native replay is not iPhone-to-PC acceptance.",
               "samples": samples, "cases": []}
    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    for case in cases:
        wire = build_request(system, case, arguments.model)
        status, body = request_once(session, "POST", receipt["endpoint"], wire)
        record = dict(case, request=wire, status=status, responseBase64=base64.b64encode(body).decode("ascii"),
                      responseSHA256=hashlib.sha256(body).hexdigest())
        receipt["cases"].append(record)
        arguments.output.write_text(json.dumps(receipt, ensure_ascii=False, indent=2), encoding="utf-8")
        print(json.dumps({"case": case["name"], "status": status, "bytes": len(body), "response_sha256": record["responseSHA256"]}))
        if status in (401, 403) or (status != 200 and not case["supportsImages"]):
            raise RuntimeError(f"Gateway rejected {case['name']} with HTTP{status}; no retry")
    session.close()


if __name__ == "__main__":
    main()
