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
parser.add_argument("--require-pair", action="append", default=[], help="require matching start and end for this stage")
parser.add_argument("--ui-log", action="append", default=[], help="UI log containing correlation_bind events")
args = parser.parse_args()
ui_bindings = collections.defaultdict(set)
for path in args.ui_log:
    try:
        with open(path, encoding="utf-8", errors="replace") as stream:
            for line in stream:
                if "event=correlation_bind" not in line:
                    continue
                fields = dict(re.findall(r'\b(uiRunId|correlationId)=([A-Za-z0-9_-]+)', line))
                if {"uiRunId", "correlationId"} <= fields.keys():
                    ui_bindings[fields["correlationId"]].add(fields["uiRunId"])
    except OSError as error:
        print(f"ui_read_error path={path!r} error={error}", file=sys.stderr)
        sys.exit(2)
files = sorted({p for pattern in args.paths for p in (glob.glob(pattern) or [pattern])})
groups = collections.defaultdict(list)
malformed = []
for path in files:
    try:
        with open(path, encoding="utf-8", errors="replace") as stream:
            for number, line in enumerate(stream, 1):
                if "[startup-timing]" not in line or "schema=2" not in line:
                    continue
                fields = dict(re.findall(r'\b(event|correlationId|pid|seq|stage|outcome|tunAttempt)=([^\s"\\]+)', line))
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
                    (int(fields["seq"]), fields["stage"], fields["event"], fields.get("outcome", ""), path, number, fields.get("tunAttempt", "legacy"))
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
    orphan = collections.Counter()
    matched = set()
    for _, stage, event, _, _, _, attempt in sorted(records):
        key = (attempt, stage)
        if event == "stage_start":
            pending[key] += 1
        elif event == "stage_end" and pending[key] > 0:
            pending[key] -= 1
            matched.add(stage)
        elif event == "stage_end" and stage in args.require_pair:
            orphan[key] += 1
    incomplete = {str(key): count for key, count in pending.items() if count}
    completed = {stage for _, stage, event, _, _, _, _ in records if event == "stage_end"}
    missing_required = sorted(set(args.require_stage) - completed)
    missing_pairs = sorted(set(args.require_pair) - matched)
    missing_ui = bool(args.ui_log and not ui_bindings.get(correlation))
    failed |= bool(low != 1 or missing or duplicates or incomplete or missing_required or missing_pairs or orphan or missing_ui)
    print(f"correlationId={correlation} pid={pid} count={len(records)} first={low} last={high} missing={missing} duplicates={duplicates} prefixMissing={low != 1}")
    print(f"unclosedStarts={incomplete}")
    print(f"missingRequiredStages={missing_required}")
    print(f"missingPairs={missing_pairs} orphanEnds={dict(orphan)}")
    if args.ui_log:
        print(f"uiRunIds={sorted(ui_bindings.get(correlation, set()))} missingUiBinding={missing_ui}")
    print("stages=" + ",".join(f"{n}:{stage}:{event}:{outcome}:attempt={attempt}" for n, stage, event, outcome, _, _, attempt in sorted(records)))
    print("note=sequence coverage does not prove that an unrecorded final event or another process log exists")
if failed:
    sys.exit(1)
