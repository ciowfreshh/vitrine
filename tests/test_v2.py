import hashlib,importlib.util,json,pathlib,plistlib,re,struct,subprocess,sys,tempfile,unittest,zipfile
ROOT=pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'scripts'))
import localization
class LocalizationTests(unittest.TestCase):
    def test_catalog_arguments_and_generated_header(self):
        catalog,generated=localization.compile_catalog()
        self.assertGreater(len(catalog),1500)
        self.assertEqual((ROOT/'tweak/Sources/Core/SGUICatalog.inc').read_text(),generated)
        self.assertEqual(catalog['Lyrics'],'Lời bài hát')
        self.assertIn('Neural Engine',catalog['Karaoke runs on the Neural Engine.'])
    def test_objective_c_concatenation_unicode_and_character_literals(self):
        source='char c = \'"\'; NSString *s = @"One " "two " @"three"; // @"ignore"\n'
        self.assertEqual([key for _,key in localization.literals(source)],['One two three'])
        self.assertEqual(localization.decode('Tiếng Việt\\n"'), 'Tiếng Việt\n"')
    def test_inventory_detects_new_ui(self):
        path=ROOT/'tweak/Sources/App/LocalizationRegressionProbe.m'
        try:
            path.write_text('void probe(void) { id s = @"A newly added untranslated warning"; }\n')
            run=subprocess.run([sys.executable,str(ROOT/'scripts/localization.py')],capture_output=True,text=True)
            self.assertNotEqual(run.returncode,0)
            self.assertIn('A newly added untranslated warning',run.stderr)
        finally:path.unlink(missing_ok=True)
    def test_format_mismatch_detected(self):
        self.assertNotEqual(localization.signature('%lu of %lu'),localization.signature('%@ trên %lu'))
        self.assertEqual(localization.signature('100% is a percentage.'),[])
    def test_existing_catalog_key_cannot_bypass_localizer(self):
        path=ROOT/'tweak/Sources/App/LocalizationRegressionProbe.m'
        try:
            path.write_text('void probe(void) { id s = @"Lyrics"; }\n')
            run=subprocess.run([sys.executable,str(ROOT/'scripts/localization.py')],capture_output=True,text=True)
            self.assertNotEqual(run.returncode,0)
            self.assertIn('bypasses localization',run.stderr)
        finally:path.unlink(missing_ok=True)
    def test_swift_ui_is_included_in_inventory(self):
        path=ROOT/'extension/LiveActivity/LocalizationRegressionProbe.swift'
        try:
            path.write_text('let label = Text("A new untranslated widget label")\n')
            run=subprocess.run([sys.executable,str(ROOT/'scripts/localization.py')],capture_output=True,text=True)
            self.assertNotEqual(run.returncode,0)
            self.assertIn('A new untranslated widget label',run.stderr)
        finally:path.unlink(missing_ok=True)
    def test_localized_labels_do_not_become_api_tokens(self):
        source=(ROOT/'tweak/Sources/Shared/LyricsTranslation/LyricsTranslation.m').read_text()
        self.assertNotIn('setObject:thinkingLevels[index]',source)
        self.assertIn('setObject:@[@"low", @"medium", @"high"][index] forKey:SGKeyAIThinking',source)
    def test_vitrine_tables_do_not_overwrite_spotify(self):
        spec=importlib.util.spec_from_file_location('tables',ROOT/'scripts/install-localizations.py');module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
        tables=module.resources()
        self.assertEqual(set(tables),{f'{lang}.lproj/{name}.strings' for lang in ('en','vi') for name in ('Vitrine','AppShortcuts')})
        self.assertIn('Lời bài hát',tables['vi.lproj/Vitrine.strings'].decode())
    def test_shortcuts_phrases_and_placeholders(self):
        phrases=json.loads((ROOT/'localization/app-shortcuts.json').read_text())
        source=(ROOT/'tweak/Sources/Shared/LiveActivity/AppShortcuts.swift').read_text()
        actual=[]
        for _,key in localization.swift_literals(source):
            if r'\(.applicationName)' in key:
                actual.append(re.sub(r'\\\(\\\.\$(\w+)\)',r'${\1}',key.replace(r'\(.applicationName)','${applicationName}')))
        self.assertEqual(set(actual),set(phrases))
        for key,value in phrases.items():
            self.assertEqual(sorted(re.findall(r'\$\{\w+\}',key)),sorted(re.findall(r'\$\{\w+\}',value)))
            self.assertNotEqual(key,value)
    def test_install_preserves_existing_spotify_resource_entries(self):
        spec=importlib.util.spec_from_file_location('tables',ROOT/'scripts/install-localizations.py');module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
        with tempfile.TemporaryDirectory() as tmp:
            path=pathlib.Path(tmp)/'test.ipa';app='Payload/Spotify.app/'
            with zipfile.ZipFile(path,'w') as z:
                z.writestr(app+'SpotifyData',b'unchanged binary')
                z.writestr(app+'vi.lproj/AppShortcuts.strings',plistlib.dumps({'Spotify-owned':'Giữ nguyên'},fmt=plistlib.FMT_BINARY))
            module.install(path,app)
            with zipfile.ZipFile(path) as z:
                self.assertIsNone(z.testzip())
                self.assertEqual(z.read(app+'SpotifyData'),b'unchanged binary')
                existing=plistlib.loads(z.read(app+'vi.lproj/AppShortcuts.strings'))
                self.assertEqual(existing['Spotify-owned'],'Giữ nguyên')
                self.assertEqual(existing['Play or pause ${applicationName}'],'Phát hoặc tạm dừng ${applicationName}')
    def test_upstream_contract(self):
        contract=json.loads((ROOT/'tests/upstream-contract.json').read_text())
        for relative,expected in contract['unchanged_files'].items():
            self.assertEqual(hashlib.sha256((ROOT/relative).read_bytes()).hexdigest(),expected,relative)
        source=(ROOT/'tweak/Sources/Shared/LyricsTranslation/LyricsTranslation.m').read_text()
        for fragment in contract['translation_instructions']:
            self.assertIn(fragment,source)
    def test_no_eviction_and_durable_path(self):
        source=(ROOT/'tweak/Sources/Shared/LyricsTranslation/SavedTranslations.m').read_text()
        self.assertNotIn('kKept',source)
        self.assertIn('NSApplicationSupportDirectory',source)
        self.assertIn('legacyDirectory:',source)
        store=(ROOT/'tweak/Sources/Core/TranslationStore/SGTranslationStore.m').read_text()
        self.assertIn('PRAGMA synchronous=FULL',store)
        self.assertIn('PRIMARY KEY(track,language)',store)
        self.assertNotIn('LIMIT 200',store)
    def test_workflow_does_not_interpolate_untrusted_url_into_shell(self):
        workflow=(ROOT/'.github/workflows/vitrine-v2.yml').read_text()
        self.assertNotIn('curl -fsSL "${{',workflow)
        self.assertIn('IPA_URL: ${{ inputs.ipa_url }}',workflow)
    def test_ipa_validator_rejects_changed_input_hash(self):
        with tempfile.TemporaryDirectory() as tmp:
            path=pathlib.Path(tmp)/'input.ipa'
            with zipfile.ZipFile(path,'w') as z:
                z.writestr('Payload/Spotify.app/Info.plist',plistlib.dumps({'CFBundleIdentifier':'com.spotify.client','CFBundleExecutable':'Spotify'}))
                z.writestr('Payload/Spotify.app/Spotify',struct.pack('<8I',0xfeedfacf,0x100000c,0,2,0,0,0,0))
            command=[sys.executable,str(ROOT/'scripts/validate-v2-ipa.py'),str(path),'--sha256']
            good=subprocess.run(command+[hashlib.sha256(path.read_bytes()).hexdigest()],capture_output=True,text=True)
            self.assertEqual(good.returncode,0,good.stderr)
            bad=subprocess.run(command+['0'*64],capture_output=True,text=True)
            self.assertNotEqual(bad.returncode,0)
            self.assertIn('does not match',bad.stderr)
if __name__=='__main__':unittest.main()
