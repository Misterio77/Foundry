import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import { runInNewContext } from 'node:vm';

// Exercise the patched entry point without importing the rest of the Web UI.
const source = readFileSync(process.env.JELLYFIN_DASHBOARD_SOURCE, 'utf8');
const match = source.match(/export function logout\(\) \{[\s\S]*?\n\}/);
assert.ok(match, 'dashboard logout entry point exists');

function fixture(logoutPromise) {
    const calls = [];
    const unexpectedNavigation = () => assert.fail('must not navigate back to Jellyfin login/server selection');
    const logout = runInNewContext(match[0].replace('export ', '') + '\nlogout;', {
        ServerConnections: {
            logout: () => {
                calls.push('logout');
                return logoutPromise;
            }
        },
        queryClient: { clear: () => calls.push('clear') },
        viewContainer: { reset: () => calls.push('reset') },
        window: { location: { assign: url => calls.push(url) } },
        appHost: { supports: unexpectedNavigation },
        selectServer: unexpectedNavigation,
        navigate: unexpectedNavigation
    });
    return { logout, calls };
}

test('waits for local logout before cache cleanup and full-page IdP navigation', async () => {
    let complete;
    const pending = new Promise(resolve => { complete = resolve; });
    const { logout, calls } = fixture(pending);
    const result = logout();
    await Promise.resolve();
    assert.deepEqual(calls, ['logout']);
    complete();
    await result;
    assert.deepEqual(calls, [
        'logout', 'clear', 'reset',
        'https://auth.m7.rs/application/o/jellyfin/end-session/'
    ]);
});

test('leaves provider choices visible without tokens or an automatic return URL', async () => {
    const { logout, calls } = fixture(Promise.resolve());
    await logout();
    const url = new URL(calls.at(-1));
    assert.equal(url.origin, 'https://auth.m7.rs');
    assert.equal(url.pathname, '/application/o/jellyfin/end-session/');
    assert.equal(url.search, '');
    assert.equal(url.hash, '');
});

test('does not redirect or clear caches if the logout promise rejects', async () => {
    const error = new Error('logout failed');
    const { logout, calls } = fixture(Promise.reject(error));
    await assert.rejects(logout(), error);
    assert.deepEqual(calls, ['logout']);
});
