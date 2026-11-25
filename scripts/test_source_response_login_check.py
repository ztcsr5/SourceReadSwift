"""Replay the production response-hook adapter with offline JavaScript fixtures."""
from pathlib import Path
import re
import unittest

from test_source_android_bridges import replay_android_bridge


ROOT = Path(__file__).resolve().parents[1]


def replay_response_hook(script: str) -> dict:
    source = (ROOT / 'SourceReadSwift/Core/Engine/SourceResponseLoginCheck.swift').read_text(encoding='utf8')
    factory = re.search(r'private static let bridgeScript = #"""\n(.*?)\n    """#', source, re.S)
    if factory is None:
        raise AssertionError('Production response-hook adapter was not found')
    return replay_android_bridge('var createHook = ' + factory.group(1) + ';\n' + script)


class SourceResponseLoginCheckBridgeTests(unittest.TestCase):
    def test_original_status_url_body_and_headers_remain_callable(self):
        result = replay_response_hook("""
        java.getStrResponse = function() { return 'outside hook'; };
        var session = createHook({url: 'https://fixture.local/search', statusCode: 201,
          headers: {'X-Fixture': 'original'}, body: 'original 正文', bytes: []}, function() {});
        var original = session.response;
        var answer = {code: original.code(), url: original.url(), body: String(original.body()),
          header: original.header('x-fixture'), extracted: session.extract(original)};
        session.restore();
        answer.after = java.getStrResponse();
        answer;
        """)
        self.assertEqual(result, {'code': 201, 'url': 'https://fixture.local/search',
            'body': 'original 正文', 'header': 'original', 'after': 'outside hook',
            'extracted': {'url': 'https://fixture.local/search', 'statusCode': 201,
                'headers': {'X-Fixture': 'original'}, 'body': 'original 正文'}})

    def test_replacement_uses_str_response_body_instead_of_response_description(self):
        result = replay_response_hook("""
        java.getStrResponse = function() {};
        var session = createHook({url: 'https://fixture.local/search', statusCode: 200,
          headers: {}, body: 'Unchanged'}, function() {});
        var completion = (function(result) {
          return eval("Packages.io.legado.app.help.http.StrResponse(result.url(), result.body().replace('Unchanged', 'Checked'))");
        })(session.response);
        session.extract(completion);
        """)
        self.assertEqual(result, {'url': 'https://fixture.local/search', 'statusCode': 200,
            'headers': {}, 'body': 'Checked'})

    def test_only_null_arguments_resend_and_restore_returns_the_original_function(self):
        result = replay_response_hook("""
        var calls = [], resends = 0;
        var previous = java.getStrResponse = function(url, rule) { calls.push([url, rule]); return 'delegated'; };
        var session = createHook({url: 'https://fixture.local/search', statusCode: 401,
          headers: {}, body: 'login'}, function() { resends++; return {url: 'https://fixture.local/search',
            statusCode: 202, headers: {'X-Session': 'renewed'}, body: 'Checked'}; });
        var response = java.getStrResponse(null, null);
        var answer = {code: response.code(), header: response.header('x-session'),
          body: String(response.body()), delegated: java.getStrResponse('/other', '$.name'), calls, resends};
        session.restore();
        answer.restored = java.getStrResponse === previous;
        answer;
        """)
        self.assertEqual(result, {'code': 202, 'header': 'renewed', 'body': 'Checked',
            'delegated': 'delegated', 'calls': [['/other', '$.name']], 'resends': 1, 'restored': True})

    def test_resend_failure_throws_and_restore_survives_the_hook_error(self):
        result = replay_response_hook("""
        var previous = java.getStrResponse = function() {};
        var session = createHook({url: 'https://fixture.local/search', statusCode: 200, headers: {}, body: 'original'},
          function() { return {failure: 'cancelled response'}; });
        var error = '';
        try { java.getStrResponse(null, null); } catch (failure) { error = failure.message; }
        session.restore();
        ({error, restored: java.getStrResponse === previous});
        """)
        self.assertEqual(result, {'error': 'cancelled response', 'restored': True})

    def test_non_response_completion_preserves_the_original_and_null_body_is_empty(self):
        result = replay_response_hook("""
        java.getStrResponse = function() {};
        var session = createHook({url: 'https://fixture.local/search', statusCode: 200, headers: {}, body: 'original'}, function() {});
        ({boolean: session.extract(true), missing: session.extract(undefined),
          nullable: session.extract(Packages.io.legado.app.help.http.StrResponse('https://fixture.local/search', null))});
        """)
        self.assertEqual(result, {'boolean': None, 'missing': None, 'nullable': {
            'url': 'https://fixture.local/search', 'statusCode': 200, 'headers': {}, 'body': ''}})


if __name__ == '__main__':
    unittest.main()
