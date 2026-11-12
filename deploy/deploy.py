"""Deploy tested revisions of the AlmostReady API on the existing production VM."""

import argparse
import fcntl
import hashlib
import json
import os
import re
import secrets
import subprocess
import tarfile
import tempfile
import time
from datetime import datetime
from pathlib import Path
from urllib.request import Request, urlopen


REPOSITORY = "a-nechaeva/AlmostDone"
ORIGIN = f"https://github.com/{REPOSITORY}.git"
RUNS = (
    f"https://api.github.com/repos/{REPOSITORY}/actions/workflows/server.yml/runs"
    "?branch=main&event=push&per_page=10"
)
API_IP = "51.250.76.77"
READY = "/api/v1/health/ready"
DOCKER = ("sudo", "-n", "docker")
MAIN = "refs/remotes/origin/main"
MIGRATOR = "almostready-production-migrate"
CURL = ("curl", "--noproxy", "*", "-fsS", "--max-time", "5", "--retry", "6",
        "--retry-delay", "2", "--retry-all-errors")
API_PORTS = {
    "api": {("127.0.0.1", "8000", "8000", "tcp")},
    "caddy": {("0.0.0.0", "80", "80", "tcp"), ("0.0.0.0", "443", "443", "tcp")},
    "migrate": set(),
}
MONITORING_PORTS = {
    "prometheus": {("127.0.0.1", "9090", "9090", "tcp")},
    "grafana": {("127.0.0.1", "3000", "3000", "tcp")},
}
MONITORING_PATHS = ("server/docker-compose.monitoring.yml", "server/monitoring")


def valid_sha(sha):
    return isinstance(sha, str) and re.fullmatch(r"[0-9a-f]{40}", sha) is not None


def select_run(runs):
    main_pushes = [
        run for run in runs
        if run["event"] == "push"
        and run["head_branch"] == "main"
        and run["head_repository"]["full_name"] == REPOSITORY
    ]
    if not main_pushes:
        return None
    latest = max(main_pushes, key=lambda run: run["run_number"])
    if latest["status"] != "completed" or latest["conclusion"] != "success":
        return None
    if not valid_sha(latest["head_sha"]):
        raise ValueError("Invalid revision in GitHub Actions response")
    return {
        "sha": latest["head_sha"],
        "run_id": latest["id"],
        "run_attempt": latest["run_attempt"],
        "run_number": latest["run_number"],
    }


def latest_tested_run():
    request = Request(RUNS, headers={"Accept": "application/vnd.github+json"})
    with urlopen(request, timeout=15) as response:
        return select_run(json.load(response)["workflow_runs"])


def run(*command, capture=False, stdin=subprocess.DEVNULL, stdout=None, timeout=120):
    result = subprocess.run(
        command, check=True, timeout=timeout, stdin=stdin,
        stdout=subprocess.PIPE if capture else stdout, text=capture,
    )
    return result.stdout.strip() if capture else None


def atomic_write(path, data, mode=0o600):
    temporary = path.with_suffix(path.suffix + ".tmp")
    with temporary.open("wb") as output:
        output.write(data)
        output.flush()
        os.fchmod(output.fileno(), mode)
        os.fsync(output.fileno())
    temporary.replace(path)
    sync_directory(path.parent)


def sync_directory(path):
    descriptor = os.open(path, os.O_RDONLY)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def image_for(sha, legacy=False):
    return f"almostready-api:legacy-{sha}" if legacy else f"almostready-api:{sha}"


def validate_ports(services, expected=API_PORTS):
    actual = {
        service: {(port.get("host_ip"), str(port["published"]), str(port["target"]), port.get("protocol", "tcp"))
                  for port in config.get("ports", [])}
        for service, config in services.items()
    }
    if actual != expected:
        raise ValueError("Production Compose port bindings differ from the allowed bindings")


def check_monitoring():
    curl = ("curl", "--noproxy", "*", "-fsS", "--max-time", "3")
    prometheus = "http://127.0.0.1:9090"
    started_at = time.time()
    deadline = time.monotonic() + 75
    while time.monotonic() < deadline:
        try:
            run(*curl, prometheus + "/-/ready", stdout=subprocess.DEVNULL)
            grafana = json.loads(run(*curl, "http://127.0.0.1:3000/api/health", capture=True))
            scrape = json.loads(run(*curl, prometheus + "/api/v1/targets?state=active", capture=True))
            if grafana.get("database") == "ok" and scrape.get("status") == "success" and any(
                target["labels"].get("job") == "api-metrics"
                and target["health"] == "up"
                and datetime.fromisoformat(target["lastScrape"]).timestamp() >= started_at
                for target in scrape["data"]["activeTargets"]
            ):
                return
        except (subprocess.CalledProcessError, json.JSONDecodeError):
            pass
        time.sleep(3)
    raise RuntimeError("Monitoring is not ready: check Grafana, Prometheus and the API scrape target")


class Deployment:
    def __init__(self, root, legacy):
        self.root = root.resolve()
        self.legacy = legacy.resolve()
        self.env_file = self.legacy / "server/.env"
        self.state_file = self.root / "state.json"
        self.repository = self.root / "repository.git"
        self.public = self.root / "public"

    def publish(self, state):
        attempt = state["attempt"]
        active = state["active"] if not attempt.get("cutover") else {}
        monitoring = state.get("monitoring", {})
        status = {
            "active_sha": active.get("sha"),
            "active_run_number": active.get("run_number"),
            "attempt_sha": attempt["sha"],
            "run_id": attempt.get("run_id"),
            "run_attempt": attempt.get("run_attempt"),
            "run_number": attempt.get("run_number"),
            "state": attempt["state"],
        }
        if monitoring:
            status.update(
                monitoring_sha=monitoring["sha"],
                monitoring_state=monitoring["state"],
                monitoring_checked_at=monitoring.get("checked_at"),
            )
        atomic_write(self.public / "status.json", json.dumps(status).encode(), 0o644)

    def save(self, state):
        atomic_write(self.state_file, json.dumps(state, indent=2).encode())
        self.publish(state)

    def compose(self, release, *args, **kwargs):
        variables = self.root / "compose.env"
        atomic_write(variables, (
            f"ALMOSTREADY_IMAGE={image_for(release['sha'], release.get('legacy'))}\n"
            f"ALMOSTREADY_ENV_FILE={self.env_file}\n"
            f"ALMOSTREADY_CADDYFILE={release['caddyfile']}\n"
            f"ALMOSTREADY_STATUS_DIR={self.public}\n"
        ).encode())
        return run(
            *DOCKER, "compose", "--env-file", str(self.env_file), "--env-file", str(variables),
            "-f", release["compose"], *args, **kwargs,
        )

    def prepare(self, sha, files, *, legacy=False):
        config_dir = self.root / "config"
        config_dir.mkdir(exist_ok=True)
        release = {"sha": sha, "legacy": legacy}
        for key, filename in (("compose", "compose.yml"), ("caddyfile", "Caddyfile")):
            data = (files / filename).read_bytes()
            digest = hashlib.sha256(data).hexdigest()
            destination = config_dir / f"{digest}.{filename}"
            atomic_write(destination, data, 0o644)
            release[key] = str(destination)

        config = json.loads(self.compose(release, "config", "--format", "json", capture=True))
        validate_ports(config["services"])
        caddy_image = config["services"]["caddy"]["image"]
        run(
            *DOCKER, "run", "--rm", "--network", "none", "--mount",
            f"type=bind,source={release['caddyfile']},target=/etc/caddy/Caddyfile,readonly",
            caddy_image, "caddy", "validate", "--config", "/etc/caddy/Caddyfile", timeout=180,
        )
        return release

    def https(self, path, *options):
        return run(*CURL, *options, "--connect-to", f"{API_IP}:443:127.0.0.1:443", f"https://{API_IP}{path}",
                   capture=True, timeout=50)

    def check_ready(self):
        local = run(*CURL, "http://127.0.0.1:8000" + READY, capture=True, timeout=50)
        if json.loads(local)["status"] != "ok" or json.loads(self.https(READY))["status"] != "ok":
            raise RuntimeError("API did not report readiness")

    def check_status(self, sha):
        status = json.loads(self.https("/_deploy/status.json"))
        if status["attempt_sha"] != sha:
            raise RuntimeError("Caddy did not publish the expected deployment status")

    def check_revision(self, sha):
        revision = self.https(READY, "-o", "/dev/null", "-w", "%header{x-almostready-revision}")
        if revision != sha:
            raise RuntimeError("HTTPS readiness did not report the tested image revision")

    def up(self, release, service):
        self.compose(release, "up", "-d", "--no-deps", "--no-build", "--wait", "--wait-timeout", "120",
                     service, timeout=160)

    def activate(self, release):
        self.up(release, "api")
        self.up(release, "caddy")
        self.check_ready()
        image = run(*DOCKER, "inspect", "--format", "{{.Config.Image}}", "almostdone-api-1", capture=True)
        if image != image_for(release["sha"], release.get("legacy")):
            raise RuntimeError("Running API image does not match the tested revision")

    def restore_legacy_proxy(self):
        server = self.legacy / "server"
        run(
            *DOCKER, "compose", "--env-file", str(self.env_file),
            "-f", str(server / "docker-compose.yml"), "-f", str(server / "compose.cloud.yml"),
            "-f", str(server / "compose.https.yml"), "up", "-d", "--no-deps", "--no-build", "caddy",
        )
        self.check_ready()

    def bootstrap(self):
        pending = self.root / "bootstrap.pending"
        if self.state_file.exists():
            self.publish(json.loads(self.state_file.read_text()))
            pending.unlink(missing_ok=True)
            return
        if pending.exists():
            self.restore_legacy_proxy()
            pending.unlink()
        sha = (self.legacy / ".revision").read_text().strip()
        if not valid_sha(sha):
            raise ValueError("Invalid revision in the existing deployment")
        self.check_ready()
        image = run(*DOCKER, "inspect", "--format", "{{.Image}}", "almostdone-api-1", capture=True)
        run(*DOCKER, "image", "tag", image, image_for(sha, legacy=True))
        release = self.prepare(sha, Path(__file__).parent, legacy=True)
        state = {
            "active": release, "migration_source": sha, "database_source": sha,
            "attempt": {"sha": sha, "state": "deployed"},
        }
        atomic_write(pending, b"")
        try:
            self.up(release, "caddy")
            self.check_ready()
            self.publish(state)
            self.check_status(sha)
            self.save(state)
        except Exception:
            self.state_file.unlink(missing_ok=True)
            self.restore_legacy_proxy()
            pending.unlink()
            raise
        pending.unlink()

    def git(self, *args, **kwargs):
        return run("git", "--git-dir", str(self.repository), *args, **kwargs)

    def fetch_main(self):
        if not self.repository.exists():
            run("git", "init", "--bare", str(self.repository))
        self.git("fetch", "--no-tags", ORIGIN, f"+refs/heads/main:{MAIN}", timeout=180)

    def is_ancestor(self, older, newer):
        try:
            self.git("merge-base", "--is-ancestor", older, newer)
        except subprocess.CalledProcessError as error:
            if error.returncode == 1:
                return False
            raise
        return True

    def migrations_at(self, sha):
        entries = self.git("ls-tree", "-r", sha, "--", "db/migrations/", capture=True)
        migrations = {}
        for entry in entries.splitlines():
            fields, filename = entry.split("\t", 1)
            path = Path(filename)
            if path.suffix == ".sql" and path.parent == Path("db/migrations"):
                migrations[path.stem] = fields.split()[2]
        return migrations

    def bootstrap_changed(self, previous, candidate):
        return bool(self.git(
            "diff", "--name-only", previous, candidate, "--", "db/schema.sql", "db/seed.sql", capture=True,
        ))

    def database_changed(self, state, candidate):
        source = state["migration_source"]
        reference = self.migrations_at(source)
        migrations = self.migrations_at(candidate)
        applied = set(run(
            *DOCKER, "exec", "almostdone-db-1", "psql", "-X", "-At", "-v", "ON_ERROR_STOP=1",
            "-U", "koma", "-d", "almostdone", "-c", "SELECT version FROM public.api_schema_migrations",
            capture=True,
        ).splitlines())
        for version in applied:
            if version not in reference or migrations.get(version) != reference[version]:
                raise ValueError(f"Applied migration {version} is missing or differs from the recorded SQL")
        pending = migrations.keys() - applied
        baseline = state["database_source"]
        if self.bootstrap_changed(baseline, candidate):
            previous = self.migrations_at(baseline)
            changed = {version for version, blob in migrations.items() if blob != previous.get(version)}
            recovered = (
                not pending and bool(changed) and migrations == reference
                and not self.bootstrap_changed(source, candidate)
            )
            if not (pending & changed or recovered):
                raise ValueError("Schema or seed changes require a migration for the live database")
        return bool(pending)

    def backup(self, sha):
        directory = self.root / "backups"
        directory.mkdir(exist_ok=True)
        with tempfile.NamedTemporaryFile(dir=directory, delete=False) as backup:
            path = Path(backup.name)
            try:
                run(*DOCKER, "exec", "almostdone-db-1", "pg_dump", "-U", "koma", "-d", "almostdone",
                    "-Fc", stdout=backup, timeout=180)
                os.fsync(backup.fileno())
                with path.open("rb") as archive:
                    run(*DOCKER, "exec", "-i", "almostdone-db-1", "pg_restore", "--list",
                        stdin=archive, stdout=subprocess.DEVNULL)
                destination = directory / f"{sha}-{path.name}.dump"
                path.replace(destination)
                sync_directory(directory)
                print(f"Saved database backup {destination}")
            finally:
                path.unlink(missing_ok=True)

    def export(self, sha, destination, *paths):
        archive_path = destination / "source.tar"
        self.git("archive", f"--output={archive_path}", sha, *paths)
        with tarfile.open(archive_path) as archive:
            archive.extractall(destination, filter="data")
        archive_path.unlink()

    def build(self, sha):
        with tempfile.TemporaryDirectory(dir=self.root) as directory:
            source = Path(directory)
            self.export(sha, source, "server", "engine", "db", "docs/api", "deploy")
            release = self.prepare(sha, source / "deploy")
            run(*DOCKER, "build", "-f", str(source / "server/Dockerfile"),
                "--build-arg", f"ALMOSTDONE_DEPLOY_REVISION={sha}", "-t", image_for(sha), str(source), timeout=600)
        return release

    def monitoring_compose(self, compose, *args, **kwargs):
        variables = self.root / "monitoring.env"
        if not variables.exists():
            atomic_write(variables, f"GRAFANA_ADMIN_PASSWORD={secrets.token_urlsafe(32)}\n".encode())
        return run(
            *DOCKER, "compose", "--project-name", "almostdone-monitoring",
            "--env-file", str(variables), "--env-file", str(self.env_file),
            "-f", str(compose), *args, **kwargs,
        )

    def monitoring_config(self, active):
        sha = active["sha"]
        entries = "" if active.get("legacy") else self.git("ls-tree", sha, "--", *MONITORING_PATHS, capture=True)
        if entries:
            return self.root / "monitoring" / hashlib.sha256(entries.encode()).hexdigest()

    def start_monitoring(self, sha, directory):
        compose = directory / MONITORING_PATHS[0]
        if not directory.exists():
            directory.parent.mkdir(exist_ok=True)
            with tempfile.TemporaryDirectory(dir=directory.parent) as temporary:
                source = Path(temporary) / "source"
                source.mkdir()
                self.export(sha, source, *MONITORING_PATHS)
                config_root = source / MONITORING_PATHS[1]
                # Grafana reads the bind-mounted directories as a different UID.
                for path in (config_root, *config_root.rglob("*")):
                    if path.is_dir() and not path.is_symlink():
                        path.chmod(0o755)
                source.rename(directory)
        config = self.monitoring_compose(compose, "config", "--format", "json", capture=True)
        validate_ports(json.loads(config)["services"], MONITORING_PORTS)
        self.monitoring_compose(compose, "up", "-d", "--no-build", "--wait", "--wait-timeout", "120", timeout=240)

    def reconcile_monitoring(self):
        state = json.loads(self.state_file.read_text())
        if state["attempt"].get("cutover") or state["attempt"].get("migrating"):
            return
        sha = state["active"]["sha"]
        previous = state.get("monitoring", {})
        already_started = previous.get("sha") == sha and previous.get("state") == "deployed"
        monitoring = previous
        if not already_started:
            directory = self.monitoring_config(state["active"])
            if directory is None:
                compose = previous.get("compose")
                if compose and Path(compose).is_file():
                    self.monitoring_compose(compose, "stop")
                if previous:
                    self.save({**state, "monitoring": {}})
                return
            monitoring = {"sha": sha, "state": "deploying", "compose": str(directory / MONITORING_PATHS[0])}
            self.save({**state, "monitoring": monitoring})
        try:
            if not already_started:
                self.start_monitoring(sha, directory)
            check_monitoring()
        except Exception:
            self.save({**state, "monitoring": {**monitoring, "state": "failed"}})
            raise
        self.save({**state, "monitoring": {**monitoring, "state": "deployed", "checked_at": int(time.time())}})
        if not already_started:
            print(f"Monitoring ready for {sha}")

    def remove_migrator(self):
        container = run(*DOCKER, "ps", "-aq", "--filter", f"name=^/{MIGRATOR}$", capture=True)
        if container:
            run(*DOCKER, "rm", "-f", container)

    def deploy(self, state, candidate):
        current = state["active"]
        sha = candidate["sha"]
        attempt = {**candidate, "state": "deploying"}
        self.save({**state, "attempt": attempt})
        try:
            print(f"Deploying {sha}")
            database_changed = self.database_changed(state, sha)
            release = {**self.build(sha), **candidate}
            if database_changed:
                self.backup(sha)
            state = {**state, "migration_source": sha}
            attempt = {**attempt, "migrating": True}
            self.save({**state, "attempt": attempt})
            self.compose(release, "run", "--name", MIGRATOR, "--no-deps", "-T", "migrate", timeout=240)
            state = {**state, "database_source": sha}
            self.save({**state, "attempt": attempt})
            self.remove_migrator()
            attempt = {**attempt, "migrating": False, "cutover": True}
            self.save({**state, "attempt": attempt})
            self.activate(release)
            self.check_status(sha)
            self.check_revision(sha)
            self.save({
                **state, "active": release, "previous": current,
                "attempt": {**candidate, "state": "deployed"},
            })
            print(f"Deployed {sha}")
        except Exception:
            self.fail(state, attempt)
            raise

    @staticmethod
    def failed_state(state, attempt):
        failed_runs = {**state.get("failed_runs", {})}
        run_id = str(attempt["run_id"])
        failed_runs[run_id] = max(failed_runs.get(run_id, 0), attempt["run_attempt"])
        return {**state, "failed_runs": failed_runs, "attempt": {**attempt, "state": "failed"}}

    def fail(self, state, attempt):
        try:
            if attempt.get("migrating"):
                self.remove_migrator()
            if attempt.get("cutover"):
                current = state["active"]
                print(f"Restoring {current['sha']}")
                self.activate(current)
        except Exception:
            self.save(self.failed_state(state, attempt))
            raise
        failed = self.failed_state(state, {**attempt, "cutover": False, "migrating": False})
        self.save(failed)
        return failed

    def rollback(self):
        state = json.loads(self.state_file.read_text())
        previous = state.get("previous")
        current = state["active"]
        attempt = state["attempt"]
        if (not previous or "run_id" not in current or attempt["state"] == "deploying"
                or attempt.get("cutover") or attempt.get("migrating")):
            raise RuntimeError("No completed release to roll back")
        attempt = {key: current[key] for key in ("sha", "run_id", "run_attempt", "run_number")}
        attempt.update(state="deploying", cutover=True)
        self.save({**state, "attempt": attempt})
        try:
            self.activate(previous)
            self.save(self.failed_state({**state, "active": previous, "previous": current},
                                        {**attempt, "cutover": False}))
        except Exception:
            self.fail(state, attempt)
            raise

    def update(self):
        state = json.loads(self.state_file.read_text())
        self.publish(state)
        attempt = state["attempt"]
        if attempt["state"] == "deploying" or attempt.get("cutover") or attempt.get("migrating"):
            state = self.fail(state, attempt)
        candidate = latest_tested_run()
        active = state["active"]
        if not candidate or (candidate["sha"] == active["sha"] and not active.get("legacy")):
            return
        failed_attempt = state.get("failed_runs", {}).get(str(candidate["run_id"]), 0)
        if candidate["run_attempt"] <= failed_attempt:
            return

        self.fetch_main()
        sha = candidate["sha"]
        if not self.is_ancestor(sha, MAIN):
            self.fail(state, candidate)
            raise ValueError("Tested revision is not on main")
        current = state["active"]["sha"]
        if not self.is_ancestor(current, sha):
            if self.is_ancestor(sha, current):
                return
            self.fail(state, candidate)
            raise ValueError("Tested revision is not a fast-forward from the deployed revision")
        self.deploy(state, candidate)

    def tick(self):
        try:
            self.update()
        finally:
            self.reconcile_monitoring()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_mutually_exclusive_group()
    commands.add_argument("--bootstrap", action="store_true")
    commands.add_argument("--rollback", action="store_true")
    args = parser.parse_args()
    os.umask(0o077)
    deployment = Deployment(Path.home() / "almostready-deploy", Path.home() / "almostready")
    deployment.root.mkdir(exist_ok=True)
    deployment.public.mkdir(exist_ok=True)
    deployment.public.chmod(0o755)
    with (deployment.root / "lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            if args.bootstrap or args.rollback:
                raise RuntimeError("A deployment is already running") from None
            return
        if args.bootstrap:
            deployment.bootstrap()
        elif args.rollback:
            deployment.rollback()
            deployment.reconcile_monitoring()
        else:
            deployment.tick()


if __name__ == "__main__":
    main()
