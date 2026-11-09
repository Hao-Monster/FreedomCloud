import pathlib
import subprocess
import sys
import tempfile
import unittest

CHECK = pathlib.Path(__file__).with_name("check_startup_timing.py")


class TimingCheckTest(unittest.TestCase):
    def check(self, lines, *options):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "core.log"
            path.write_text("\n".join(lines), encoding="utf-8")
            return subprocess.run([sys.executable, str(CHECK), *options, str(path)], capture_output=True, text=True)

    def line(self, seq, event, stage="call"):
        return f"[startup-timing] schema=2 event={event} correlationId=test pid=1 seq={seq} stage={stage} outcome=ok"

    def test_paired_start_and_end(self):
        self.assertEqual(self.check([self.line(1, "stage_start"), self.line(2, "stage_end")]).returncode, 0)

    def test_missing_duplicate_and_unclosed_fail(self):
        for lines in ([self.line(1, "stage_start")],
                      [self.line(1, "stage_end"), self.line(3, "stage_end")],
                      [self.line(1, "stage_end"), self.line(1, "stage_end")]):
            with self.subTest(lines=lines):
                self.assertEqual(self.check(lines).returncode, 1)

    def test_malformed_and_required_stage_fail(self):
        self.assertEqual(self.check([self.line(1, "stage_end"), "[startup-timing] schema=2 event=broken"]).returncode, 1)
        self.assertEqual(self.check([self.line(1, "stage_end")], "--require-stage", "missing").returncode, 1)
        self.assertEqual(self.check([self.line(1, "stage_end")], "--require-stage", "call").returncode, 0)

    def test_required_pair_rejects_orphan_end_and_different_attempt(self):
        self.assertEqual(self.check([self.line(1, "stage_end")], "--require-pair", "call").returncode, 1)
        lines = [self.line(1, "stage_start") + " tunAttempt=1", self.line(2, "stage_end") + " tunAttempt=2"]
        self.assertEqual(self.check(lines, "--require-pair", "call").returncode, 1)
        lines[1] = self.line(2, "stage_end") + " tunAttempt=1"
        self.assertEqual(self.check(lines, "--require-pair", "call").returncode, 0)

    def test_ui_binding_must_match_correlation(self):
        with tempfile.TemporaryDirectory() as directory:
            ui = pathlib.Path(directory) / "ui.log"
            ui.write_text("[startup-timing] event=correlation_bind uiRunId=ui1 correlationId=wrong\n", encoding="utf-8")
            self.assertEqual(self.check([self.line(1, "stage_end")], "--ui-log", str(ui)).returncode, 1)
            ui.write_text("[startup-timing] event=correlation_bind uiRunId=ui1 correlationId=test\n", encoding="utf-8")
            self.assertEqual(self.check([self.line(1, "stage_end")], "--ui-log", str(ui)).returncode, 0)

    def test_requirements_and_outcome_apply_to_selected_attempt(self):
        lines = [self.line(1, "stage_start") + " tunAttempt=1",
                 self.line(2, "stage_end").replace("outcome=ok", "outcome=error") + " tunAttempt=1",
                 self.line(3, "stage_start") + " tunAttempt=2",
                 self.line(4, "stage_end") + " tunAttempt=2"]
        self.assertEqual(self.check(lines, "--attempt", "1", "--require-pair", "call", "--require-success", "call").returncode, 1)
        self.assertEqual(self.check(lines, "--attempt", "2", "--require-pair", "call", "--require-success", "call").returncode, 0)
        self.assertEqual(self.check(lines, "--attempt", "3", "--require-stage", "call").returncode, 1)

    def test_required_pair_for_each_attempt(self):
        lines = [self.line(1, "stage_start") + " tunAttempt=1", self.line(2, "stage_end") + " tunAttempt=1",
                 self.line(3, "stage_start", "other") + " tunAttempt=2", self.line(4, "stage_end", "other") + " tunAttempt=2"]
        self.assertEqual(self.check(lines, "--require-pair-each", "call").returncode, 1)
        self.assertEqual(self.check(lines[:2], "--require-pair-each", "call").returncode, 0)


if __name__ == "__main__":
    unittest.main()
