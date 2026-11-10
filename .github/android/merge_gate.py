import os
import re
import subprocess
import sys
from pathlib import Path

CHECK_JOBS = ("unit", "ui", "screenshots", "lint", "build")


def is_android_path(path):
    return (
        path.startswith("mobile/") and not path.endswith(".md")
        or path == ".github/workflows/android.yml"
        or path.startswith(".github/android/")
    )


def changed_paths(base, head, mode, cwd=None):
    if mode not in ("pr", "push"):
        raise ValueError("Unknown diff mode")
    for sha in (base, head):
        if not re.fullmatch(r"[0-9a-fA-F]{40}", sha) or sha == "0" * 40:
            raise ValueError("A real base and head commit are required")
    # PRs compare against the merge base; pushes compare the two exact trees.
    revision = f"{base}...{head}" if mode == "pr" else f"{base}..{head}"
    output = subprocess.check_output(
        ["git", "diff", "--no-renames", "--name-only", "-z", revision, "--"],
        cwd=cwd,
    )
    return output.decode("utf-8", errors="surrogateescape").split("\0")[:-1]


def gate_passes(changes_result, android_changed, check_results):
    if changes_result != "success" or set(check_results) != set(CHECK_JOBS):
        return False
    expected = {"true": "success", "false": "skipped"}.get(android_changed)
    return expected is not None and all(result == expected for result in check_results.values())


def main():
    if len(sys.argv) != 2 or sys.argv[1] not in ("changes", "gate"):
        raise ValueError("Usage: merge_gate.py changes|gate")
    if sys.argv[1] == "changes":
        paths = changed_paths(
            os.environ["BASE_SHA"], os.environ["HEAD_SHA"], os.environ["DIFF_MODE"]
        )
        android = str(any(is_android_path(path) for path in paths)).lower()
        output = f"android={android}\n"
        if "GITHUB_OUTPUT" in os.environ:
            with Path(os.environ["GITHUB_OUTPUT"]).open("a") as destination:
                destination.write(output)
        print(output, end="")
    else:
        changes = os.environ.get("CHANGES_RESULT", "")
        android = os.environ.get("ANDROID_CHANGED", "")
        checks = {job: os.environ.get(f"CHECK_{job.upper()}", "") for job in CHECK_JOBS}
        if not gate_passes(changes, android, checks):
            print(f"Merge blocked: changes={changes!r}, android={android!r}, checks={checks!r}")
            return 1
        print("All five Android checks passed" if android == "true" else "Android is unchanged")
    return 0


if __name__ == "__main__":
    sys.exit(main())
