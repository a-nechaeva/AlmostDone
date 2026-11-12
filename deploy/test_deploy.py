import json
import subprocess
import tempfile
import unittest
from datetime import UTC, datetime
from pathlib import Path
from unittest.mock import Mock, patch

from deploy import MAIN, MONITORING_PORTS, REPOSITORY, Deployment, check_monitoring, select_run, validate_ports


CURRENT = "a" * 40
CANDIDATE = "b" * 40
RUN = {"sha": CANDIDATE, "run_id": 5, "run_attempt": 2, "run_number": 5}


def workflow_run(number, **overrides):
    return {
        "event": "push",
        "head_branch": "main",
        "head_repository": {"full_name": REPOSITORY},
        "status": "completed",
        "conclusion": "success",
        "head_sha": CANDIDATE,
        "run_number": number,
        "id": number,
        "run_attempt": 2,
        **overrides,
    }


class WorkflowSelectionTests(unittest.TestCase):
    def test_only_successful_pushes_to_own_main_can_deploy(self):
        runs = [
            workflow_run(5),
            workflow_run(8, event="pull_request"),
            workflow_run(9, head_branch="feature"),
            workflow_run(10, head_repository={"full_name": "fork/AlmostDone"}),
        ]
        self.assertEqual(select_run(runs), RUN)

    def test_newest_failure_or_pending_run_blocks_an_older_success(self):
        for latest in (
            workflow_run(6, conclusion="failure"),
            workflow_run(6, conclusion="cancelled"),
            workflow_run(6, status="in_progress", conclusion=None),
        ):
            with self.subTest(latest=latest):
                self.assertIsNone(select_run([latest, workflow_run(5)]))

    def test_rejects_invalid_sha(self):
        with self.assertRaises(ValueError):
            select_run([workflow_run(5, head_sha="main")])


class DeploymentTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        root = Path(self.directory.name)
        self.deployment = Deployment(root, root / "legacy")
        self.deployment.public.mkdir()
        self.current = {"sha": CURRENT, "compose": "old.yml", "caddyfile": "old.caddy"}
        self.candidate = {"sha": CANDIDATE, "compose": "new.yml", "caddyfile": "new.caddy"}
        self.state = {
            "active": self.current, "migration_source": CURRENT, "database_source": CURRENT,
            "attempt": {"sha": CURRENT, "state": "deployed"},
        }
        self.deployment.save(self.state)

    def status(self):
        return json.loads((self.deployment.public / "status.json").read_text())

    @patch("deploy.run")
    def test_compose_passes_variables_as_files_through_sudo(self, run):
        self.deployment.compose(self.candidate, "config", "--quiet")
        variables = self.deployment.root / "compose.env"
        self.assertIn(f"ALMOSTREADY_IMAGE=almostready-api:{CANDIDATE}\n", variables.read_text())
        self.assertEqual(run.call_args.args[3:8], (
            "compose", "--env-file", str(self.deployment.env_file), "--env-file", str(variables),
        ))

    @patch("deploy.run")
    def test_monitoring_keeps_password_file_and_uses_existing_env_override(self, run):
        self.deployment.monitoring_compose("monitor.yml", "config")
        variables = self.deployment.root / "monitoring.env"
        initial = variables.read_bytes()
        self.deployment.monitoring_compose("monitor.yml", "up")
        self.assertEqual(variables.read_bytes(), initial)
        self.assertTrue(initial.startswith(b"GRAFANA_ADMIN_PASSWORD="))
        self.assertEqual(variables.stat().st_mode & 0o777, 0o600)
        self.assertEqual(run.call_args.args[3:], (
            "compose", "--project-name", "almostdone-monitoring", "--env-file", str(variables),
            "--env-file", str(self.deployment.env_file), "-f", "monitor.yml", "up",
        ))

    def test_monitoring_failure_keeps_api_live_and_retries_until_ready(self):
        def export(_sha, destination, compose, monitoring):
            (destination / monitoring).mkdir(parents=True)
            (destination / compose).write_text("name: almostdone-monitoring\n")

        config = {
            "services": {
                service: {"ports": [
                    {"host_ip": host, "published": published, "target": target}
                    for host, published, target, _protocol in bindings
                ]}
                for service, bindings in MONITORING_PORTS.items()
            }
        }
        with (
            patch.object(self.deployment, "git", return_value="committed monitoring files"),
            patch.object(self.deployment, "export", side_effect=export) as snapshot,
            patch.object(self.deployment, "monitoring_compose", return_value=json.dumps(config)) as compose,
            patch("deploy.check_monitoring", side_effect=[RuntimeError("not ready"), None, None]) as health,
            patch("deploy.time.time", side_effect=[100, 200]),
        ):
            with self.assertRaisesRegex(RuntimeError, "not ready"):
                self.deployment.reconcile_monitoring()
            self.assertEqual(self.status()["active_sha"], CURRENT)
            self.assertEqual(self.status()["state"], "deployed")
            self.assertEqual(self.status()["monitoring_sha"], CURRENT)
            self.assertEqual(self.status()["monitoring_state"], "failed")
            self.deployment.reconcile_monitoring()
            self.assertEqual(self.status()["monitoring_state"], "deployed")
            self.assertEqual(self.status()["monitoring_checked_at"], 100)
            self.deployment.reconcile_monitoring()
            self.assertEqual(self.status()["monitoring_checked_at"], 200)
        snapshot.assert_called_once()
        self.assertEqual(compose.call_count, 4)
        self.assertEqual(health.call_count, 3)
        self.assertNotIn("compose", self.status())
        monitoring = next(self.deployment.root.glob("monitoring/*/server/monitoring"))
        self.assertEqual(monitoring.stat().st_mode & 0o777, 0o755)

    def test_timer_retries_monitoring_if_github_lookup_fails(self):
        with (
            patch.object(self.deployment, "update", side_effect=TimeoutError),
            patch.object(self.deployment, "reconcile_monitoring") as monitor,
            self.assertRaises(TimeoutError),
        ):
            self.deployment.tick()
        monitor.assert_called_once_with()

    def test_monitoring_waits_for_api_cutover_recovery(self):
        self.deployment.save({**self.state, "attempt": {**self.state["attempt"], "cutover": True}})
        with patch.object(self.deployment, "monitoring_config") as config:
            self.deployment.reconcile_monitoring()
        config.assert_not_called()

    def test_rollback_to_release_without_monitoring_stops_stack_with_its_config(self):
        compose_file = self.deployment.root / "previous-monitoring.yml"
        compose_file.touch()
        self.deployment.save({
            **self.state, "monitoring": {"sha": CANDIDATE, "state": "deployed", "compose": str(compose_file)},
        })
        with (
            patch.object(self.deployment, "git", return_value=""),
            patch.object(self.deployment, "monitoring_compose") as compose,
        ):
            self.deployment.reconcile_monitoring()
        compose.assert_called_once_with(str(compose_file), "stop")
        self.assertNotIn("monitoring_state", self.status())

    @patch("deploy.run", side_effect=["sha256:old-image", None])
    def test_bootstrap_adopts_existing_api_and_only_reconfigures_caddy(self, run):
        self.deployment.state_file.unlink()
        self.deployment.legacy.mkdir()
        (self.deployment.legacy / ".revision").write_text(CURRENT)
        with (
            patch.object(self.deployment, "check_ready"),
            patch.object(self.deployment, "prepare", return_value=self.current),
            patch.object(self.deployment, "up") as up,
            patch.object(self.deployment, "check_status") as check_status,
        ):
            self.deployment.bootstrap()
        up.assert_called_once_with(self.current, "caddy")
        check_status.assert_called_once_with(CURRENT)
        self.assertEqual(run.call_args.args[-2:], ("sha256:old-image", f"almostready-api:legacy-{CURRENT}"))
        self.assertEqual(self.status()["active_sha"], CURRENT)

    @patch("deploy.run", side_effect=["sha256:old-image", None])
    def test_interrupted_bootstrap_restores_legacy_proxy_first(self, _run):
        self.deployment.state_file.unlink()
        self.deployment.legacy.mkdir()
        (self.deployment.legacy / ".revision").write_text(CURRENT)
        marker = self.deployment.root / "bootstrap.pending"
        marker.touch()
        order = Mock()
        order.prepare.return_value = self.current
        with (
            patch.object(self.deployment, "restore_legacy_proxy", order.restore),
            patch.object(self.deployment, "check_ready", order.ready),
            patch.object(self.deployment, "prepare", order.prepare),
            patch.object(self.deployment, "up", order.up),
            patch.object(self.deployment, "check_status"),
        ):
            self.deployment.bootstrap()
        self.assertEqual([call[0] for call in order.mock_calls[:2]], ["restore", "ready"])
        self.assertFalse(marker.exists())

    @patch("deploy.latest_tested_run", return_value=None)
    def test_failed_ci_never_fetches_or_deploys(self, _latest):
        with patch.object(self.deployment, "fetch_main") as fetch:
            self.deployment.update()
        fetch.assert_not_called()
        self.assertEqual(self.status()["active_sha"], CURRENT)

    @patch("deploy.latest_tested_run", return_value=RUN)
    def test_rejects_revision_outside_main(self, _latest):
        with (
            patch.object(self.deployment, "fetch_main"),
            patch.object(self.deployment, "is_ancestor", return_value=False) as is_ancestor,
            patch.object(self.deployment, "deploy") as deploy,
            self.assertRaisesRegex(ValueError, "not on main"),
        ):
            self.deployment.update()
        is_ancestor.assert_called_once_with(CANDIDATE, MAIN)
        deploy.assert_not_called()

    @patch("deploy.latest_tested_run", return_value=RUN)
    def test_skips_older_revision_and_failed_attempt(self, _latest):
        with (
            patch.object(self.deployment, "fetch_main") as fetch,
            patch.object(self.deployment, "is_ancestor", side_effect=[True, False, True]),
            patch.object(self.deployment, "deploy") as deploy,
        ):
            self.deployment.update()
            self.deployment.fail(self.state, RUN)
            self.deployment.update()
        fetch.assert_called_once()
        deploy.assert_not_called()

    def test_rebuilds_legacy_image_when_ci_reports_the_same_sha(self):
        state = {**self.state, "active": {**self.current, "legacy": True}}
        self.deployment.save(state)
        tested = {**RUN, "sha": CURRENT}
        with (
            patch("deploy.latest_tested_run", return_value=tested),
            patch.object(self.deployment, "fetch_main"),
            patch.object(self.deployment, "is_ancestor", return_value=True),
            patch.object(self.deployment, "deploy") as deploy,
        ):
            self.deployment.update()
        deploy.assert_called_once_with(state, tested)

    def test_backup_precedes_migration_and_success_publishes_revision(self):
        order = Mock()
        with (
            patch.object(self.deployment, "database_changed", return_value=True),
            patch.object(self.deployment, "build", return_value=self.candidate),
            patch.object(self.deployment, "backup", order.backup),
            patch.object(self.deployment, "compose", order.compose),
            patch.object(self.deployment, "remove_migrator", order.remove_migrator),
            patch.object(self.deployment, "activate", order.activate),
            patch.object(self.deployment, "check_status", order.check_status),
            patch.object(self.deployment, "check_revision", order.check_revision),
        ):
            self.deployment.deploy(self.state, RUN)
        self.assertEqual([call[0] for call in order.mock_calls], [
            "backup", "compose", "remove_migrator", "activate", "check_status", "check_revision",
        ])
        self.assertEqual(self.status()["active_sha"], CANDIDATE)
        self.assertEqual(self.status()["state"], "deployed")

    def test_migration_failure_keeps_current_api(self):
        with (
            patch.object(self.deployment, "database_changed", return_value=False),
            patch.object(self.deployment, "build", return_value=self.candidate),
            patch.object(self.deployment, "compose", side_effect=subprocess.CalledProcessError(1, "migrate")),
            patch.object(self.deployment, "remove_migrator") as remove,
            patch.object(self.deployment, "activate") as activate,
            self.assertRaises(subprocess.CalledProcessError),
        ):
            self.deployment.deploy(self.state, RUN)
        activate.assert_not_called()
        remove.assert_called_once()
        self.assertEqual(self.status()["active_sha"], CURRENT)
        self.assertEqual(self.status()["state"], "failed")
        state = json.loads(self.deployment.state_file.read_text())
        self.assertEqual(state["migration_source"], CANDIDATE)
        self.assertEqual(state["database_source"], CURRENT)

    def test_failed_backup_prevents_migration(self):
        with (
            patch.object(self.deployment, "database_changed", return_value=True),
            patch.object(self.deployment, "build", return_value=self.candidate),
            patch.object(self.deployment, "backup", side_effect=RuntimeError("backup failed")),
            patch.object(self.deployment, "compose") as compose,
            self.assertRaisesRegex(RuntimeError, "backup failed"),
        ):
            self.deployment.deploy(self.state, RUN)
        compose.assert_not_called()
        self.assertEqual(self.status()["active_sha"], CURRENT)

    def test_health_failure_restores_previous_api(self):
        with (
            patch.object(self.deployment, "database_changed", return_value=False),
            patch.object(self.deployment, "build", return_value=self.candidate),
            patch.object(self.deployment, "compose"),
            patch.object(self.deployment, "remove_migrator"),
            patch.object(self.deployment, "activate", side_effect=[RuntimeError("health failed"), None]) as activate,
            self.assertRaisesRegex(RuntimeError, "health failed"),
        ):
            self.deployment.deploy(self.state, RUN)
        self.assertEqual([call.args for call in activate.call_args_list], [({**self.candidate, **RUN},), (self.current,)])
        self.assertEqual(self.status(), {
            "active_sha": CURRENT, "active_run_number": None, "attempt_sha": CANDIDATE, "run_id": 5, "run_attempt": 2,
            "run_number": 5, "state": "failed",
        })

    @patch("deploy.latest_tested_run", return_value=None)
    def test_interrupted_cutover_is_restored_before_any_new_release(self, _latest):
        self.deployment.save({**self.state, "attempt": {**RUN, "state": "deploying", "cutover": True}})
        with patch.object(self.deployment, "activate") as activate:
            self.deployment.update()
        activate.assert_called_once_with(self.current)
        self.assertEqual(self.status()["state"], "failed")

    @patch("deploy.latest_tested_run", return_value=None)
    def test_interrupted_migration_is_stopped_before_any_new_release(self, _latest):
        self.deployment.save({**self.state, "attempt": {**RUN, "state": "deploying", "migrating": True}})
        with patch.object(self.deployment, "remove_migrator") as remove:
            self.deployment.update()
        remove.assert_called_once()
        self.assertEqual(self.status()["state"], "failed")

    @patch("deploy.run", return_value="001_server_state\n002_volume")
    def test_rollback_does_not_allow_changes_to_already_applied_migration(self, _run):
        recorded = {"001_server_state": "first", "002_volume": "applied"}
        changed = {**recorded, "002_volume": "different"}
        state = {**self.state, "migration_source": "c" * 40}
        with (
            patch.object(self.deployment, "migrations_at", side_effect=[recorded, changed]) as migrations,
            self.assertRaisesRegex(ValueError, "Applied migration 002_volume"),
        ):
            self.deployment.database_changed(state, CANDIDATE)
        self.assertEqual(migrations.call_args_list[0].args, ("c" * 40,))

    @patch("deploy.run", return_value="001_server_state")
    def test_unapplied_sql_can_be_corrected_and_requires_backup(self, _run):
        recorded = {"001_server_state": "first", "002_volume": "failed"}
        corrected = {**recorded, "002_volume": "fixed"}
        with (
            patch.object(self.deployment, "migrations_at", side_effect=[recorded, corrected]),
            patch.object(self.deployment, "git", return_value=""),
        ):
            self.assertTrue(self.deployment.database_changed(self.state, CANDIDATE))

    @patch("deploy.run", return_value="001_server_state\n002_volume")
    def test_seed_only_change_is_rejected_even_after_api_rollback(self, _run):
        migrations = {"001_server_state": "first", "002_volume": "applied"}
        state = {**self.state, "migration_source": "c" * 40, "database_source": "c" * 40}
        with (
            patch.object(self.deployment, "migrations_at", return_value=migrations),
            patch.object(self.deployment, "git", return_value="db/seed.sql") as git,
            self.assertRaisesRegex(ValueError, "require a migration"),
        ):
            self.deployment.database_changed(state, CANDIDATE)
        self.assertEqual(git.call_args.args[2:4], ("c" * 40, CANDIDATE))

    @patch("deploy.run", return_value="001_server_state")
    def test_failed_seed_migration_cannot_disappear_from_next_release(self, _run):
        previous = {"001_server_state": "first"}
        attempted = {**previous, "002_seed": "pending"}
        state = {**self.state, "migration_source": "c" * 40}
        with (
            patch.object(self.deployment, "migrations_at", side_effect=[attempted, previous, previous]),
            patch.object(self.deployment, "bootstrap_changed", return_value=True),
            self.assertRaisesRegex(ValueError, "require a migration"),
        ):
            self.deployment.database_changed(state, CANDIDATE)

    @patch("deploy.run", return_value="001_server_state")
    def test_same_seed_migration_can_be_retried_when_still_pending(self, _run):
        previous = {"001_server_state": "first"}
        attempted = {**previous, "002_seed": "pending"}
        state = {**self.state, "migration_source": CANDIDATE}
        with (
            patch.object(self.deployment, "migrations_at", side_effect=[attempted, attempted, previous]),
            patch.object(self.deployment, "bootstrap_changed", return_value=True),
        ):
            self.assertTrue(self.deployment.database_changed(state, CANDIDATE))

    @patch("deploy.run", return_value="001_server_state\n002_seed")
    def test_recovers_if_database_committed_before_success_was_recorded(self, _run):
        previous = {"001_server_state": "first"}
        applied = {**previous, "002_seed": "applied"}
        state = {**self.state, "migration_source": "c" * 40}
        with (
            patch.object(self.deployment, "migrations_at", side_effect=[applied, applied, previous]),
            patch.object(self.deployment, "bootstrap_changed", side_effect=[True, False]),
        ):
            self.assertFalse(self.deployment.database_changed(state, CANDIDATE))

    def test_operator_rollback_keeps_migration_source_and_suppresses_retry(self):
        newer = {"sha": "c" * 40, "run_id": 6, "run_attempt": 1, "run_number": 6}
        state = {
            "active": {**self.candidate, **RUN}, "previous": self.current,
            "migration_source": CANDIDATE, "database_source": CANDIDATE,
            "attempt": {**RUN, "state": "deployed"},
        }
        self.deployment.save(self.deployment.failed_state(state, newer))
        self.assertEqual(self.status()["active_run_number"], 5)
        with patch.object(self.deployment, "activate") as activate:
            self.deployment.rollback()
        activate.assert_called_once_with(self.current)
        state = json.loads(self.deployment.state_file.read_text())
        self.assertEqual(state["migration_source"], CANDIDATE)
        self.assertEqual(state["database_source"], CANDIDATE)
        self.assertEqual(state["failed_runs"], {"5": 2, "6": 1})
        self.assertEqual(self.status()["state"], "failed")
        self.assertEqual(self.status()["active_sha"], CURRENT)


class ProductionPortsTests(unittest.TestCase):
    def test_caddy_must_be_public_and_api_must_be_local(self):
        def port(host, number):
            return {"host_ip": host, "target": number, "published": str(number), "protocol": "tcp"}

        services = {
            "api": {"ports": [port("127.0.0.1", 8000)]},
            "caddy": {"ports": [port("0.0.0.0", 80), port("0.0.0.0", 443)]},
            "migrate": {},
        }
        validate_ports(services)
        services["caddy"]["ports"][1]["host_ip"] = "127.0.0.1"
        with self.assertRaisesRegex(ValueError, "allowed bindings"):
            validate_ports(services)

    def test_rejects_public_monitoring_port(self):
        services = {
            "prometheus": {"ports": [{"host_ip": "127.0.0.1", "target": 9090, "published": 9090}]},
            "grafana": {"ports": [{"host_ip": "127.0.0.1", "target": 3000, "published": 3000}]},
        }
        validate_ports(services, MONITORING_PORTS)
        services["grafana"]["ports"][0]["host_ip"] = "0.0.0.0"
        with self.assertRaisesRegex(ValueError, "allowed bindings"):
            validate_ports(services, MONITORING_PORTS)


class MonitoringReadinessTests(unittest.TestCase):
    @patch("deploy.time.sleep")
    @patch("deploy.time.time", return_value=100)
    @patch("deploy.run")
    def test_requires_healthy_grafana_and_a_fresh_successful_scrape(self, run, _time, sleep):
        def scrape(timestamp, health="up"):
            target = {"labels": {"job": "api-metrics"}, "health": health,
                      "lastScrape": datetime.fromtimestamp(timestamp, UTC).isoformat()}
            return json.dumps({"status": "success", "data": {"activeTargets": [target]}})

        healthy_grafana = '{"database": "ok"}'
        run.side_effect = [
            None, healthy_grafana, scrape(99),
            None, healthy_grafana, scrape(101, health="down"),
            None, '{"database": "unavailable"}', scrape(102),
            None, healthy_grafana, scrape(103),
        ]
        check_monitoring()
        self.assertEqual(sleep.call_count, 3)
        self.assertIn("http://127.0.0.1:9090/api/v1/targets?state=active", run.call_args.args)
