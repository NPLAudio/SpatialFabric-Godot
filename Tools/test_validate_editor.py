"""Offline tests for isolated editor validation and evidence gates."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("validate_editor", Path(__file__).with_name("validate_editor.py"))
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)


class EditorGateTests(unittest.TestCase):
    def test_enrollment_only_changes_disposable_copy(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            source = root / "Source"
            source.mkdir()
            for name in ("addons", "examples", "Tests"):
                (source / name).mkdir()
                (source / name / "fixture.txt").write_text(name)
            original = "[editor_plugins]\n" + validator.ENABLED + "\n"
            (source / "project.godot").write_text(original)
            target = root / "Copy"
            validator.prepare_project(source, target)
            self.assertEqual((source / "project.godot").read_text(), original)
            self.assertIn(validator.TEST_ENABLED, (target / "project.godot").read_text())
            self.assertEqual((target / "Tests/fixture.txt").read_text(), "Tests")

    def test_unknown_configuration_fails_closed(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "project.godot").write_text("[editor_plugins]\nenabled=[]\n")
            with self.assertRaises(RuntimeError):
                validator.prepare_project(root, root / "Copy")
            self.assertFalse((root / "Copy").exists())

    def test_shutdown_diagnostics_fail_even_after_passes(self):
        validator.check_log("18 assertions passed; clean shutdown")
        for text in ("WARNING: ObjectDB instances leaked", "ERROR: RID leaked", "31 RIDs were leaked"):
            with self.subTest(text=text), self.assertRaises(RuntimeError):
                validator.check_log(text)

    def test_required_evidence_not_just_exit_zero(self):
        passed = sorted(validator.REQUIRED)
        self.assertEqual(validator.check_report({"status": "passed", "passed": passed, "failed": []}), len(passed))
        for data in ({}, {"status": "passed", "passed": [], "failed": []},
                     {"status": "passed", "passed": passed, "failed": ["failure"]}):
            with self.subTest(data=data), self.assertRaises(RuntimeError):
                validator.check_report(data)


if __name__ == "__main__":
    unittest.main()
