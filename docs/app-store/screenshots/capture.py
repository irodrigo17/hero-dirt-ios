#!/usr/bin/env python3
"""Drive the simulators to capture raw App Store screenshots.

usage: AI_AGENT=... /usr/bin/python3 capture.py <device: p17|duo> <out-dir>
Assumes the app is installed; runs it with -useFakeServices.
"""
import json
import subprocess
import sys
import time
from pathlib import Path

DEVICES = {
    'p17': 'A3DD4563-AC51-432C-987A-65B4F73A9EE4',  # iPhone 17 Pro (medium Dynamic Island, 1206x2622)
    'duo': '7B562688-9A77-4281-B1BB-FF2E244BC994',  # iPhone Duo
    'pm': 'BB1E89B1-223B-4BF1-98ED-35369C0A9D00',  # iPhone 17 Pro Max (large Dynamic Island, 1320x2868)
}
BUNDLE = 'com.herodirt.app'
dev, out = sys.argv[1], Path(sys.argv[2])
U = DEVICES[dev]
out.mkdir(parents=True, exist_ok=True)


def run(*args, check=False):
    return subprocess.run(list(args), capture_output=True, text=True, check=check)


def idb(*args, reason='App Store screenshot capture'):
    return run('idb', *args, '--udid', U, '--reason', reason)


def elements():
    r = run('idb', 'ui', 'describe-all', '--udid', U, '--json')
    try:
        return json.loads(r.stdout)
    except Exception:
        return []


def find(label_part, exact=False):
    for e in elements():
        label = str(e.get('AXLabel'))
        if (label == label_part) if exact else (label_part in label):
            f = e.get('frame') or {}
            if f.get('width', 0) > 0:
                return f
    return None


def tap(label_part, exact=False, wait=2.5):
    f = find(label_part, exact)
    if not f:
        print('  ! not found:', label_part)
        return False
    x, y = f['x'] + f['width'] / 2, f['y'] + f['height'] / 2
    idb('ui', 'tap', str(round(x)), str(round(y)), reason=f'tap "{label_part}" for screenshots')
    time.sleep(wait)
    return True


def swipe(x0, y0, x1, y1, wait=2.0, duration='1.0'):
    idb('ui', 'swipe', str(x0), str(y0), str(x1), str(y1), '--duration', duration, reason='scroll for screenshots')
    time.sleep(wait)


def shot(name):
    p = out / f'{dev}-{name}.png'
    idb('screenshot', str(p), reason=f'App Store screenshot: {name}')
    print('  shot', p.name)


def screen_size():
    r = run('idb', 'describe', '--udid', U)
    import re
    m = re.search(r'width_points=(\d+), height_points=(\d+)', r.stdout)
    return (int(m.group(1)), int(m.group(2))) if m else (402, 874)


def launch(appearance='light'):
    run('xcrun', 'simctl', 'terminate', U, BUNDLE)
    time.sleep(2)  # let the app flush its own prefs before we overwrite them
    run('xcrun', 'simctl', 'ui', U, 'appearance', appearance)
    for _ in range(3):
        run('xcrun', 'simctl', 'spawn', U, 'defaults', 'write', BUNDLE, 'homeMode', '-string', 'list')
        if run('xcrun', 'simctl', 'spawn', U, 'defaults', 'read', BUNDLE, 'homeMode').stdout.strip() == 'list':
            break
        time.sleep(1)
    run('xcrun', 'simctl', 'status_bar', U, 'override', '--time', '9:41', '--dataNetwork', 'wifi',
        '--wifiMode', 'active', '--wifiBars', '3', '--cellularMode', 'active', '--cellularBars', '4',
        '--batteryState', 'charged', '--batteryLevel', '100')
    run('xcrun', 'simctl', 'launch', U, BUNDLE, '-useFakeServices', '-startInList')
    time.sleep(9)


def back():
    if not (tap('My Trails', exact=True, wait=2) or tap('Back', wait=2)):
        w, h = screen_size()
        idb('ui', 'tap', '30', '70', reason='system back button')
        time.sleep(2)


def tap_at(x, y, why, wait=2.5, duration=None):
    extra = ['--duration', duration] if duration else []
    idb('ui', 'tap', str(round(x)), str(round(y)), *extra, reason=why)
    time.sleep(wait)


def show_map():
    # Toolbar items aren't in the accessibility tree; the map button is the
    # trailing nav bar button.
    if not tap('Show map', wait=6):
        w, h = screen_size()
        tap_at(w - 39, 83 if h > 700 else 66, 'map toggle (top trailing toolbar button)', wait=6)


def sheet_toolbar_y():
    g = find('Sheet Grabber')
    return g['y'] + g['height'] / 2 + 28 if g else None


def show_list():
    if not tap('Show trails list', wait=3):
        y = sheet_toolbar_y()
        if y:
            tap_at(44, y, 'list toggle (sheet toolbar, leading)', wait=3)


def collapse_sheet():
    g = find('Sheet Grabber')
    w, h = screen_size()
    if g:
        swipe(round(w / 2), round(g['y'] + 10), round(w / 2), round(h - 20), wait=3, duration='0.4')


def rain_map_on():
    if not tap('Rain map', wait=2):
        y = sheet_toolbar_y()
        w, h = screen_size()
        if y:
            tap_at(w - 102, y, 'rain map (sheet toolbar, trailing)', wait=2)
    # AXValue lags and the first tap can land mid-animation, so check the
    # switch's color in a screenshot and tap until it's green.
    time.sleep(1.5)
    f = find('Show rain on the map')
    if f:
        x, y = f['x'] + f['width'] - 43, f['y'] + f['height'] / 2
        for attempt in range(6):
            on = switch_is_on(x, y)
            print('  rain switch on:', on)
            if on:
                break
            # quick taps are often dropped by the switch; hold briefly
            tap_at(x, y, 'toggle rain overlay switch', wait=2.5, duration='0.15')
    s = None
    for e in elements():
        if e.get('type') == 'Slider':
            s = e.get('frame')
    if s:  # overlay strength to ~0.6 so the rain reads in screenshots
        y = s['y'] + s['height'] / 2
        swipe(round(s['x'] + s['width'] * 0.25), round(y), round(s['x'] + s['width'] * 0.65), round(y), wait=1)
    time.sleep(8)  # grid fetch + render; shot shows the map with its controls


def switch_is_on(x, y):
    from PIL import Image
    tmp = out / '_probe.png'
    idb('screenshot', str(tmp), reason='check rain overlay switch state')
    im = Image.open(tmp).convert('RGB')
    scale = im.width / screen_size()[0]
    r, g, b = im.getpixel((int((x - 20) * scale), int(y * scale)))
    tmp.unlink()
    return g > 150 and g > r + 50 and g > b + 30


def dismiss_rain_sheet():
    if not tap('Done', exact=True, wait=2):
        w, h = screen_size()
        swipe(round(w / 2), round(h * 0.42), round(w / 2), round(h * 0.97), wait=2, duration='0.3')


def portrait_flow(prefix, scroll_from, scroll_to):
    launch()
    shot(f'{prefix}1-list')
    tap('Rancho San Antonio, Trail', wait=4)
    shot(f'{prefix}2-detail')
    back()
    tap('Arastradero Preserve, Trail', wait=4)
    swipe(*scroll_from, *scroll_to)
    shot(f'{prefix}3-trend')
    back()
    show_map()
    rain_map_on()
    shot(f'{prefix}4-rainmap')
    dismiss_rain_sheet()
    show_list()
    run('xcrun', 'simctl', 'ui', U, 'appearance', 'dark')
    time.sleep(3)
    shot(f'{prefix}5-dark-list')
    run('xcrun', 'simctl', 'ui', U, 'appearance', 'light')


if dev in ('p17', 'pm'):
    run('xcrun', 'simctl', 'boot', U)
    idb('rotation', 'PORTRAIT')
    w, h = screen_size()
    portrait_flow('', (w // 2, int(h * 0.80)), (w // 2, int(h * 0.49)))
else:
    # iPhone Duo: toolbar items live in the system vertical bar / native
    # toolbars, which aren't in the accessibility tree, so use positions.
    def duo_back():
        w, h = screen_size()
        tap_at(w - 48, 194, 'back button (Duo vertical bar)', wait=2.5)

    # Outer display (folded, portrait).
    idb('hinge', '0'); idb('rotation', 'PORTRAIT'); time.sleep(3)
    w, h = screen_size()
    launch()
    shot('outer-1-list')
    tap('Rancho San Antonio, Trail', wait=4)
    shot('outer-2-detail')
    duo_back()
    tap('Arastradero Preserve, Trail', wait=4)
    swipe(w // 2 - 20, int(h * 0.80), w // 2 - 20, int(h * 0.46))
    shot('outer-3-trend')
    duo_back()
    run('xcrun', 'simctl', 'ui', U, 'appearance', 'dark'); time.sleep(3)
    shot('outer-4-dark-list')
    run('xcrun', 'simctl', 'ui', U, 'appearance', 'light')

    # Inner display, held tall (device landscape when unfolded).
    idb('hinge', '180'); time.sleep(3); idb('rotation', 'LANDSCAPE_LEFT'); time.sleep(4)
    launch()
    shot('inner-tall-1-list')

    # Inner display, held wide: list + details side by side, then the map.
    idb('rotation', 'PORTRAIT'); time.sleep(4)
    launch()
    tap('Rancho San Antonio, Trail', wait=4)
    shot('inner-wide-1-split')
    tap_at(215, 48, 'map button (sidebar nav bar)', wait=8)
    shot('inner-wide-2-map')
print('done')
