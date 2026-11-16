"""Replay production Android bridge contracts with synthetic, offline fixtures.

Usage: python -B -X utf8 -m unittest discover -s scripts -p test_source_android_bridges.py
Node verifies JavaScript dispatch; XCTest verifies the real JSCore/native digest boundary.
"""
import json
from pathlib import Path
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[1]


def replay_android_bridge(script: str) -> dict:
    """Evaluate the production bridge declarations without loading publisher scripts."""
    runtime = (ROOT / 'SourceReadSwift/Core/JavaScript/JSCoreRuntime.swift').read_text(encoding='utf8')
    digest = runtime.split('        Packages.cn = Packages.cn || {};', 1)[1].split('        Packages.cn.hutool.core =', 1)[0]
    responses = 'function __bridgeBody' + runtime.split('        function __bridgeBody', 1)[1].split('        // Minimal synchronous Promise facade.', 1)[0]
    constructor = ''
    if '        Packages.io = Packages.io || {};' in runtime:
        constructor = 'Packages.io = Packages.io || {};' + runtime.split('        Packages.io = Packages.io || {};', 1)[1].split('        Packages.cn =', 1)[0]
    bridge = (responses + constructor + digest).replace('\\\\', '\\')
    harness = """
    const crypto = require('node:crypto');
    const input = JSON.parse(require('node:fs').readFileSync(0, 'utf8'));
    const Packages = {cn: {}}, java = {};
    const __asJavaList = value => Array.from(value);
    const __javaBytes = value => Array.from(value, octet => Number(octet) & 255);
    const __native_digestBytes = (octets, algorithm) => Array.from(crypto.createHash(algorithm).update(Buffer.from(octets)).digest());
    eval(input.bridge);
    const result = eval(input.script);
    process.stdout.write(JSON.stringify(result));
    """
    completed = subprocess.run(['node', '-e', harness], input=json.dumps({'bridge': bridge, 'script': script}),
                               cwd=ROOT, capture_output=True, text=True, encoding='utf8', timeout=10)
    if completed.returncode:
        raise AssertionError(completed.stderr.strip())
    return json.loads(completed.stdout)


class SourceAndroidBridgeTests(unittest.TestCase):
    def test_md5_preserves_binary_input_and_returns_digest_bytes(self):
        result = replay_android_bridge("""
        ({digest: Packages.cn.hutool.crypto.digest.DigestUtil.md5([0, 127, 128, 255, 13, 10])});
        """)
        self.assertEqual(result['digest'], [92, 251, 68, 172, 200, 96, 201, 215, 194, 83, 29, 218, 210, 206, 54, 5])

    def test_md5_supports_empty_and_signed_octets(self):
        result = replay_android_bridge("""
        ({empty: Buffer.from(Packages.cn.hutool.crypto.digest.DigestUtil.md5([])).toString('hex'),
          signed: Buffer.from(Packages.cn.hutool.crypto.digest.DigestUtil.md5([0, 127, -128, -1, 13, 10])).toString('hex')});
        """)
        self.assertEqual(result, {'empty': 'd41d8cd98f00b204e9800998ecf8427e', 'signed': '5cfb44acc860c9d7c2531ddad2ce3605'})

    def test_str_response_replaces_body_and_preserves_original_response_contract(self):
        result = replay_android_bridge("""
        var original = __bridgeResponse('encoded', 'https://fixture.local/chapter');
        var response = Packages.io.legado.app.help.http.StrResponse(original.url(), 'decoded 正文');
        ({body: response.body(), url: response.url(), code: response.code(), message: response.message(),
          successful: response.isSuccessful(), headerCount: response.headers().size(), error: response.errorBody(),
          rawCode: response.raw().code(), originalCode: original.code, originalBody: String(original.body())});
        """)
        self.assertEqual(result, {'body': 'decoded 正文', 'url': 'https://fixture.local/chapter', 'code': 200,
                                  'message': 'OK', 'successful': True, 'headerCount': 0, 'error': None,
                                  'rawCode': 200, 'originalCode': 200, 'originalBody': 'encoded'})

    def test_str_response_supports_new_nullable_body_and_invalid_url_fallback(self):
        result = replay_android_bridge("""
        var response = new Packages.io.legado.app.help.http.StrResponse('not an absolute URL', null);
        ({body: response.body(), url: response.url(), code: response.code()});
        """)
        self.assertEqual(result, {'body': None, 'url': 'http://localhost/', 'code': 200})


if __name__ == '__main__':
    unittest.main()
