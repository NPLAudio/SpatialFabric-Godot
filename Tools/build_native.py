"""Build the GDExtension (Windows x64 or macOS universal). Close the Godot editor first.
godot-cpp is fetched at a pinned tag into the ignored Native/.deps; it is never vendored."""
import argparse, platform, subprocess, sys
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]; TAG = 'godot-4.5-stable'; DEPS = ROOT/'Native/.deps/godot-cpp'
def run(cmd, cwd): print('+', ' '.join(map(str, cmd)), flush=True); subprocess.run(cmd, cwd=cwd, check=True)
def main():
    p = argparse.ArgumentParser(); p.add_argument('--targets', nargs='+', default=['template_debug', 'template_release']); a = p.parse_args()
    if not DEPS.exists(): run(['git', 'clone', '--depth', '1', '-b', TAG, 'https://github.com/godotengine/godot-cpp.git', str(DEPS)], ROOT)
    try: import SCons  # noqa: F401
    except ImportError: sys.exit('Install SCons first: python -m pip install scons')
    system = 'windows' if platform.system() == 'Windows' else 'macos' if platform.system() == 'Darwin' else None
    if system is None: sys.exit('Direct-device audio is implemented only for Windows and macOS.')
    arch = ['arch=x86_64'] if system == 'windows' else ['arch=universal']
    for target in a.targets: run([sys.executable, '-m', 'SCons', f'platform={system}', f'target={target}', '-j8'] + arch, ROOT/'Native/gdextension')
    print('Native extension built under addons/spatial_fabric/bin (ignored by Git).')
if __name__ == '__main__': main()
