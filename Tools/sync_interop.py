"""Explicit fixture vendoring. Runtime never needs a sibling repository."""
import argparse, hashlib, json
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
SOURCES = ['Fixtures/osc-v1.json', 'Fixtures/coordinates-v1.json', 'Fixtures/custom-v1.json', 'Fixtures/ack-v1.json', 'Schemas/scene-v1.schema.json', 'Specs/OSC-v1.md']
def main():
    p = argparse.ArgumentParser(); p.add_argument('--source', type=Path, default=ROOT.parent/'SpatialFabric'); p.add_argument('--check', action='store_true'); args = p.parse_args()
    target = ROOT/'Tests/Fixtures'; hashes = {}
    for name in SOURCES:
        data = (args.source/name).read_bytes(); hashes[name] = hashlib.sha256(data).hexdigest()
        path = target/Path(name).name
        if args.check:
            if not path.is_file() or path.read_bytes() != data: raise SystemExit('Fixture drift: '+name)
        else:
            target.mkdir(parents=True, exist_ok=True); path.write_bytes(data)
    manifest = {'repository': 'https://github.com/NPLAudio/SpatialFabric', 'sha256': hashes}
    data = (json.dumps(manifest, indent=2)+'\n').encode('utf-8'); path = target/'PROVENANCE.json'
    if args.check:
        if path.read_bytes() != data: raise SystemExit('Provenance drift')
    else: path.write_bytes(data)
    print('Interop fixture bytes/provenance verified' if args.check else 'Interop fixtures vendored')
if __name__ == '__main__': main()
