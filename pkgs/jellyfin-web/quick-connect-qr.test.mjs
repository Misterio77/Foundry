import assert from 'node:assert/strict';
import { test } from 'node:test';
import quickConnectQrHtml from './quick-connect-qr.mjs';

for (const code of ['000000', '012345', '999999']) {
    test('renders an unlinked approval QR for ' + code, () => {
        const html = quickConnectQrHtml(code);
        const url = 'https://media.m7.rs/connect?user_code=' + code;
        assert.ok(html.includes('<div class="foundry-quick-connect-qr">'));
        assert.ok(!html.includes('<a '));
        assert.ok(!html.includes(url));
        assert.ok(html.includes('<div class="foundry-quick-connect-instructions">Ou visite https://media.m7.rs/connect</div>'));
        assert.ok(!html.includes('Escaneie'));
        assert.ok(!html.includes('<p>'));
        assert.ok(html.includes('<svg'));
        assert.ok(html.includes('fill="white"'));
        assert.ok(html.includes('fill="black"'));
        assert.ok(html.includes('código ' + code));
        assert.ok(!/secret|access_token|id_token|<img|<script/i.test(html));
        assert.ok(!/src=|fetch\(/i.test(html));
    });
}

for (const code of [undefined, null, 123456, '', '12345', '1234567', '123456\n', ' 123456', '１２３４５６', '<img/>', '123&45']) {
    test('rejects malformed public code ' + JSON.stringify(code), () => {
        assert.equal(quickConnectQrHtml(code), '');
    });
}
