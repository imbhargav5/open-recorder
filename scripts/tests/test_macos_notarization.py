"""Exercise notarization gates without credentials or contacting Apple."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'notarize-macos-production-app.zsh'


class NotarizationTests(unittest.TestCase):
    def run_notary(self, mode, profile=True):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            app = root / 'Nightly.app'
            app.mkdir()
            commands = root / 'commands'
            xcrun = root / 'xcrun'
            xcrun.write_text('''#!/bin/zsh
print -r -- "$*" >> "$TEST_COMMANDS"
if [[ "$1 $2" == "notarytool submit" ]]; then
    if [[ "$TEST_MODE" == "failure" ]]; then exit 42; fi
    if [[ "$TEST_MODE" == "rejected" ]]; then
        print -r -- '{"status":"Invalid"}'
    else
        print -r -- '{"status":"Accepted"}'
    fi
fi
''')
            xcrun.chmod(0o755)
            spctl = root / 'spctl'
            spctl.write_text('#!/bin/zsh\nprint -r -- "gatekeeper" >> "$TEST_COMMANDS"\n')
            spctl.chmod(0o755)
            environment = {
                **os.environ,
                'PATH': str(root) + ':/usr/bin:/bin:/usr/sbin:/sbin',
                'TEST_COMMANDS': str(commands), 'TEST_MODE': mode,
                'NOTARYTOOL_MAX_ATTEMPTS': '2', 'NOTARYTOOL_RETRY_DELAY_SECONDS': '0',
                'OPEN_RECORDER_NOTARY_PROFILE': 'fixture-profile' if profile else '',
                'APPLE_ID': 'fixture@example.invalid',
                'APPLE_TEAM_ID': 'TESTTEAM', 'APPLE_APP_SPECIFIC_PASSWORD': 'fixture-only',
            }
            result = subprocess.run(['zsh', str(SCRIPT), str(app)], env=environment,
                                    capture_output=True, text=True)
            return result, commands.read_text()

    def test_failed_submission_preserves_exit_code_and_never_staples(self):
        result, commands = self.run_notary('failure')
        self.assertEqual(result.returncode, 42, result.stderr)
        self.assertEqual(commands.count('notarytool submit'), 2)
        self.assertNotIn('stapler', commands)
        self.assertNotIn('gatekeeper', commands)

    def test_rejected_submission_with_zero_exit_code_never_staples(self):
        result, commands = self.run_notary('rejected')
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('stapler', commands)

    def test_accepted_profile_submission_staples_validates_and_assesses(self):
        result, commands = self.run_notary('accepted')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('--keychain-profile fixture-profile', commands)
        self.assertNotIn('--password', commands)
        self.assertIn('stapler staple', commands)
        self.assertIn('stapler validate', commands)
        self.assertIn('gatekeeper', commands)

    def test_existing_ci_credentials_remain_supported(self):
        result, commands = self.run_notary('accepted', profile=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('--apple-id fixture@example.invalid', commands)
        self.assertNotIn('--keychain-profile', commands)


class NightlyCredentialSelectionTests(unittest.TestCase):
    def test_ci_secrets_do_not_require_a_local_keychain_profile(self):
        self.check_preflight(profile='', ci_credentials=True, expects_profile=False)

    def test_local_build_defaults_to_nightly_profile(self):
        self.check_preflight(profile='', ci_credentials=False, expects_profile=True)

    def test_explicit_profile_wins_over_ci_secrets(self):
        self.check_preflight(profile='fixture-profile', ci_credentials=True, expects_profile=True)

    def check_preflight(self, profile, ci_credentials, expects_profile):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            commands = root / 'commands'
            scripts = root / 'scripts'
            scripts.mkdir()
            wrapper = scripts / 'package-macos-nightly-app.zsh'
            wrapper.write_text((SCRIPT.parent / wrapper.name).read_text())
            (scripts / 'package-macos-app-shared.zsh').write_text('#!/bin/zsh\nexit 73\n')
            stubs = {
                'security': '#!/bin/zsh\nprint \'1) ABCDEF "Developer ID Application: Fixture (TESTTEAM)"\'\n',
                'xcrun': '#!/bin/zsh\nprint -r -- "$*" >> "$TEST_COMMANDS"\n',
            }
            for name, source in stubs.items():
                path = root / name
                path.write_text(source)
                path.chmod(0o755)
            environment = {
                **os.environ,
                'PATH': str(root) + ':/usr/bin:/bin:/usr/sbin:/sbin',
                'TEST_COMMANDS': str(commands),
                'OPEN_RECORDER_NOTARY_PROFILE': profile,
                'OPEN_RECORDER_SIGNING_KEYCHAIN': '', 'CODE_SIGN_IDENTITY': '',
                'APPLE_ID': 'fixture@example.invalid' if ci_credentials else '',
                'APPLE_TEAM_ID': 'TESTTEAM' if ci_credentials else '',
                'APPLE_APP_SPECIFIC_PASSWORD': 'fixture-only' if ci_credentials else '',
            }
            result = subprocess.run(['zsh', str(wrapper)],
                                    env=environment, capture_output=True, text=True)
            self.assertEqual(result.returncode, 73, result.stderr)
            recorded = commands.read_text() if commands.exists() else ''
            self.assertEqual('notarytool history --keychain-profile' in recorded, expects_profile)
            if expects_profile:
                self.assertIn(profile or 'OpenRecorderNightly', recorded)


if __name__ == '__main__':
    unittest.main()
