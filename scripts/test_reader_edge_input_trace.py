"""Exercise the regression-only reader touch observer against synthetic document events."""
import json
from pathlib import Path
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[1]
TRACE = ROOT / "SourceReadSwift/Features/Reader/Navigation/ReaderEdgeInputTrace.swift"


class ReaderEdgeInputTraceTests(unittest.TestCase):
    def test_edge_trace_is_passive_and_reports_displacement_once(self):
        script = TRACE.read_text(encoding="utf-8").split('"""', 2)[1]
        program = """
        const listeners = new Map(), received = [];
        const window = {
            __reader: {state: {revision: 'fixture'}},
            webkit: {messageHandlers: {reader: {postMessage: value => received.push(value)}}},
            addEventListener(type, listen, options) { listeners.set(type, {listen, options}); }
        };
        const send = (type, clientX, clientY, pointerId = 1) => listeners.get(type).listen({
            pointerType: 'touch', isPrimary: true, pointerId, clientX, clientY,
            preventDefault() { throw new Error('probe must never prevent input'); }
        });
        """ + script + """
        send('pointerdown', 55, 100); send('pointerup', 100, 100);
        send('pointerdown', 3, 100); send('pointermove', 70, 100, 2);
        send('pointermove', 15, 100); send('pointermove', 29, 101);
        send('pointercancel', 28, 101); send('pointerup', 29, 101);
        console.log(JSON.stringify({received, passive: [...listeners.values()].every(v => v.options.passive),
            installed: window.__sourceReadEdgeTraceInstalled}));
        """
        result = subprocess.run(["node", "-e", program], cwd=ROOT, capture_output=True, check=True,
                                encoding="utf-8", timeout=10)
        self.assertEqual(json.loads(result.stdout), {
            "passive": True,
            "installed": True,
            "received": [
                {"type": "edge-input", "revision": "fixture", "sequence": 1, "phase": "began", "dx": 0},
                {"type": "edge-input", "revision": "fixture", "sequence": 1, "phase": "cancelled", "dx": 26},
            ],
        })
