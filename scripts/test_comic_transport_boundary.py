"""Keep advertised and streamed comic byte limits enforced before image decode.
Usage: python -m unittest discover -s scripts -p test_comic_transport_boundary.py
"""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[1]
class ComicTransportBoundaryTests(unittest.TestCase):
    def test_comic_header_limit_does_not_depend_only_on_expected_length(self):
        source = (ROOT / "SourceReadSwift/Shared/DesignSystem/ComicImageTransport.swift").read_text(encoding="utf8")
        self.assertTrue('value(forHTTPHeaderField: "Content-Length")' in source,
                        "Reject an advertised oversized response even if expectedContentLength is unknown")

    def test_application_failure_commits_before_transport_cancellation(self):
        source = (ROOT / "SourceReadSwift/Shared/DesignSystem/ComicImageTransport.swift").read_text(encoding="utf8")
        response = source.split('if let failure = ComicImageResponsePolicy.failure', 1)[1].split('} else {', 1)[0]
        self.assertLess(response.index('complete(dataTask, result: .failure(failure))'),
                        response.index('completionHandler(.cancel)'),
                        "A cancellation callback must not win over the byte-limit result")
        chunk = source.split('guard chunk.count <= limit - transfer.bytes.count else {', 1)[1].split('return', 1)[0]
        self.assertLess(chunk.index('complete(dataTask, result: .failure(.tooLarge))'),
                        chunk.index('dataTask.cancel()'))

    def test_raw_configuration_and_task_expected_length_reach_the_receiver(self):
        source = (ROOT / "SourceReadSwift/Shared/DesignSystem/ComicImageTransport.swift").read_text(encoding="utf8")
        self.assertTrue('transportConfiguration.protocolClasses = configuration.protocolClasses' in source)
        self.assertTrue('expectedBodyBytes: dataTask.countOfBytesExpectedToReceive' in source)
        loader = (ROOT / "SourceReadSwift/Shared/DesignSystem/RemoteImageLoader.swift").read_text(encoding="utf8")
        self.assertTrue('configuration: URLSessionConfiguration? = nil' in loader)
        tests = (ROOT / "SourceReadSwiftTests/RemoteComicImageTests.swift").read_text(encoding="utf8")
        self.assertNotIn('RemoteImageLoader(session: session)', tests)
