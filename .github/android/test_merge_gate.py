import subprocess
import tempfile
import unittest
from pathlib import Path

from merge_gate import CHECK_JOBS, changed_paths, gate_passes, is_android_path


class AndroidPathsTest(unittest.TestCase):
    def test_android_sources_and_ci(self):
        for path in (
            "mobile/app/src/main/Main.kt",
            "mobile/gradlew",
            "mobile/.hidden",
            "mobile/a\nb.kt",
            ".github/workflows/android.yml",
            ".github/android/merge_gate.py",
            ".github/android/README.md",
        ):
            with self.subTest(path=path):
                self.assertTrue(is_android_path(path))

    def test_backend_and_markdown_do_not_start_android(self):
        for path in (
            "README.md",
            "docs/mobile-plan.md",
            "mobile/README.md",
            "mobile/app/docs/setup.md",
            "backend/main.py",
            "mobile-other/main.kt",
            ".github/workflows/backend.yml",
        ):
            with self.subTest(path=path):
                self.assertFalse(is_android_path(path))


class MergeGateTest(unittest.TestCase):
    def test_all_five_results_are_required(self):
        for android, expected in (("true", "success"), ("false", "skipped")):
            green = dict.fromkeys(CHECK_JOBS, expected)
            self.assertTrue(gate_passes("success", android, green))
            for job in CHECK_JOBS:
                for result in ("success", "failure", "cancelled", "skipped", "", "unknown"):
                    with self.subTest(android=android, job=job, result=result):
                        checks = dict(green, **{job: result})
                        self.assertEqual(result == expected, gate_passes("success", android, checks))

    def test_missing_or_unexpected_check_cannot_allow_merge(self):
        green = dict.fromkeys(CHECK_JOBS, "success")
        for job in CHECK_JOBS:
            checks = dict(green)
            del checks[job]
            self.assertFalse(gate_passes("success", "true", checks))
        self.assertFalse(gate_passes("success", "true", dict(green, extra="success")))

    def test_classifier_must_finish_with_a_known_output(self):
        green = dict.fromkeys(CHECK_JOBS, "success")
        for changes in ("failure", "cancelled", "skipped", "", "unknown"):
            self.assertFalse(gate_passes(changes, "true", green))
        for android in ("", "unknown"):
            self.assertFalse(gate_passes("success", android, green))


class GitChangesTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.git("init", "-q")
        self.write("README.md", "initial\n")
        self.base = self.commit()

    def git(self, *args):
        return subprocess.check_output(
            ["git", "-c", "user.name=Fixture", "-c", "user.email=fixture@example.test", *args],
            cwd=self.root,
            stderr=subprocess.PIPE,
        ).decode().strip()

    def write(self, name, content):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)

    def commit(self):
        self.git("add", ".")
        self.git("commit", "-qm", "fixture")
        return self.git("rev-parse", "HEAD")

    def test_backend_and_readme_only_diff(self):
        self.write("backend/main.py", "pass\n")
        self.write("mobile/README.md", "docs\n")
        head = self.commit()
        self.assertFalse(any(map(is_android_path, changed_paths(self.base, head, "pr", self.root))))

    def test_deletion_rename_and_newlines_are_not_lost(self):
        self.write("mobile/a\nb.kt", "android\n")
        base = self.commit()
        self.git("mv", "mobile/a\nb.kt", "backend.kt")
        head = self.commit()
        paths = changed_paths(base, head, "pr", self.root)
        self.assertIn("mobile/a\nb.kt", paths)
        self.assertIn("backend.kt", paths)
        self.assertTrue(any(map(is_android_path, paths)))

    def test_workflow_only_diff_requires_android(self):
        self.write(".github/workflows/android.yml", "name: Android\n")
        paths = changed_paths(self.base, self.commit(), "pr", self.root)
        self.assertTrue(any(map(is_android_path, paths)))

    def test_large_diff_has_no_path_count_limit(self):
        for number in range(350):
            self.write(f"backend/{number}.py", "pass\n")
        self.write("mobile/last.kt", "android\n")
        paths = changed_paths(self.base, self.commit(), "pr", self.root)
        self.assertEqual(351, len(paths))
        self.assertTrue(any(map(is_android_path, paths)))

    def test_pr_ignores_base_branch_only_changes(self):
        self.write("backend/main.py", "pass\n")
        head = self.commit()
        self.git("checkout", "-q", self.base)
        self.write("mobile/base.kt", "base only\n")
        base = self.commit()
        self.assertFalse(any(map(is_android_path, changed_paths(base, head, "pr", self.root))))
        self.assertTrue(any(map(is_android_path, changed_paths(base, head, "push", self.root))))

    def test_invalid_or_missing_commits_fail(self):
        for base in ("", "0" * 40, "--help"):
            with self.subTest(base=base), self.assertRaises(ValueError):
                changed_paths(base, self.base, "pr", self.root)
        with self.assertRaises(subprocess.CalledProcessError):
            changed_paths("1" * 40, self.base, "pr", self.root)


if __name__ == "__main__":
    unittest.main()
