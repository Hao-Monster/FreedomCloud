import pathlib
import subprocess
import sys
import tempfile
import unittest

CHECK = pathlib.Path(__file__).with_name("check_startup_timing.py")


class TimingCheckTest(unittest.TestCase):
    def check(self, lines):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "core.log"
            path.write_text("\n".join(lines), encoding="utf-8")
            return subprocess.run([sys.executable, str(CHECK), str(path)], capture_output=True, text=True)

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


if __name__ == "__main__":
    unittest.main()
