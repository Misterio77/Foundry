import qrcode from './qrcode.cjs';

export default function quickConnectQrHtml(code) {
    if (typeof code !== 'string' || code.length !== 6 || !/^[0-9]+$/.test(code)) {
        return '';
    }

    const url = 'https://media.m7.rs/connect?user_code=' + code;
    try {
        const qr = qrcode(0, 'M');
        qr.addData(url);
        qr.make();
        const svg = qr.createSvgTag({
            cellSize: 4,
            margin: 16,
            scalable: true,
            title: 'Autorizar o dispositivo com o código ' + code
        });
        return '<div class="foundry-quick-connect-qr">' + svg + '</div><div class="foundry-quick-connect-instructions">Ou visite https://media.m7.rs/connect</div>';
    } catch (error) {
        console.warn('Unable to generate device approval QR', error);
        return '';
    }
}
