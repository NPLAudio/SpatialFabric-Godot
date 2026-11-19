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
    "central lists unconfigured ordinary and hidden nodes",
    "central path filter includes hidden nodes",
    "central accepts parent Scene Tree selection",
    "central single add creates typed owned child",
    "central attachment matches inactive defaults without replacing parent behavior",
    "central edits typed exported NodePath arrays",
    "central rejects wrong exported property types",
    "central creation Undo retains child lifetime",
    "central creation redo restores ownership",
    "central bulk Undo only removes newly added children",
    "central repeated attachment is duplicate safe",
    "central discarded creation redo frees detached child",
    "central mixed values retained until authored",
    "central bulk property edit uses real exported property",
    "central property Undo restores distinct mixed originals",
    "central removal redo detaches without freeing early",
    "central inactive attachment never starts audio capture or network",
    "central attachment does not auto-enroll network manager",
    "central SF property and child ownership persist after save reload",
    "central rejects external packed mutation",
    "central rejects protected inherited scene mutation",
    "central permits ordinary unsaved scenes",
    "central rejects unsaved inherited scene mutation",
    "central numeric export creates SpinBox",
    "central numeric focus loss retains raw invalid draft",
    "central focus loss cannot clamp invalid input into accepted edit",
    "central integer focus loss cannot round fractional draft into accepted edit",
    "central enum UI displays export labels",
    "central invalid enum rejects atomically",
    "central typed out of range edit rejects all targets",
    "central semantic min max validates every target atomically",
    "central replay permits longer than one hour",
    "central file picker drafts apply via typed helper",
    "central node arrays compute paths relative to each real component",
    "central node array UI conversion resolves correct nodes",
    "central stale node array selection rejects all targets",
    "central single NodePath computes per target relative paths",
    "central mixed vector edit preserves untouched per target axes",
    "central unrelated history retains bound draft and property",
    "central Apply retains property key",
    "central target set change cancels draft visibly",
    "central reversed A B C removal Undo restores ascending original siblings",
    "central debounced filter retains draft without scene refresh",
    "central metadata range honors or_lesser without invented lower cap",
    "central typed dock has vertical scrolling",
    "central numeric step signal remains authorable after raw text",
    "central scene switch cannot leak pending draft",
    "routing accepts actual Godot native JSON array schema",
    "routing cache reload never claims online",
    "routing stale failed refresh preserves disk and marks offline",
    "routing missing interface preserves offline history",
    "routing construction refresh and selectors never implicitly enumerate",
    "routing explicit Refresh Interfaces invokes inventory once",
    "routing dedicated grid tab preserves Scene Objects and CSV",
    "routing route Undo restores both original properties",
    "routing route Redo restores both configured properties",
    "routing real interface dropdown signal does not clamp channel",
    "routing real channel dropdown signal authors first source destination",
    "routing route survives PackedScene reload",
    "routing fresh guard rejects active playback",
    "routing fresh guard rejects pending replay",
    "routing fresh guard rejects starting worker",
    "routing fresh guard rejects foreign transient cue",
    "routing fresh guard rejects external packed content",
    "routing native viewport mouse dispatch reaches crosspoint",
    "routing clipped viewport rejects outside clicks",
    "routing mouse release revalidates live guard after press",
    "routing unknown endpoint exposes Auto and stored channel without fabricated capacity",
    "routing large matrix uses compact groups and constant native control count",
    "routing both axes scroll with independent clipped sticky headers",
    "routing entire UI lifecycle never prepares plays captures or polls inventory",
    "routing incoming inventory bound counts UTF8 bytes and preserves history",
    "routing CSV draft preserves grid channels above 256",
    "routing unrelated CSV draft edit preserves stored grid channel",
    "routing CSV draft Undo preserves original high channel",
    "routing high grid channel survives CSV roundtrip",
    "routing rejects channels beyond native int32 without changing stored route",
    "routing native wheel at boundary propagates to ancestor",
    "routing native wheel with movement is consumed before ancestor",
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
