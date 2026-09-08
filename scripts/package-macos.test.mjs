import {test} from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';

for (const args of [
  ['--production', '--configuration', 'debug'],
  ['--dev', '--configuration', 'invalid'],
  ['--configuration'],
  ['--unknown'],
  ['--configuration', 'debug', '--production'],
]) {
  test(`reject unsafe/invalid packaging arguments: ${args.join(' ')}`, () => {
    const result = spawnSync('zsh', ['scripts/package-macos-app-shared.zsh', ...args], {encoding: 'utf8'});
    assert.equal(result.status, 2, result.stderr);
    assert.doesNotMatch(result.stdout, /Compiling|Building/);
  });
}
