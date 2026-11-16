import hashlib,json,re,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
class ScaffoldTests(unittest.TestCase):
    def test_vendored_fixture_hashes(self):
        base=ROOT/'Tests/Fixtures';p=json.loads((base/'PROVENANCE.json').read_text())
        for name,sha in p['sha256'].items():self.assertEqual(hashlib.sha256((base/Path(name).name).read_bytes()).hexdigest(),sha)
    def test_scene_keys_are_explicit_and_unique(self):
        scene=(ROOT/'examples/four_rooms/room_showcase.tscn').read_text();keys=re.findall(r'persistent_key = "([^"]+)"',scene)
        self.assertEqual(len(keys),9);self.assertEqual(len(set(keys)),9)
    def test_sockets_only_in_explicit_transport_and_no_audio_fallback(self):
        for path in (ROOT/'addons').rglob('*.gd'):
            text=path.read_text();self.assertNotIn('AudioStreamPlayer.new(',text);self.assertNotIn('UDPServer.new(',text)
            if path.name!='osc_transport.gd':self.assertNotIn('PacketPeerUDP.new(',text)
        manager=(ROOT/'addons/spatial_fabric/runtime/spatial_manager.gd').read_text()
        for hook in ('_ready','_enter_tree'):self.assertNotIn('func '+hook,manager)
    def test_no_github_actions(self):self.assertFalse((ROOT/'.github/workflows').exists())
    def test_project_and_plugin(self):
        self.assertIn('examples/four_rooms/room_showcase.tscn',(ROOT/'project.godot').read_text());self.assertTrue((ROOT/'addons/spatial_fabric/plugin.cfg').is_file())
    def test_links_and_honest_status(self):
        text=(ROOT/'README.md').read_text()
        for name in ['SpatialFabric','SpatialFabric-Unity','SpatialFabric-Interop','AudioLoom']:self.assertIn('https://github.com/NPLAudio/'+name,text)
        self.assertIn('not implemented',text);self.assertIn('-Z/X/Y',text)
if __name__=='__main__':unittest.main()
