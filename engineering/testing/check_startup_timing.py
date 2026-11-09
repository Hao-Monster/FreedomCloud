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
parser.add_argument("--attempt", help="evaluate required stages and pairs for this tunAttempt only")
parser.add_argument("--require-success", action="append", default=[], help="require successful end outcome for this stage in the selected attempt")
parser.add_argument("--require-pair-each", action="append", default=[], help="require a matching stage pair in every nonzero TUN attempt")
parser.add_argument("--ui-log", action="append", default=[], help="UI log containing correlation_bind events")
parser.add_argument("--cold-helper-run", metavar="UI_RUN_ID", help="verify one successful Windows cold Helper/TUN startup through UI settle")
parser.add_argument("--agent-log", action="append", default=[])
parser.add_argument("--helper-log", action="append", default=[])
args = parser.parse_args()
def fields_of(line):
    return dict(re.findall(r"(?<![a-zA-Z0-9_])([a-zA-Z][a-zA-Z0-9_]*)=([^\s\"\\]+)", line))

def read_lines(paths):
    for pattern in paths:
        for path in sorted(glob.glob(pattern) or [pattern]):
            with open(path, encoding="utf-8", errors="replace") as stream:
                yield from stream

target = None
if args.cold_helper_run:
    try:
        ui = []
        for line in read_lines(args.ui_log):
            if "[startup-timing]" in line:
                event = fields_of(line)
                if event.get("uiRunId") == args.cold_helper_run:
                    ui.append(event)
        settled = [e for e in ui if e.get("stage") == "settle" and e.get("outcome") == "on"]
        if len(settled) != 1:
            raise ValueError("expected exactly one successful UI settle for this run")
        end = settled[0]
        pid, attempt, corr = end.get("corePid"), end.get("tunAttempt"), end.get("correlationId")
        if not (pid and pid.isdecimal() and int(pid) > 0 and attempt and attempt.isdecimal() and int(attempt) > 0 and corr):
            raise ValueError("settle lacks Core PID, attempt, or correlation")
        expected = {
            "preload": ("ready",), "authorize": ("success",),
            "componentsMatch": ("match",), "ensureBackend": ("replaced", "reused"),
            "setupConfig": ("ok",), "startListener": ("started",),
            "getTunStatus": ("on",), "settle": ("on",),
        }
        for stage, outcomes in expected.items():
            candidates = (e for e in ui if e.get("stage") == stage and e.get("outcome") in outcomes)
            if stage not in ("preload", "authorize"):
                candidates = (e for e in candidates if e.get("correlationId") == corr)
            if stage == "getTunStatus":
                candidates = (e for e in candidates if e.get("corePid") == pid and e.get("tunAttempt") == attempt)
            if not any(e.get("elapsedMs", "").isdecimal() for e in candidates):
                raise ValueError(f"missing UI stage {stage} with an accepted outcome and duration")
        if not any(e.get("event") == "correlation_bind" and e.get("correlationId") == corr for e in ui):
            raise ValueError("missing UI binding")
        helpers = [fields_of(l) for l in read_lines(args.helper_log) if "event=core_start.success " in l]
        ports = {e["port"] for e in helpers if e.get("corePid") == pid and e.get("correlationId") == corr and e.get("port","").isdecimal()}
        if not ports:
            raise ValueError("missing matching Helper spawn")
        requests = (fields_of(l) for l in read_lines(args.agent_log) if "event=core_start.request " in l)
        if not any(e.get("correlationId") == corr and e.get("port") in ports for e in requests):
            raise ValueError("missing matching Agent request")
        target = (corr, pid)
        args.attempt = attempt
        required = ["ReCreateTun","tun.lock_wait","sing_tun.New","sing_tun.device.wintun_create","sing_tun.device.session_start","sing_tun.device.ip_dns_config","sing_tun.device.route_config"]
        args.require_pair.extend(required)
        args.require_success.extend(required)
    except (OSError, ValueError) as error:
        print(f"cold_helper_evidence_incomplete: {error}", file=sys.stderr)
        sys.exit(1)
ui_bindings = collections.defaultdict(set)
for path in sorted({p for pattern in args.ui_log for p in (glob.glob(pattern) or [pattern])}):
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
                fields = dict(re.findall(r'\b(event|correlationId|pid|seq|stage|outcome|tunAttempt|elapsedMs|priorWriteFailures)=([^\s"\\]+)', line))
                if not {"event", "correlationId", "pid", "seq", "stage"} <= fields.keys():
                    malformed.append((path, number))
                    continue
                if fields.get("priorWriteFailures", "0") != "0" or not fields["seq"].isdigit():
                    malformed.append((path, number))
                    continue
                if fields["event"] not in ("stage_start", "stage_end") or (fields["event"] == "stage_end" and ("outcome" not in fields or not fields.get("elapsedMs", "").isascii() or not fields.get("elapsedMs", "").isdecimal())):
                    malformed.append((path, number))
                    continue
                groups[(fields["correlationId"], fields["pid"])].append(
                    (int(fields["seq"]), fields["stage"], fields["event"], fields.get("outcome", ""), path, number, fields.get("tunAttempt", "legacy"))
                )
    except OSError as error:
        print(f"read_error path={path!r} error={error}", file=sys.stderr)
        sys.exit(2)
if target:
    groups = {target: groups[target]} if target in groups else {}
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
    selected = [record for record in records if args.attempt is None or record[6] == args.attempt]
    pending = collections.Counter()
    orphan = collections.Counter()
    matched = set()
    matched_attempts = set()
    for _, stage, event, _, _, _, attempt in sorted(selected):
        key = (attempt, stage)
        if event == "stage_start":
            pending[key] += 1
        elif event == "stage_end" and pending[key] > 0:
            pending[key] -= 1
            matched.add(stage)
            matched_attempts.add(key)
        elif event == "stage_end" and stage in args.require_pair + args.require_pair_each:
            orphan[key] += 1
    incomplete = {str(key): count for key, count in pending.items() if count}
    completed = {stage for _, stage, event, _, _, _, _ in selected if event == "stage_end"}
    missing_required = sorted(set(args.require_stage) - completed)
    missing_pairs = sorted(set(args.require_pair) - matched)
    attempts = {attempt for _, _, _, _, _, _, attempt in selected if attempt not in ("legacy", "0")}
    missing_each = sorted((attempt, stage) for attempt in attempts for stage in args.require_pair_each if (attempt, stage) not in matched_attempts)
    success_outcomes = {"ok", "on", "started", "ready", "success"}
    unsuccessful = {stage: [outcome for _, name, event, outcome, _, _, _ in selected if name == stage and event == "stage_end"] for stage in args.require_success}
    unsuccessful = {stage: outcomes for stage, outcomes in unsuccessful.items() if not outcomes or any(outcome not in success_outcomes for outcome in outcomes)}
    missing_attempt = args.attempt is not None and not selected
    missing_ui = bool(args.ui_log and not ui_bindings.get(correlation))
    failed |= bool(low != 1 or missing or duplicates or incomplete or missing_required or missing_pairs or missing_each or orphan or missing_ui or missing_attempt or unsuccessful or (args.require_pair_each and not attempts))
    print(f"correlationId={correlation} pid={pid} count={len(records)} first={low} last={high} missing={missing} duplicates={duplicates} prefixMissing={low != 1}")
    print(f"unclosedStarts={incomplete}")
    print(f"missingRequiredStages={missing_required}")
    print(f"missingPairs={missing_pairs} orphanEnds={dict(orphan)}")
    print(f"missingEachAttemptPairs={missing_each}")
    print(f"selectedAttempt={args.attempt} missingAttempt={missing_attempt} unsuccessfulStages={unsuccessful}")
    if args.ui_log:
        print(f"uiRunIds={sorted(ui_bindings.get(correlation, set()))} missingUiBinding={missing_ui}")
    print("stages=" + ",".join(f"{n}:{stage}:{event}:{outcome}:attempt={attempt}" for n, stage, event, outcome, _, _, attempt in sorted(records)))
    print("note=sequence coverage does not prove that an unrecorded final event or another process log exists")
if failed:
    sys.exit(1)
