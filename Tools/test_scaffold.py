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
    def test_vendored_native_source_and_audio_provenance(self):
        base=ROOT/'Native/vendor/sf_audio';recorded=json.loads((base/'PROVENANCE.json').read_text());self.assertEqual(len(recorded['commit']),40)
        for name,sha in recorded['sha256'].items():self.assertEqual(hashlib.sha256((base/name).read_bytes()).hexdigest(),sha,name)
        audio=json.loads((ROOT/'examples/four_rooms/audio/PROVENANCE.json').read_text())
        for name,sha in audio['sha256'].items():self.assertEqual(hashlib.sha256((ROOT/'examples/four_rooms/audio'/name).read_bytes()).hexdigest(),sha,name)
    def test_native_binaries_and_deps_are_not_source(self):
        ignore=(ROOT/'.gitignore').read_text();self.assertIn('.deps/',ignore);self.assertIn('addons/spatial_fabric/bin/',ignore);self.assertTrue((ROOT/'Native/.gdignore').is_file())
    def test_extension_is_not_hot_reloaded_and_never_uses_godot_mixer(self):
        cfg=(ROOT/'addons/spatial_fabric/spatialfabric_native.gdextension').read_text();self.assertIn('reloadable = false',cfg)
        source=(ROOT/'Native/gdextension/src/spatialfabric_native.cpp').read_text();self.assertNotIn('AudioServer::',source);self.assertNotIn('AudioServer.get_singleton',source)
if __name__=='__main__':unittest.main()
