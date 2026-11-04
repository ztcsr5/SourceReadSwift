"""Require real interactive book-return completion AND cancellation in simulator logs.

Usage: python -B -X utf8 scripts/verify_book_passage_log.py desk-passage.log
No frame polling, user book identity or source URL is recorded.
"""
import argparse
from pathlib import Path
import re

def inspect_passages(text):
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
    if not cancelled or not completed:
        raise ValueError(f"Expected native interactive cancel and finish; actual cancel={cancelled}, finish={completed}")
    return {"interactive_cancel": cancelled, "interactive_finish": completed}

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", type=Path)
    args = parser.parse_args()
    print(inspect_passages(args.log.read_text(encoding="utf8", errors="replace")))
