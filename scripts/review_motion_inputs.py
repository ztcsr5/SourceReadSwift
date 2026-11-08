"""Replay static motion-review evidence without running any attached code.

Usage: python -X utf8 scripts/review_motion_inputs.py --evidence-root <FOLDER>
Requires only the Python standard library and the previously inspected evidence.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import xml.etree.ElementTree as ET


def require_fact(is_true: bool, name: str) -> None:
    """Fail when the inspected source no longer supports a recorded finding."""
    if not is_true:
        raise ValueError(f"Static review mismatch: {name}; expected recorded source fact, found changed input")


def verify_input_hashes(evidence_root: Path) -> int:
    """Verify the original video, archive, documents and pasted source by SHA256."""
    manifest = json.loads((evidence_root / "input-manifest.json").read_text(encoding="utf8"))
    for item in manifest:
        path = Path(item["path"])
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        require_fact(digest == item["sha256"], f"input hash for {path.name}")
    inventory = json.loads((evidence_root / "rex-static/INVENTORY.json").read_text(encoding="utf8"))
    require_fact(hashlib.sha256(Path(inventory["path"]).read_bytes()).hexdigest() == inventory["sha256"], "authorized Rex IPA hash")
    return len(manifest) + 1


def verify_project_references(project: Path) -> dict[str, int]:
    """Check source, asset and scheme references; never execute a build phase."""
    pbx = (project / "ZhijianMotionLab.xcodeproj/project.pbxproj").read_text(encoding="utf8")
    swift_paths = list((project / "ZhijianMotionLab").glob("*.swift"))
    require_fact(len(swift_paths) == 11, "MotionLab eleven Swift files")
    require_fact(all(path.name in pbx for path in swift_paths), "Swift project references")
    require_fact("PBXShellScriptBuildPhase" not in pbx, "no attached shell build phase")
    asset_paths = list((project / "ZhijianMotionLab/Assets.xcassets").rglob("Contents.json"))
    for path in asset_paths:
        manifest = json.loads(path.read_text(encoding="utf8"))
        for image in manifest.get("images", []):
            if filename := image.get("filename"):
                require_fact((path.parent / filename).is_file(), f"asset file {filename}")
    scheme = ET.parse(project / "ZhijianMotionLab.xcodeproj/xcshareddata/xcschemes/ZhijianMotionLab.xcscheme")
    for reference in scheme.findall(".//BuildableReference"):
        require_fact(reference.attrib["BlueprintIdentifier"] in pbx, "scheme target reference")
    return {"swift_references": len(swift_paths), "asset_manifests": len(asset_paths)}


def verify_source_findings(evidence_root: Path) -> int:
    """Reproduce source facts, not unexecuted Swift runtime or GPU claims."""
    prototype = (evidence_root / "inputs/GeminiPrototype.swift").read_text(encoding="utf8")
    lab = evidence_root / "inputs/ZhijianMotionLab/ZhijianMotionLab"
    app = (lab / "ZhijianMotionLabApp.swift").read_text(encoding="utf8")
    models = (lab / "Models.swift").read_text(encoding="utf8")
    home = (lab / "HomeView.swift").read_text(encoding="utf8")
    onboarding = (lab / "OnboardingView.swift").read_text(encoding="utf8")
    facts = [
        (".preferredColorScheme(.dark)" in prototype, "Gemini forces dark"),
        ("sources[i].varlatencyMs = Int.random(in: 28...135)" in prototype, "Gemini random latency, not real checking"),
        (prototype.count("http://192.168.1.88:8080") >= 2, "Gemini constant LAN address"),
        (not re.search(r"UserDefaults|@AppStorage|FileManager|JSONEncoder|JSONDecoder", prototype), "Gemini has no persistent store"),
        ("for i in 1...min(3, tickets.count)" in prototype, "Gemini empty ticket closed-range failure path"),
        (".preferredColorScheme(.light)" in app, "MotionLab forces light"),
        ("Double(safeIndex) + 0.4" in models, "MotionLab arbitrary chapter fraction"),
        (not any("scenePhase" in path.read_text(encoding="utf8") for path in lab.glob("*.swift")), "MotionLab lacks foreground session segmentation"),
        (".blur(radius: library.immersiveBackground ? 45 : 100)" in home, "MotionLab off switch retains blur"),
        ("matchedGeometryEffect" not in onboarding and ".id(page)" in onboarding, "MotionLab onboarding is not shared-element morphing"),
    ]
    for is_true, name in facts:
        require_fact(is_true, name)
    production = Path(__file__).resolve().parents[1] / "SourceReadSwift/Core/Models/ReadingStatsSummary.swift"
    summary = production.read_text(encoding="utf8")
    require_fact("return sum + (book.totalReadingSeconds ?? 0)" in summary, "production day attribution uses lifetime totals")
    # Counterexample of the inspected formula, not a Swift execution result.
    prior_seconds, today_seconds = 3600, 60
    require_fact(prior_seconds + today_seconds != today_seconds, "lifetime total cannot represent today's one-minute session")
    return len(facts) + 1


def main() -> None:
    """Replay only static evidence and print an explicit native-build limitation."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--evidence-root", type=Path, required=True)
    options = parser.parse_args()
    evidence_root = options.evidence_root.resolve(strict=True)
    input_count = verify_input_hashes(evidence_root)
    project = verify_project_references(evidence_root / "inputs/ZhijianMotionLab")
    finding_count = verify_source_findings(evidence_root)
    print(json.dumps({"status": "PASS static evidence replay", "input_hashes": input_count,
                      "project": project, "source_facts_and_counterexamples": finding_count,
                      "native_build": "NOT RUN: no Apple SDK; not runtime/animation/FPS acceptance"}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
