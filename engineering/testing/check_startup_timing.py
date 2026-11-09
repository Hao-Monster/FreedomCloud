#!/usr/bin/env python3
"""Check retained Core startup timing records without changing runtime state."""
import argparse
import collections
import glob
import re
import sys

parser = argparse.ArgumentParser()
parser.add_argument("paths", nargs="+", help="log paths or glob patterns")
parser.add_argument("--require-stage", action="append", default=[], help="require a completed stage in each Core group")
args = parser.parse_args()
files = sorted({p for pattern in args.paths for p in (glob.glob(pattern) or [pattern])})
groups = collections.defaultdict(list)
malformed = []
for path in files:
    try:
        with open(path, encoding="utf-8", errors="replace") as stream:
            for number, line in enumerate(stream, 1):
                if "[startup-timing]" not in line or "schema=2" not in line:
                    continue
                fields = dict(re.findall(r'\b(event|correlationId|pid|seq|stage|outcome)=([^\s"\\]+)', line))
                if not {"event", "correlationId", "pid", "seq", "stage"} <= fields.keys():
                    malformed.append((path, number))
                    continue
                if not fields["seq"].isdigit():
                    malformed.append((path, number))
                    continue
                if fields["event"] not in ("stage_start", "stage_end") or (fields["event"] == "stage_end" and "outcome" not in fields):
                    malformed.append((path, number))
                    continue
                groups[(fields["correlationId"], fields["pid"])].append(
                    (int(fields["seq"]), fields["stage"], fields["event"], fields.get("outcome", ""), path, number)
                )
    except OSError as error:
        print(f"read_error path={path!r} error={error}", file=sys.stderr)
        sys.exit(2)
if not groups:
    print("no schema=2 Core timing records found")
    sys.exit(1)
failed = bool(malformed)
if malformed:
    print(f"malformed={malformed}")
for (correlation, pid), records in sorted(groups.items()):
    numbers = collections.Counter(item[0] for item in records)
    low, high = min(numbers), max(numbers)
    ordered = sorted(numbers)
    missing = [(a + 1, b - 1) for a, b in zip(ordered, ordered[1:]) if b > a + 1]
    duplicates = sorted(n for n, count in numbers.items() if count > 1)
    pending = collections.Counter()
    for _, stage, event, _, _, _ in sorted(records):
        if event == "stage_start":
            pending[stage] += 1
        elif event == "stage_end" and pending[stage] > 0:
            pending[stage] -= 1
    incomplete = {stage: count for stage, count in pending.items() if count}
    completed = {stage for _, stage, event, _, _, _ in records if event == "stage_end"}
    missing_required = sorted(set(args.require_stage) - completed)
    failed |= bool(low != 1 or missing or duplicates or incomplete or missing_required)
    print(f"correlationId={correlation} pid={pid} count={len(records)} first={low} last={high} missing={missing} duplicates={duplicates} prefixMissing={low != 1}")
    print(f"unclosedStarts={incomplete}")
    print(f"missingRequiredStages={missing_required}")
    print("stages=" + ",".join(f"{n}:{stage}:{event}:{outcome}" for n, stage, event, outcome, _, _ in sorted(records)))
    print("note=sequence coverage does not prove that an unrecorded final event or another process log exists")
if failed:
    sys.exit(1)
