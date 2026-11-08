"""Record the independently reviewed CI evidence without touching reader code."""
import json
from pathlib import Path

path = Path(__file__).with_name("semantic-validation.json")
data = json.loads(path.read_text(encoding="utf-8"))
data["source_snapshot"] = "Re-reviewed controller at eda34a5; paginator and builder baseline unchanged from 586a5bd at this review. Native diagnostics read from job-124364393951.log."
data["runtime_validation"] = "This reviewer cannot execute UIKit locally. Native CI evidence is explicitly sourced to saved logs; it is not real-device proof."
for item in data["validation_findings"]:
    if item["id"] == "queued_end_consumes_later_gesture":
        item["status"] = "SOURCE FIX VERIFIED; native independent queue tests passed in job-124364393951.log:9319-9332"
    elif item["id"] == "queued_commit_reenters_swiftui_update":
        item["status"] = "SOURCE FIX VERIFIED at eda34a5; direct-controller queue and cancellation native tests passed"
        item["source_location"] = "eda34a5:167-177"
        item["claim"] = "Queued commits are now deferred out of representable update with animation generation, waiting identity, and installed identity guards. Native testDismantleCancelsDeferredQueuedCommit passed at log lines 9323-9324."
    elif item["id"] == "onboarding_actual_surface_overflow":
        item["status"] = "NATIVE FAILURE AND METRIC MISMATCH OBSERVED; explicit minimum line-height correction proposed, not yet tested"
        item["evidence"] = "job-124364393951.log:9268-9315"
        item["claim"] = "Identical glyph line ranges and widths, insets, and fontLeading settings produce standalone maxY691.203125 versus actual maxY756.9453125. Pure CJK standalone line height is 28 (20+8), but actual UITextView is 31.8671875 (UIFont.lineHeight23.8671875+8). This disproves paragraph-tail wrapping as the cause for this fixture. Explicit minimumLineHeight=corresponding body/title UIFont.lineHeight is the smallest proposed common contract; do not set maximumLineHeight, which could clip taller fallback glyphs."
for item in data["investigation_hypotheses"]:
    if item["id"] == "paragraph_tail_reflow":
        item["status"] = "EXCLUDED AS CAUSE OF ONBOARDING FAILURE by identical native glyph line ranges; general edge-case hypothesis only"
        item["confidence_score"] = 0.2
data["validation_findings"].append({
    "id": "rtl_suffix_not_paginated",
    "severity": "P1",
    "status": "NATIVE CONSERVATION FAILURE OBSERVED; repair pending",
    "evidence": "job-124364393951.log:9385-9386",
    "source_file": "SourceReadSwift/Features/Reader/ReaderTextPagePaginator.swift",
    "source_location": "43-49,58-64",
    "claim": "Mixed Arabic/CJK repeated paragraph loses its suffix and a following final paragraph disappears. End-of-document must be checked in UTF16 character coverage rather than a glyph count frozen before container layout. Glyph-count change is a plausible mechanism, not directly proven by these logs.",
    "reproduction": "ReaderRecovery119Tests.testLongInlineTitleAndEmbeddedNewlinesConserveSourceRanges: long inline title, empty paragraphs, embedded newlines, Arabic/CJK/Latin repeated 60 times, then final Chinese paragraph.",
    "recommended_minimal_repair": "Ensure glyphs for full document after attaching a container; iterate while characterEnd<document.length; after each container layout derive characterRange and advance by NSMaxRange; detect no character progress and test contiguous coverage. Keep UTF16 offsets and character conservation assertions. Do not call ensureLayout(fullDocument) before enough containers exist as a completion proof."
})
path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print(f"Updated {len(data['nodes'])} nodes, {len(data['edges'])} edges, {len(data['validation_findings'])} findings")
