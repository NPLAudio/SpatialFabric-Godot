"""Export, verify and package the Godot four-room example as a Windows x64 release build.

Needs the Godot 4.7.2 editor with Windows export templates (a self-contained portable editor works) and the
RELEASE native library (python Tools/build_native.py --targets template_release). Silent verification only:
a headless self-check (native extension loaded, inventory, nothing listening/playing at startup) and a windowed
screenshot from the exported build. Never plays audio. The output directory must be new or empty.
"""
import argparse, hashlib, json, shutil, subprocess, zipfile
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
NAME = 'SpatialFabricRoomShowcase'


def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    p = argparse.ArgumentParser(); p.add_argument('--godot', required=True, type=Path, help='Godot console executable (with export templates installed)')
    p.add_argument('--output', required=True, type=Path); args = p.parse_args()
    out = args.output.resolve()
    if out.exists() and any(out.iterdir()): raise SystemExit('Output must be new or empty')
    release_dll = ROOT / 'addons/spatial_fabric/bin/spatialfabric_native.windows.template_release.x86_64.dll'
    if not release_dll.is_file(): raise SystemExit('Build the release native library first: python Tools/build_native.py --targets template_release')
    for stray in (ROOT / 'addons/spatial_fabric/bin').glob('~*'): stray.unlink()   # editor hot-reload copies must never ship
    version = json.loads(json.dumps({'v': next(l for l in (ROOT / 'addons/spatial_fabric/plugin.cfg').read_text().splitlines() if l.startswith('version=')).split('"')[1]}))['v']
    name = f'{NAME}-Godot-{version}-Windows-x64'; folder = out / name; (out / 'evidence').mkdir(parents=True); folder.mkdir()
    def run(extra, log, timeout=600):
        with (out / 'evidence' / log).open('w', encoding='utf-8') as stream:
            return subprocess.run([str(args.godot), '--audio-driver', 'Dummy', '--path', str(ROOT)] + extra, stdout=stream, stderr=subprocess.STDOUT, timeout=timeout)
    if run(['--headless', '--editor', '--import', '--quit'], 'import.log').returncode: raise SystemExit('Godot import failed; see evidence/import.log')
    result = run(['--headless', '--export-release', 'Windows Desktop', str(folder / (NAME + '.exe'))], 'export.log')
    log = (out / 'evidence/export.log').read_text(errors='replace')
    if result.returncode or 'ERROR' in log.replace('ERROR: Cannot get class', ''): raise SystemExit('Export failed:\n' + log[-1500:])
    exe = folder / (NAME + '.exe'); pck = folder / (NAME + '.pck')
    libraries = sorted(p.name for p in folder.rglob('*.dll'))
    if not exe.is_file() or not pck.is_file() or not any('template_release' in n for n in libraries) or any('template_debug' in n or n.startswith('~') for n in libraries):
        raise SystemExit(f'Unexpected export contents: exe={exe.is_file()} pck={pck.is_file()} dlls={libraries}')
    # Exported-build self-check, headless then windowed with a rendered screenshot.
    console = folder / (NAME + '.console.exe')
    runner = console if console.is_file() else exe
    check = out / 'evidence/selfcheck.json'
    subprocess.run([str(runner), '--headless', '--audio-driver', 'Dummy', '--', '--sf-selfcheck', str(check)], check=True, timeout=120, capture_output=True)
    data = json.loads(check.read_text()); assert data['status'] == 'passed' and data['exported_template'], data
    # The exported build must really SEND ADM when OSC is switched on (the N key's code path): verify with a real receiver.
    import socket, threading, time
    sink = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); sink.bind(('127.0.0.1', 0)); sink.settimeout(0.05); adm_port = sink.getsockname()[1]
    seen, stop = set(), threading.Event()
    def listen():
        while not stop.is_set():
            try: packet, _ = sink.recvfrom(65535)
            except socket.timeout: continue
            seen.add(packet.split(b'\0', 1)[0].decode('ascii', 'replace'))
    thread = threading.Thread(target=listen, daemon=True); thread.start()
    osc = out / 'evidence/selfcheck-osc.json'
    subprocess.run([str(runner), '--headless', '--audio-driver', 'Dummy', '--', '--sf-selfcheck', str(osc), '--sf-osc', '--sf-adm-port', str(adm_port)], check=True, timeout=120, capture_output=True)
    time.sleep(0.3); stop.set(); thread.join(); sink.close()
    osc_data = json.loads(osc.read_text())
    expected = {f'/adm/obj/{i}/xyz' for i in (1, 2, 3, 4)}
    assert osc_data['osc_started'] and osc_data['adm_enabled_after_start'] and expected <= seen, (osc_data, sorted(seen))
    data['osc_output_verified'] = sorted(expected)
    shot, check2 = out / 'evidence/exported.png', out / 'evidence/selfcheck-windowed.json'
    subprocess.run([str(exe), '--audio-driver', 'Dummy', '--resolution', '1280x720', '--', '--sf-selfcheck', str(check2), '--sf-shot', str(shot)], check=True, timeout=120, capture_output=True)
    assert shot.is_file() and json.loads(check2.read_text())['status'] == 'passed'
    for source, target in [(ROOT / 'README.md', 'README.md'), (ROOT / 'LICENSE', 'LICENSE'), (ROOT / 'examples/four_rooms/audio/PROVENANCE.json', 'AUDIO_PROVENANCE.json')]:
        if source.is_file(): shutil.copy2(source, folder / target)
    (folder / 'RUNNING.txt').write_text('SpatialFabric Godot four-room example (Windows x64, release export, unsigned).\n\nKeep every file in this folder together (the .pck and the native .dll are required).\n'
        'Run SpatialFabricRoomShowcase.exe. Nothing plays or listens at startup. Click to capture the mouse; WASD walks; Esc releases.\n'
        'E plays the room cue THROUGH YOUR DEFAULT OUTPUT DEVICE; Q stops; X stops all; I starts LIVE INPUT (default microphone to default output: use headphones); N starts OSC.\n'
        'Windows microphone-permission and unsigned-app warnings are expected. Windows only: no macOS/Linux build.\n', encoding='utf-8')
    archive = out / (name + '.zip')
    with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED) as z:
        for item in sorted(folder.rglob('*')):
            if item.is_file(): z.write(item, item.relative_to(out))
    manifest = {'name': name, 'version': version, 'engine': data['engine'], 'native_release_dll_sha256': sha(release_dll), 'signed': False, 'files': sorted(str(p.relative_to(folder)) for p in folder.rglob('*') if p.is_file()),
                'selfcheck': data, 'archive': {'name': archive.name, 'bytes': archive.stat().st_size, 'sha256': sha(archive)}, 'exe_sha256': sha(exe), 'pck_sha256': sha(pck)}
    (out / 'BUILD_MANIFEST.json').write_text(json.dumps(manifest, indent=2) + '\n'); (out / 'SHA256SUMS.txt').write_text(f'{sha(archive)}  {archive.name}\n{sha(exe)}  {exe.name}\n{sha(pck)}  {pck.name}\n')
    print(json.dumps({k: manifest[k] for k in ('name', 'engine', 'files', 'archive', 'selfcheck')}, indent=2))


if __name__ == '__main__': main()
