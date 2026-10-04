import copy
import json
from pathlib import Path
import plistlib
import re
import tempfile
import unittest
from native_release_preflight import validate


class NativePreflightTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.config = dict(environment='staging', projectId='attendus-staging', applicationId='com.attendus.ownedstage', associatedDomain='stage.attendus.app', messagingSenderId='925344893088', mapsApiKey='AIza'+'A'*35, serviceConfigPath='service.json', playAppSigningSha256=':'.join(f'{i:02X}' for i in range(32)), appCheckProvider='playIntegrity')
        self.service = dict(project_info=dict(project_id='attendus-staging', project_number='925344893088', storage_bucket='attendus-staging.firebasestorage.app'), client=[dict(client_info=dict(android_client_info=dict(package_name=self.config['applicationId']), mobilesdk_app_id='1:925344893088:android:abcdef'), api_key=[dict(current_key='AIza'+'B'*35)], oauth_client=[dict(client_type=3,client_id='925344893088-abc.apps.googleusercontent.com')])])

    def run_android(self, config=None, service=None):
        (self.root/'service.json').write_text(json.dumps(service or self.service))
        return validate(config or self.config, 'android', self.root)

    def test_matching_staging_configuration(self):
        manifest, defines = self.run_android()
        self.assertEqual(manifest['projectId'], 'attendus-staging')
        self.assertNotIn('mapsApiKey', manifest)
        self.assertEqual(defines['ATTENDUS_NATIVE_APPLICATION_ID'], self.config['applicationId'])

    def test_cross_environment_and_missing_configuration(self):
        for field, bad in [('projectId','orgami-66nxok'),('applicationId','com.stormdeve.orgami'),('associatedDomain','attendus.app'),('mapsApiKey','placeholder'),('messagingSenderId','1'),('appCheckProvider','debug'),('playAppSigningSha256', 'AA:'*31+'AA')]:
            with self.subTest(field=field), self.assertRaises(ValueError):
                self.run_android(dict(self.config, **{field:bad}))

    def test_wrong_service_and_missing_oauth(self):
        for mutation in ['project', 'oauth', 'bucket', 'duplicate']:
            data = copy.deepcopy(self.service)
            if mutation=='project': data['project_info']['project_id']='orgami-66nxok'
            if mutation=='bucket': data['project_info']['storage_bucket']='orgami-66nxok.appspot.com'
            if mutation=='oauth': data['client'][0]['oauth_client']=[]
            if mutation=='duplicate': data['client']*=2
            with self.subTest(mutation=mutation), self.assertRaises(ValueError):
                self.run_android(service=data)

    def test_ios_oauth_and_project_validation(self):
        config = dict(self.config, serviceConfigPath='service.plist', appleTeamId='ABC123DEF4', appCheckProvider='deviceCheck')
        data = dict(PROJECT_ID=config['projectId'], GCM_SENDER_ID=config['messagingSenderId'], BUNDLE_ID=config['applicationId'], GOOGLE_APP_ID='1:925344893088:ios:abcdef', API_KEY='AIza'+'B'*35, STORAGE_BUCKET='attendus-staging.firebasestorage.app', CLIENT_ID='925344893088-abc.apps.googleusercontent.com',REVERSED_CLIENT_ID='com.googleusercontent.apps.925344893088-abc')
        (self.root/'service.plist').write_bytes(plistlib.dumps(data))
        validate(config,'ios',self.root)
        data['REVERSED_CLIENT_ID']='com.wrong'
        (self.root/'service.plist').write_bytes(plistlib.dumps(data))
        with self.assertRaises(ValueError): validate(config,'ios',self.root)

    def test_native_boot_permission_contract(self):
        repo = Path(__file__).resolve().parent.parent
        android=(repo/'android/app/src/main/AndroidManifest.xml').read_text()
        self.assertIn('firebase_messaging_auto_init_enabled" android:value="false"',android)
        for unsupported in ['USE_BIOMETRIC','android.permission.NFC','FOREGROUND_SERVICE_LOCATION']:
            self.assertNotIn(unsupported,android)
        ios=plistlib.loads((repo/'ios/Runner/Info.plist').read_bytes())
        self.assertFalse(ios['FirebaseMessagingAutoInitEnabled'])
        self.assertNotIn('NFCReaderUsageDescription',ios)

    def test_android_uses_the_supported_native_dependency_repositories(self):
        repo = Path(__file__).resolve().parent.parent
        for name in ['build.gradle', 'settings.gradle']:
            with self.subTest(name=name):
                source = (repo/'android'/name).read_text()
                self.assertNotIn('maven.stripe.com', source)
                self.assertIn('google()', source)
                self.assertIn('mavenCentral()', source)

    def test_ios_camera_and_foreground_location_permission_build_contract(self):
        repo = Path(__file__).resolve().parent.parent
        podfile = (repo/'ios/Podfile').read_text()
        ios = plistlib.loads((repo/'ios/Runner/Info.plist').read_bytes())
        self.assertRegex(podfile, r"'permission_handler_apple'\s*=>\s*\['PERMISSION_CAMERA=1'\]")
        self.assertRegex(podfile, r"'geolocator_apple'\s*=>\s*\['BYPASS_PERMISSION_LOCATION_ALWAYS=1'\]")
        self.assertIn("config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] = definitions", podfile)
        self.assertTrue(ios['NSCameraUsageDescription'])
        self.assertTrue(ios['NSLocationWhenInUseUsageDescription'])
        self.assertNotIn('NSLocationAlwaysAndWhenInUseUsageDescription', ios)
        self.assertNotIn('NSLocationAlwaysUsageDescription', ios)
        self.assertNotIn('location', ios.get('UIBackgroundModes', []))
        for unsupported in ["'PERMISSION_MICROPHONE=1'", "'PERMISSION_LOCATION_ALWAYS=1'", "'PERMISSION_LOCATION=1'"]:
            self.assertNotIn(unsupported, podfile)

    def test_ios_application_privacy_manifest_is_bundled(self):
        repo = Path(__file__).resolve().parent.parent
        project = (repo/'ios/Runner.xcodeproj/project.pbxproj').read_text()
        privacy = plistlib.loads((repo/'ios/Runner/PrivacyInfo.xcprivacy').read_bytes())
        self.assertIs(privacy['NSPrivacyTracking'], False)
        self.assertTrue(privacy['NSPrivacyAccessedAPITypes'])
        resource_phase = re.search(r'97C146EC1CF9000F007C117D /\* Resources \*/ = \{(.*?)\};', project, re.S).group(1)
        build_id = re.search(r'([A-F0-9]{24}) /\* PrivacyInfo.xcprivacy in Resources \*/,', resource_phase).group(1)
        build_file = re.search(build_id + r' /\* PrivacyInfo.xcprivacy in Resources \*/ = \{(.*?)\};', project).group(1)
        reference_id = re.search(r'fileRef = ([A-F0-9]{24})', build_file).group(1)
        self.assertRegex(project, reference_id + r' /\* PrivacyInfo.xcprivacy \*/ = \{isa = PBXFileReference;[^}]*path = PrivacyInfo.xcprivacy;')


if __name__ == '__main__': unittest.main()
