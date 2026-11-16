"""Vendor/verify the direct-device C ABI source from SpatialFabric-Unity with SHA-256 provenance.
The Godot repo builds from its own vendored copy; no sibling checkout is needed to build."""
import argparse
import hashlib
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FILES = {
    'include/spatialfabric_audio.h': 'spatialfabric_audio.h',
    'src/audio.cpp': 'src/audio.cpp',
    'src/pcm.h': 'src/pcm.h',
    'src/core_audio.inc': 'src/core_audio.inc',
}
CRLF = bytes([13, 10])
LF = bytes([10])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', type=Path, default=ROOT.parent / 'SpatialFabric-Unity')
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    target = ROOT / 'Native/vendor/sf_audio'
    manifest = target / 'PROVENANCE.json'
    if args.check:
        recorded = json.loads(manifest.read_text())
        for name, digest in recorded['sha256'].items():
            if hashlib.sha256((target / name).read_bytes()).hexdigest() != digest:
                raise SystemExit('Vendored native source drift: ' + name)
        print('Vendored native source hashes verified')
        return
    commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=args.source, text=True).strip()
    hashes = {}
    for src, dst in FILES.items():
        data = (args.source / 'Native' / src).read_bytes().replace(CRLF, LF)
        (target / dst).parent.mkdir(parents=True, exist_ok=True)
        (target / dst).write_bytes(data)
        hashes[dst] = hashlib.sha256(data).hexdigest()
    manifest.write_text(json.dumps({'source': 'https://github.com/NPLAudio/SpatialFabric-Unity', 'commit': commit, 'license': 'MIT', 'sha256': hashes}, indent=2) + '\n')
    print('Vendored native source at', commit)


if __name__ == '__main__':
    main()
