"""Offline, allowlisted license bundle for the supported Windows release export."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ENGINE = '4.7.2-stable (official)'
PINNED = ('godot/LICENSE.txt', 'godot/COPYRIGHT.txt', 'godot-cpp/LICENSE.md')


def verify_engine_notices(engine):
    if engine != ENGINE:
        raise SystemExit(f'License notices support {ENGINE}, not {engine!r}; pin and review matching official engine notices before packaging')


def bundle_notices(folder, root=ROOT):
    """Validate all inputs before writing; never scan/copy arbitrary engine or deps folders."""
    base = root / 'LICENSES'
    try:
        provenance = json.loads((base / 'PROVENANCE.json').read_text(encoding='utf-8'))
        if (provenance['engine'] != ENGINE or provenance['godot_tag'] != '4.7.2-stable'
                or provenance['godot_cpp_tag'] != 'godot-4.5-stable'
                or set(provenance['files']) != set(PINNED)):
            raise ValueError('unexpected pinned notice inventory or engine version')
        files = {}
        records = {}
        for name in PINNED:
            data = (base / name).read_bytes()
            record = provenance['files'][name]
            if not data.strip() or hashlib.sha256(data).hexdigest() != record['sha256']:
                raise ValueError(f'notice hash mismatch: {name}')
            files[name] = data
            records[name] = record
        # The native extension compiles sf_audio and links godot-cpp; OS APIs are system libraries.
        for name, source in [('SpatialFabric-LICENSE.txt', root / 'LICENSE'),
                             ('sf_audio/LICENSE.md', root / 'Native/vendor/sf_audio/LICENSE.md')]:
            data = source.read_bytes()
            if not data.strip():
                raise ValueError(f'empty license: {source.relative_to(root)}')
            files[name] = data
            records[name] = {'source': source.relative_to(root).as_posix(),
                             'sha256': hashlib.sha256(data).hexdigest()}
        # If the build checkout is present, do not silently ship a different binding license.
        binding = root / 'Native/.deps/godot-cpp/LICENSE.md'
        if binding.exists() and binding.read_bytes() != files['godot-cpp/LICENSE.md']:
            raise ValueError('godot-cpp build checkout license differs from pinned notice')
    except (OSError, ValueError, KeyError, TypeError) as exc:
        raise SystemExit(f'Required release license notices unavailable or invalid: {exc}. Restore LICENSES/ pinned notices and native/project licenses before exporting.') from exc

    manifest = {'engine': ENGINE, 'godot_tag': provenance['godot_tag'],
                'godot_cpp_tag': provenance['godot_cpp_tag'], 'files': records}
    target = folder / 'LICENSES'
    for name, data in sorted(files.items()):
        path = target / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    (target / 'PROVENANCE.json').write_text(json.dumps(manifest, indent=2, sort_keys=True) + '\n', encoding='utf-8', newline='\n')
    (target / 'README.txt').write_text(
        'Runtime license notices (keep this directory with the application).\n'
        'SpatialFabric and native sf_audio: MIT; godot-cpp: MIT.\n'
        'godot/LICENSE.txt: Godot engine license.\n'
        'godot/COPYRIGHT.txt: full engine third-party copyright and license texts,\n'
        'including components that may not be enabled in this Windows template.\n'
        'PROVENANCE.json records pinned upstream sources and SHA-256 hashes.\n', encoding='utf-8', newline='\n')
    return manifest
