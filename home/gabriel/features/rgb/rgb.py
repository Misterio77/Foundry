import colorsys
import sys
import time

import hidraw
import pyudev
from dbus import DBusException
from openrazer.client import DaemonNotFound, DeviceManager


def keychron(rgb):
    devices = hidraw.enumerate(0x3434, 0x0331)
    path = next((d['path'] for d in devices if (d['usage_page'], d['usage']) == (0xff60, 0x61)), None)
    if path is None:
        raise OSError('VIA interface not ready')
    hue, sat, value = colorsys.rgb_to_hsv(*(x / 255 for x in rgb))
    keyboard = hidraw.device()
    keyboard.open_path(path)
    try:
        # VIA RGB matrix channel: select solid, set hue/saturation and brightness; no EEPROM save.
        for setting in [(2, 1), (4, round(255 * hue), round(255 * sat)), (1, round(255 * value))]:
            command = bytes((7, 3, *setting)).ljust(32, b'\0')
            keyboard.write(b'\0' + command)
            if bytes(keyboard.read(32, 500)) != command:
                raise OSError('VIA did not acknowledge the lighting command')
    finally:
        keyboard.close()


def naga(rgb):
    for device in DeviceManager().devices:
        if 'Naga Epic Chroma' in device.name:
            device.fx.misc.scroll_wheel.static(*rgb)
            device.fx.misc.backlight.static(*rgb)
            return
    raise OSError('Naga not registered with OpenRazer yet')


def apply(device, rgb):
    ids = tuple(device.properties.get('PRODUCT', '').split('/')[:2])
    setter = {('3434', '331'): keychron, ('1532', '3e'): naga, ('1532', '3f'): naga}.get(ids)
    if setter is None:
        return
    for attempt in range(10):
        try:
            setter(rgb)
            return
        except (OSError, DBusException, DaemonNotFound) as error:
            if attempt == 9:
                print(f'{setter.__name__}: {error}', file=sys.stderr)
            else:
                time.sleep(1)


def main():
    rgb = bytes.fromhex(sys.argv[1].removeprefix('#'))
    context = pyudev.Context()
    monitor = pyudev.Monitor.from_netlink(context)
    monitor.filter_by('usb', 'usb_device')
    monitor.start()
    for device in context.list_devices(subsystem='usb', DEVTYPE='usb_device'):
        apply(device, rgb)
    for device in iter(monitor.poll, None):
        if device.action == 'add':
            apply(device, rgb)


if __name__ == '__main__':
    main()
