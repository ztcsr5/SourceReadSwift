"""Require real interactive book-return completion AND cancellation in simulator logs.

Usage: python -B -X utf8 scripts/verify_book_passage_log.py desk-passage.log --ui-log desk-ui.log
No frame polling, user book identity or source URL is recorded.
"""
import argparse
from pathlib import Path
import re

def inspect_system_surface(text):
    """Confirm the actual desk return skips its synthetic paper carrier."""
    active = False
    is_system_surface = False
    outcomes = set()
    for line in text.splitlines():
        if match := re.search(r"\bBEGIN interactive=([01])\b", line):
            active = match[1] == "1"
            is_system_surface = False
        elif active and re.search(r"\bSURFACE system-book\b", line):
            is_system_surface = True
        elif match := re.search(r"\bEND cancelled=([01])\b", line):
            if active and is_system_surface:
                outcomes.add(match[1])
            active = False
    if outcomes != {"0", "1"}:
        raise ValueError("Expected both interactive desk returns to leave the surface to UIKit")
    return len(outcomes)

def inspect_passages(text, ui_text=""):
    active = None
    cancelled = 0
    completed = 0
    for line in text.splitlines():
        event = re.search(r"\b(BEGIN interactive|END cancelled)=([01])\b", line)
        if event is None:
            continue
        name, flag = event.groups()
        if name.startswith("BEGIN"):
            if active is not None:
                raise ValueError("A second book return began before the first completed")
            active = flag == "1"
        elif active is not None:
            if active:
                cancelled += flag == "1"
                completed += flag == "0"
            active = None
    if active is not None:
        raise ValueError("Book return has no completion event")
    # Native zoom may reverse before committing a navigation pop, so there is
    # no transitionCoordinator cancellation callback. Require BOTH a real
    # native recognizer's motion and the unchanged real-reader UI assertions.
    case = re.escape("Test Case '-[SourceReadSwiftUITests.FloatingReadingDeskUITests testReaderSystemReturnCanCancelWithoutLosingItsSavedParagraph]'")
    passed = re.search(case + r" started\.(.*?)" + case + r" passed \(", ui_text, re.S)
    if not cancelled and passed:
        motion = re.search(r"BOOK_NATIVE_CANCEL_VERIFIED motion_before=(\d+) motion_after=(\d+)", passed.group(1))
        if motion:
            before, after = map(int, motion.groups())
            counts = {int(count) for count in re.findall(r"PAN_MOVED native=1 count=(\d+)", text)}
            cancelled = int(after > before and after in counts)
    if not cancelled or not completed:
        raise ValueError(f"Expected native interactive cancel and finish; actual cancel={cancelled}, finish={completed}")
    return {"interactive_cancel": cancelled, "interactive_finish": completed}

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", type=Path)
    parser.add_argument("--ui-log", type=Path)
    parser.add_argument("--require-system-surface", action="store_true")
    args = parser.parse_args()
    passage_log = args.log.read_text(encoding="utf8", errors="replace")
    print(inspect_passages(passage_log,
                          args.ui_log.read_text(encoding="utf8", errors="replace") if args.ui_log else ""))
    if args.require_system_surface:
        print({"system_surface_outcomes": inspect_system_surface(passage_log)})
