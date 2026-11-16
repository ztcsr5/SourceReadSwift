"""Replay production image JS shims with Node crypto; native transport/ImageIO stay covered by XCTest.

Usage: python -B -X utf8 -m unittest discover -s scripts -p test_source_image_bytes.py
No publisher scripts, source URLs or account credentials are loaded.
"""

import json
from pathlib import Path
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[1]


def replay_image_bridge(script: str) -> dict:
    """Run the actual Swift-embedded compatibility functions with binary native stubs."""
    runtime = (ROOT / "SourceReadSwift/Core/JavaScript/JSCoreRuntime.swift").read_text(encoding="utf8")
    bridge = runtime.split("        function __cipherArgs", 1)[1].split("        java.setContent", 1)[0]
    bridge = ("function __cipherArgs" + bridge).replace("\\\\", "\\")
    harness = r"""
    const vm = require('node:vm');
    const crypto = require('node:crypto');
    const NativeBuffer = Buffer;
    const input = JSON.parse(require('node:fs').readFileSync(0, 'utf8'));
    const bytes = value => typeof value === 'string' ? NativeBuffer.from(value) : NativeBuffer.from(value || []);
    const context = vm.createContext({
      java: {}, __asJavaList: value => Array.from(value),
      __native_stringToBytes: value => Array.from(NativeBuffer.from(value)),
      __native_bytesToString: value => bytes(value).toString('utf8'),
      __native_base64DecodeBytes: value => Array.from(NativeBuffer.from(value, 'base64')),
      __native_base64EncodeBytes: value => bytes(value).toString('base64'),
      __nativeLegado: {invoke: request => {
        const [payload, key, transformation, iv] = request.args;
        if (!/^AES\/CBC\/PKCS7Padding$/i.test(transformation)) throw Error('Unexpected fixture transformation');
        const create = request.method === 'cipherEncryptBytes' ? crypto.createCipheriv : crypto.createDecipheriv;
        const cipher = create('aes-128-cbc', bytes(key), bytes(iv));
        return Array.from(NativeBuffer.concat([cipher.update(bytes(payload)), cipher.final()]));
      }}
    });
    vm.runInContext(input.bridge, context, {timeout: 2000});
    const result = vm.runInContext(input.script, context, {timeout: 2000});
    process.stdout.write(JSON.stringify(result));
    """
    completed = subprocess.run(["node", "-e", harness], input=json.dumps({"bridge": bridge, "script": script}),
                               text=True, encoding="utf8", capture_output=True, timeout=10, check=True)
    return json.loads(completed.stdout)


class SourceImageByteBridgeTests(unittest.TestCase):
    def test_binary_decrypt_preserves_octets_and_string_decrypt_stays_text(self):
        result = replay_image_bridge("""
        const cipher = java.createSymmetricCrypto('AES/CBC/PKCS7Padding', '0123456789abcdef', 'fedcba9876543210');
        const original = [137,80,78,71,0,255,128,13,10,26,10,7];
        const encrypted = cipher.encrypt(original);
        const decrypted = cipher.decrypt(encrypted);
        const phrase = 'fixture 正文';
        ({isArray: Array.isArray(decrypted), bytes: decrypted, text: cipher.decryptStr(cipher.encryptStr(phrase))});
        """)
        self.assertTrue(result["isArray"])
        self.assertEqual(result["bytes"], [137, 80, 78, 71, 0, 255, 128, 13, 10, 26, 10, 7])
        self.assertEqual(result["text"], "fixture 正文")

    def test_concat_keeps_binary_head_tail_and_requested_length(self):
        result = replay_image_bridge("""
        const arrays = [new Uint8Array([137,80,78,71]), [13,10,26,10,0,255]];
        ({full: Array.from(Buffer.concat(arrays)), short: Array.from(Buffer.concat(arrays, 3)),
          padded: Array.from(Buffer.concat([[1,2]], 4))});
        """)
        self.assertEqual(result["full"], [137, 80, 78, 71, 13, 10, 26, 10, 0, 255])
        self.assertEqual(result["short"], [137, 80, 78])
        self.assertEqual(result["padded"], [1, 2, 0, 0])

    def test_concat_rejects_unbounded_allocations_before_creating_typed_array(self):
        result = replay_image_bridge("""
        [25165825, -1, 0.5, Infinity].map(size => {
          try { Buffer.concat([[1]], size); return false; }
          catch (error) { return error instanceof RangeError; }
        });
        """)
        self.assertEqual(result, [True, True, True, True])


if __name__ == "__main__":
    unittest.main()
