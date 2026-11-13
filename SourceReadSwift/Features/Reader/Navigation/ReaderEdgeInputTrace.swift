#if DEBUG
import Foundation
import WebKit

/// Reports whether the prose received an edge touch without adding a UIKit recognizer.
enum ReaderEdgeInputTrace {
    static let isRequested = ProcessInfo.processInfo.arguments.contains("--reader-edge-input-trace")

    static func install(in controller: WKUserContentController) {
        controller.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
    }

    private static let script = """
        (() => {
            const options = {capture: true, passive: true};
            const edgeWidth = 44;
            let nextSequence = 0;
            let touch = null;

            function report(phase) {
                const revision = window.__reader?.state?.revision;
                if (revision) window.webkit.messageHandlers.reader.postMessage({
                    type: 'edge-input', revision, sequence: touch.sequence, phase, dx: Math.round(touch.dx)
                });
            }

            function recordDisplacement(event) {
                const dx = event.clientX - touch.x;
                if (Math.abs(dx) > Math.abs(touch.dx)) touch.dx = dx;
            }

            window.addEventListener('pointerdown', event => {
                if (!event.isPrimary || event.pointerType !== 'touch' || event.clientX > edgeWidth) return;
                touch = {id: event.pointerId, x: event.clientX, sequence: ++nextSequence, dx: 0};
                report('began');
            }, options);
            window.addEventListener('pointermove', event => {
                if (touch?.id === event.pointerId) recordDisplacement(event);
            }, options);
            window.addEventListener('pointerup', event => {
                if (touch?.id !== event.pointerId) return;
                recordDisplacement(event);
                report('ended');
                touch = null;
            }, options);
            window.addEventListener('pointercancel', event => {
                if (touch?.id !== event.pointerId) return;
                report('cancelled');
                touch = null;
            }, options);
            window.__sourceReadEdgeTraceInstalled = true;
        })();
        """
}
#endif
