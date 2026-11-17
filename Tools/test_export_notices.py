import hashlib
import json
import shutil
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import export_notices
import export_windows

ROOT = Path(__file__).resolve().parents[1]


class ExportNoticeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / 'source'
        self.out = Path(self.temp.name) / 'runtime'
        shutil.copytree(ROOT / 'LICENSES', self.root / 'LICENSES')
        for name in ('LICENSE', 'Native/vendor/sf_audio/LICENSE.md'):
            target = self.root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / name, target)

    def bundle(self):
        return export_notices.bundle_notices(self.out, self.root)

    def test_complete_exact_allowlisted_bundle_and_hashes(self):
        (self.root / 'LICENSES/private-token.txt').write_text('must never ship')
        manifest = self.bundle()
        expected = set(export_notices.PINNED) | {'SpatialFabric-LICENSE.txt', 'sf_audio/LICENSE.md'}
        self.assertEqual(set(manifest['files']), expected)
        self.assertEqual({p.relative_to(self.out / 'LICENSES').as_posix()
                          for p in (self.out / 'LICENSES').rglob('*') if p.is_file()},
                         expected | {'PROVENANCE.json', 'README.txt'})
        for name, record in manifest['files'].items():
            data = (self.out / 'LICENSES' / name).read_bytes()
            self.assertEqual(hashlib.sha256(data).hexdigest(), record['sha256'])
        self.assertEqual((self.out / 'LICENSES/godot/COPYRIGHT.txt').read_bytes(),
                         (ROOT / 'LICENSES/godot/COPYRIGHT.txt').read_bytes())
        self.assertEqual(json.loads((self.out / 'LICENSES/PROVENANCE.json').read_text()), manifest)

    def test_deterministic_and_no_machine_paths(self):
        self.bundle()
        before = {p.relative_to(self.out): p.read_bytes() for p in self.out.rglob('*') if p.is_file()}
        self.bundle()
        after = {p.relative_to(self.out): p.read_bytes() for p in self.out.rglob('*') if p.is_file()}
        self.assertEqual(before, after)
        manifest = (self.out / 'LICENSES/PROVENANCE.json').read_text()
        self.assertNotIn(str(self.root), manifest)
        for name in export_notices.PINNED:
            self.assertRegex(json.loads(manifest)['files'][name]['url'],
                             r'^https://raw\.githubusercontent\.com/godotengine/[^/]+/[0-9a-f]{40}/')

    def test_missing_notices_fail_without_partial_bundle(self):
        for name in ('LICENSES/godot/LICENSE.txt', 'LICENSES/godot/COPYRIGHT.txt',
                     'LICENSES/godot-cpp/LICENSE.md', 'LICENSES/PROVENANCE.json',
                     'LICENSE', 'Native/vendor/sf_audio/LICENSE.md'):
            with self.subTest(name=name):
                source = self.root / name
                data = source.read_bytes()
                source.unlink()
                with self.assertRaisesRegex(SystemExit, 'Required release license notices unavailable or invalid'):
                    self.bundle()
                self.assertFalse(self.out.exists())
                source.write_bytes(data)

    def test_tampered_notices_fail(self):
        for name in export_notices.PINNED:
            with self.subTest(name=name):
                source = self.root / 'LICENSES' / name
                data = source.read_bytes()
                source.write_bytes(data + b'changed')
                with self.assertRaisesRegex(SystemExit, 'notice hash mismatch'):
                    self.bundle()
                source.write_bytes(data)
        self.assertFalse(self.out.exists())

    def test_empty_native_license_fails(self):
        (self.root / 'Native/vendor/sf_audio/LICENSE.md').write_bytes(b'\n')
        with self.assertRaisesRegex(SystemExit, 'empty license'):
            self.bundle()
        self.assertFalse(self.out.exists())

    def test_unexpected_inventory_fails(self):
        source = self.root / 'LICENSES/PROVENANCE.json'
        manifest = json.loads(source.read_text())
        manifest['files']['../secret'] = {}
        source.write_text(json.dumps(manifest))
        with self.assertRaisesRegex(SystemExit, 'unexpected pinned notice inventory'):
            self.bundle()
        self.assertFalse(self.out.exists())

    def test_binding_build_license_must_match_if_present(self):
        binding = self.root / 'Native/.deps/godot-cpp/LICENSE.md'
        binding.parent.mkdir(parents=True)
        binding.write_bytes(b'different license')
        with self.assertRaisesRegex(SystemExit, 'build checkout license differs'):
            self.bundle()
        binding.write_bytes((self.root / 'LICENSES/godot-cpp/LICENSE.md').read_bytes())
        self.bundle()

    def test_engine_version_gate(self):
        export_notices.verify_engine_notices('4.7.2-stable (official)')
        for version in ('4.7.1-stable (official)', '4.7.2-stable (custom_build)', ''):
            with self.subTest(version=version), self.assertRaisesRegex(SystemExit, 'pin and review matching official engine notices'):
                export_notices.verify_engine_notices(version)

    def test_export_fails_before_godot_when_notice_missing(self):
        dll = self.root / 'addons/spatial_fabric/bin/spatialfabric_native.windows.template_release.x86_64.dll'
        dll.parent.mkdir(parents=True)
        dll.write_bytes(b'test stub, never executed')
        (self.root / 'addons/spatial_fabric/plugin.cfg').write_text('version="0.2.0"\n')
        (self.root / 'LICENSES/godot/COPYRIGHT.txt').unlink()
        with patch.object(export_windows, 'ROOT', self.root), \
                patch.object(export_windows, 'bundle_notices', side_effect=lambda folder: export_notices.bundle_notices(folder, self.root)), \
                patch('sys.argv', ['export_windows.py', '--godot', 'must-not-run.exe', '--output', str(self.out)]), \
                patch.object(export_windows.subprocess, 'run') as run:
            with self.assertRaisesRegex(SystemExit, 'Required release license notices unavailable or invalid'):
                export_windows.main()
            run.assert_not_called()


if __name__ == '__main__':
    unittest.main()
