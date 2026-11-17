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
        return f"[startup-timing] schema=2 event={event} correlationId=test pid=1 seq={seq} stage={stage} elapsedMs=1 outcome=ok"

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

    def test_output_loss_is_incomplete_even_with_a_contiguous_prefix(self):
        for counter in ("droppedTimingLines", "priorWriteFailures"):
            self.assertEqual(self.check([self.line(1, "stage_end") + f" {counter}=2"]).returncode, 1)

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


    def test_cold_helper_chain(self):
        with tempfile.TemporaryDirectory() as d:
            ui, agent, helper = [pathlib.Path(d) / n for n in ("ui", "agent", "helper")]
            ui_prefix = "[startup-timing] uiRunId=u correlationId=test "
            ui_lines = [ui_prefix+"event=correlation_bind"]
            for stage, outcome in [("preload","ready"),("authorize","success"),("componentsMatch","match"),("ensureBackend","replaced"),("setupConfig","ok"),("startListener","started"),("getTunStatus","on"),("settle","on")]:
                ui_lines.append(ui_prefix+f"stage={stage} outcome={outcome} elapsedMs=1 corePid=1 tunAttempt=9")
            agent.write_text("event=core_start.request correlationId=test port=1234")
            helper.write_text("event=core_start.success corePid=1 correlationId=test port=1234")
            ui.write_text("\n".join(ui_lines))
            options = ["--cold-helper-run","u","--ui-log",str(ui),"--agent-log",str(agent),"--helper-log",str(helper)]
            core = []
            for stage in ("ReCreateTun","tun.lock_wait","sing_tun.New","sing_tun.device.wintun_create","sing_tun.device.session_start","sing_tun.device.ip_dns_config","sing_tun.device.route_config"):
                for event in ("stage_start","stage_end"):
                    core.append(self.line(len(core)+1,event,stage)+" tunAttempt=9")
            self.assertEqual(self.check(core,*options).returncode,0)
            for bad in ([], [core[0]], [line.replace("elapsedMs=1","") for line in core]):
                self.assertNotEqual(self.check(bad,*options).returncode,0)
            ui.write_text("\n".join(ui_lines[:-1]))
            self.assertEqual(self.check(core,*options).returncode,1)
            ui.write_text("\n".join(ui_lines))
            for path in (agent, helper):
                saved=path.read_text()
                path.write_text("")
                self.assertEqual(self.check(core,*options).returncode,1)
                path.write_text(saved)

    def test_cold_helper_chain_accepts_uac_free_preload_and_authorize_none(self):
        with tempfile.TemporaryDirectory() as d:
            ui, agent, helper = [pathlib.Path(d) / n for n in ("ui", "agent", "helper")]
            agent.write_text("event=core_start.request correlationId=test port=1234")
            helper.write_text("event=core_start.success corePid=1 correlationId=test port=1234")
            core = []
            for stage in ("ReCreateTun","tun.lock_wait","sing_tun.New","sing_tun.device.wintun_create","sing_tun.device.session_start","sing_tun.device.ip_dns_config","sing_tun.device.route_config"):
                core.append(self.line(len(core)+1,"stage_start",stage)+" tunAttempt=9")
                core.append(self.line(len(core)+1,"stage_end",stage).replace("elapsedMs=1", "elapsedMs=12")+" tunAttempt=9")
            core.append(self.line(len(core)+1,"stage_start","tun.wintun_create_adapter")+" tunAttempt=9")
            core.append(self.line(len(core)+1,"stage_end","tun.wintun_create_adapter").replace("elapsedMs=1", "elapsedMs=10")+" tunAttempt=9")

            # Path A: UAC-free cold start where preload bound correlationId directly
            # and prepareWindowsTunBackend short-circuited without authorize/ensureBackend.
            uac_free_ui = [
                "[startup-timing] schema=2 source=ui event=correlation_bind uiRunId=u correlationId=test",
                "[startup-timing] stage=e2e.first_frame elapsedMs=180 outcome=rendered schema=2 source=ui uiRunId=u",
                "[startup-timing] stage=preload elapsedMs=95 outcome=ready schema=2 source=ui uiRunId=u correlationId=test",
                "[startup-timing] stage=componentsMatch elapsedMs=4 outcome=match schema=2 source=ui uiRunId=u correlationId=test",
                "[startup-timing] stage=setupConfig elapsedMs=35 outcome=ok schema=2 source=ui uiRunId=u correlationId=test",
                "[startup-timing] stage=startListener elapsedMs=55 outcome=started schema=2 source=ui uiRunId=u correlationId=test",
                "[startup-timing] stage=getTunStatus elapsedMs=2 outcome=on corePid=1 tunAttempt=9 detail=state=on revision=2 schema=2 source=ui uiRunId=u correlationId=test",
                "[startup-timing] stage=settle elapsedMs=3 outcome=on attempt=1 corePid=1 tunAttempt=9 schema=2 source=ui uiRunId=u correlationId=test",
                "[startup-timing] stage=e2e.tunnel_ready elapsedMs=390 outcome=on corePid=1 tunAttempt=9 detail=mode=tun schema=2 source=ui uiRunId=u correlationId=test",
            ]
            ui.write_text("\n".join(uac_free_ui), encoding="utf-8")
            options = ["--cold-helper-run","u","--ui-log",str(ui),"--agent-log",str(agent),"--helper-log",str(helper)]
            res = self.check(core, *options)
            self.assertEqual(res.returncode, 0, msg=res.stdout + res.stderr)
            self.assertIn("metrics.e2e uiRunId=u firstFrameMs=180 tunnelReadyMs=390", res.stdout)
            self.assertIn("metrics.core ", res.stdout)
            self.assertIn("metrics.top_leaf_calls ", res.stdout)

            # Passing UI schema=2 lines in positional paths (e.g. logs/*.log) must not fail as malformed Core records.
            combined = self.check(uac_free_ui + core)
            self.assertEqual(combined.returncode, 0, msg=combined.stdout + combined.stderr)

            # Deferred preload (correlation_bind AFTER preload) without authorize/ensureBackend must still fail!
            bad_deferred_ui = [
                "[startup-timing] stage=preload elapsedMs=5 outcome=ready schema=2 source=ui uiRunId=u",
                "[startup-timing] schema=2 source=ui event=correlation_bind uiRunId=u correlationId=test",
                *uac_free_ui[3:],
            ]
            ui.write_text("\n".join(bad_deferred_ui), encoding="utf-8")
            self.assertEqual(self.check(core, *options).returncode, 1)

            # Path B: authorize outcome=none with ensureBackend=reused must succeed.
            auth_none_ui = [
                "[startup-timing] stage=preload elapsedMs=5 outcome=ready schema=2 source=ui uiRunId=u",
                "[startup-timing] stage=authorize elapsedMs=12 outcome=none schema=2 source=ui uiRunId=u",
                "[startup-timing] schema=2 source=ui event=correlation_bind uiRunId=u correlationId=test",
                "[startup-timing] stage=ensureBackend elapsedMs=40 outcome=reused schema=2 source=ui uiRunId=u correlationId=test",
                *uac_free_ui[3:],
            ]
            ui.write_text("\n".join(auth_none_ui), encoding="utf-8")
            self.assertEqual(self.check(core, *options).returncode, 0)

if __name__ == "__main__":
    unittest.main()
