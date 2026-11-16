"""Local real-Godot gate. Requires nonempty passing evidence, never just exit zero."""
import argparse, json, subprocess, tempfile
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
def main():
    p=argparse.ArgumentParser();p.add_argument('--godot',required=True,type=Path);p.add_argument('--output',type=Path);p.add_argument('--require-native',action='store_true');args=p.parse_args()
    out=(args.output or Path(tempfile.mkdtemp(prefix='SpatialFabricGodotChecks-'))).resolve();out.mkdir(parents=True,exist_ok=True)
    command=[str(args.godot.resolve()),'--headless','--audio-driver','Dummy','--path',str(ROOT)]
    def run(extra,name):
        with (out/name).open('w',encoding='utf-8') as log: subprocess.run(command+extra,stdout=log,stderr=subprocess.STDOUT,check=True,timeout=120)
        text=(out/name).read_text(errors='replace')
        if 'ERROR:' in text or 'Parse Error:' in text or 'Unicode parsing error' in text or 'WARNING:' in text: raise SystemExit('Godot script/import error; inspect '+str(out/name))
    run(['--editor','--import','--quit'],'import.log')
    report=out/'tests.json';report.unlink(missing_ok=True)
    run(['--script','res://Tests/Godot/run_tests.gd','--',str(report)]+(['--require-native'] if args.require_native else []),'tests.log')
    data=json.loads(report.read_text());assert data['status']=='passed' and data['passed'] and not data['failed'],data
    print('Godot checks:',len(data['passed']),'Evidence:',out)
if __name__=='__main__':main()
