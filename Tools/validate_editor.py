"""Run silent authoring assertions in a disposable, normal Godot editor session.

Unlike --editor --script SceneTree, the EditorPlugin runner preserves normal
editor teardown. Never enables the test plugin or edits assets in the source tree.
"""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
ENABLED = 'enabled=PackedStringArray("res://addons/spatial_fabric/plugin.cfg")'
TEST_ENABLED = 'enabled=PackedStringArray("res://addons/spatial_fabric/plugin.cfg", "res://Tests/Godot/plugin.cfg")'
REQUIRED = {
    "EditorUndoRedoManager undoes routing transaction",
    "EditorUndoRedoManager redoes routing transaction",
    "editor CSV file import undoes as one transaction",
    "editor playback/live collision rejects whole row",
    "editor authoring never opens audio",
}


def prepare_project(source, target):
    config = (source / "project.godot").read_text(encoding="utf-8")
    if config.count(ENABLED) != 1:
        raise RuntimeError("Unexpected editor plugin configuration; refusing to guess test enrollment")
    target.mkdir()
    for name in ("addons", "examples", "Tests"):
        shutil.copytree(source / name, target / name)
    (target / "project.godot").write_text(config.replace(ENABLED, TEST_ENABLED), encoding="utf-8")


def check_log(text):
    if any(marker in text for marker in ("ERROR:", "WARNING:", "Parse Error:", "Unicode parsing error", "were leaked")):
        raise RuntimeError("Godot editor error/warning/leak diagnostics; inspect evidence log")


def check_report(data):
    passed = data.get("passed", [])
    if (data.get("status") != "passed" or data.get("failed") != []
            or not isinstance(passed, list) or not all(isinstance(item, str) for item in passed)
            or not REQUIRED.issubset(passed)):
        raise RuntimeError("Editor authoring assertions failed or required evidence is missing")
    return len(passed)


def main():
    parser = argparse.ArgumentParser(__doc__)
    parser.add_argument("--godot", required=True, type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    output = (args.output or Path(tempfile.mkdtemp(prefix="SpatialFabricGodotEditor-"))).resolve()
    if output == ROOT or ROOT in output.parents:
        raise RuntimeError("Editor validation output must be outside the source project")
    if args.output and output.exists() and any(output.iterdir()):
        raise RuntimeError("Choose an empty output directory; previous evidence is never replaced")
    output.mkdir(parents=True, exist_ok=True)
    project = output / "Project"
    prepare_project(ROOT, project)
    command = [str(args.godot.resolve()), "--headless", "--audio-driver", "Dummy", "--path", str(project), "--editor"]
    report = output / "editor-tests.json"
    for extra, name in ((["--import", "--quit"], "import.log"),
                        (["--", "--spatialfabric-authoring-report", str(report)], "editor.log")):
        log = output / name
        print("Running editor validation:", name, "Evidence:", output, flush=True)
        with log.open("w", encoding="utf-8") as stream:
            subprocess.run(command + extra, stdout=stream, stderr=subprocess.STDOUT, check=True, timeout=180)
        check_log(log.read_text(encoding="utf-8", errors="replace"))
    count = check_report(json.loads(report.read_text(encoding="utf-8")))
    print("Editor authoring checks:", count, "Clean shutdown. Evidence:", output)


if __name__ == "__main__":
    main()
