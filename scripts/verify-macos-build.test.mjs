import {test} from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';

test('packaging verifier rejects incorrect metadata and resources', () => {
  const result = spawnSync('python3', ['-c', `
import importlib.util, pathlib, plistlib, tempfile, sys
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location('verify', 'scripts/verify-macos-build.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
with tempfile.TemporaryDirectory() as temporary:
    root = pathlib.Path(temporary)
    contents = root / 'Contents'
    contents.mkdir()
    good = dict(OpenRecorderBuildConfiguration='release', OpenRecorderSourceRevision='abc',
                CFBundleShortVersionString='1.0', CFBundleVersion='1.0')
    for field in good:
        metadata = {**good, field: 'incorrect'}
        (contents / 'Info.plist').write_bytes(plistlib.dumps(metadata))
        try:
            module.verify(root, 'release', 'abc', 'arm64', '1.0', '/tmp/release', '/tmp/release')
        except ValueError as error:
            assert field in str(error), error
        else:
            raise AssertionError(field)
    (contents / 'Info.plist').write_bytes(plistlib.dumps(good))
    try:
        module.verify(root, 'release', 'abc', 'arm64', '1.0', '/tmp/release', '/tmp/release')
    except ValueError as error:
        assert 'resources' in str(error), error
    else:
        raise AssertionError('missing resources accepted')
`], {encoding: 'utf8'});
  assert.equal(result.status, 0, result.stderr);
});
