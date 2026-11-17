# Release runtime notices

The portable Godot installation contains executables but no adjacent license files.
These unmodified notices were fetched from official, commit-pinned upstream sources:

- Godot **4.7.2-stable**, commit `ed1daf0bf001b61586d9930840f2f1394092c079`:
  `godot/LICENSE.txt` (engine MIT) and `godot/COPYRIGHT.txt` (full engine third-party
  attribution and license texts, conservatively including disabled components).
- godot-cpp **godot-4.5-stable**, commit `e83fd0904c13356ed1d4c3d09f8bb9132bdc6b77`:
  `godot-cpp/LICENSE.md` (MIT), matching `Tools/build_native.py`.

`PROVENANCE.json` records official raw URLs and exact SHA-256 hashes. The export tool
checks these bytes offline and bundles only this allowlist, the root project `LICENSE`,
and `Native/vendor/sf_audio/LICENSE.md`. The native build compiles sf_audio and links
godot-cpp plus Windows system APIs; no separate third-party native audio library is used.
An available godot-cpp build checkout must have the same license text. The bundle has
its own deterministic provenance manifest and is included in the release file inventory.
No engine installation directories, credentials, environment variables or arbitrary dependency
files are copied. Missing, empty or altered notices fail before any Godot process starts;
a different exported engine version fails before ZIP creation.

To update the supported engine/binding version, review official notices at the matching
immutable upstream commits, replace these files and hashes, and update the version gates
in `Tools/export_notices.py` alongside build/export documentation. Do not substitute an
HTML download page, an unrelated engine version, or a link-only attribution. Customized
engine templates or extra native dependencies require their own license review/notices.
Keep the complete generated `LICENSES/` directory with distributed runtime binaries.
