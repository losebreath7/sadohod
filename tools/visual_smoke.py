"""Capture real Chrome screenshots of compiled Flutter Figma preview builds.

This tests a STATIC preview served from the CI artifact, not the user's live
PostgreSQL/API and not a substitute for manual interaction testing.
"""
import argparse
import json
import asyncio
from pathlib import Path
import subprocess
import sys
import time
import urllib.request

from playwright.async_api import async_playwright
from PIL import Image, ImageChops


def verify_manrope_bundle(build):
    """Check the actual compiled web output, not just pubspec declarations.

    This guards against a missing package font, absent font weight or a stale
    release build which quietly falls back to a system typeface in Chrome.
    """
    manifest_path = build / 'assets' / 'FontManifest.json'
    if not manifest_path.is_file():
        raise RuntimeError(f'Flutter font manifest missing: {manifest_path}')
    manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
    families = [item for item in manifest
                if item.get('family') == 'packages/sadohod_shared_core/Manrope']
    if len(families) != 1:
        raise RuntimeError('Web build has no unique shared Manrope font family')
    expected = {
        200: 'Manrope-ExtraLight.ttf', 300: 'Manrope-Light.ttf',
        400: 'Manrope-Regular.ttf', 500: 'Manrope-Medium.ttf',
        600: 'Manrope-SemiBold.ttf', 700: 'Manrope-Bold.ttf',
        800: 'Manrope-ExtraBold.ttf',
    }
    fonts = families[0].get('fonts', [])
    actual = {int(row.get('weight', 400)): row.get('asset') for row in fonts}
    for weight, name in expected.items():
        asset = f'packages/sadohod_shared_core/assets/fonts/{name}'
        if actual.get(weight) != asset:
            raise RuntimeError(f'Manrope {weight} missing or mapped incorrectly: {actual}')
        file = build / 'assets' / asset
        if not file.is_file() or file.stat().st_size < 90000:
            raise RuntimeError(f'Manrope font not bundled: {file}')
    print('Manrope font manifest: 7 weights, all TTF assets present')


def cases(app):
    if app == 'buyer_matrix':
        # QA presets are selected via URL so the screenshot reliably exercises
        # the actual browser device wrapper and its MediaQuery.
        return [
            ('buyer-matrix-iphone16pro', '/?previewDevice=iPhone%2016%20Pro#/home', 1440, 1000),
            ('buyer-matrix-iphone13', '/?previewDevice=iPhone%2013#/home', 1440, 1000),
            ('buyer-matrix-compact320', '/?previewDevice=Compact%20320#/home', 1440, 1000),
            ('buyer-matrix-galaxy-a15', '/?previewDevice=Galaxy%20A15#/home', 1440, 1000),
            ('buyer-matrix-tecno-spark20', '/?previewDevice=TECNO%20Spark%2020#/home', 1440, 1000),
            ('buyer-matrix-pro-max', '/?previewDevice=iPhone%2016%20Pro%20Max#/home', 1440, 1080),
        ]
    if app == 'buyer_shell':
        # Real desktop-hosted phone preview injects a 62 px iOS SafeArea,
        # unlike FIGMA_PREVIEW which removes the phone frame.
        return [
            ('buyer-shell-home', '/#/home', 1440, 1000),
            ('buyer-shell-favorites', '/#/favorites', 1440, 1000),
            ('buyer-shell-favorite-sellers', '/#/favorite-sellers', 1440, 1000),
            ('buyer-shell-product', '/#/product/p01', 1440, 1000),
            ('buyer-shell-seller', '/#/seller/s01', 1440, 1000),
            ('buyer-shell-profile', '/#/account', 1440, 1000),
        ]
    if app == 'buyer_app':
        return [('buyer-home-iphone16pro', '/', 402, 874),
                ('buyer-home-desktop', '/', 1440, 900)]
    return [
        ('seller-profile-iphone16pro', '/?screen=366%3A15805', 402, 874),
        ('seller-settings-iphone16pro', '/?screen=366%3Asettings', 402, 874),
        ('seller-catalog-iphone16pro', '/?screen=366%3A16277', 402, 874),
        ('seller-shop-iphone16pro', '/?screen=366%3A17044', 402, 874),
        ('seller-selection-iphone16pro', '/?screen=388%3A17542', 402, 874),
        ('seller-add-product-iphone16pro', '/?screen=366%3A17304', 402, 874),
        ('seller-edit-product-iphone16pro', '/?screen=366%3A16062', 402, 874),
    ]


async def capture(app, port, output):
    async with async_playwright() as playwright:
        browser = await playwright.chromium.launch(
            channel='chrome', headless=True,
            args=['--no-sandbox', '--disable-dev-shm-usage',
                  '--enable-unsafe-swiftshader',
                  '--use-gl=angle', '--use-angle=swiftshader'])
        try:
            for name, path, width, height in cases(app):
                context = await browser.new_context(
                    viewport={'width': width, 'height': height},
                    device_scale_factor=1, locale='ru-RU',
                    service_workers='block')
                page = await context.new_page()
                errors = []
                page.on('pageerror', lambda exc: errors.append(str(exc)[:250]))
                try:
                    # For saved products exercise the actual Flutter UI, not
                    # a seeded localStorage snapshot. The preview runs in
                    # a 1440x1000 Chrome viewport with a 402px iPhone shell.
                    entry_path = '/#/home' if name == 'buyer-shell-favorites' else path
                    response = await page.goto(
                        f'http://127.0.0.1:{port}{entry_path}',
                        wait_until='domcontentloaded', timeout=45000)
                    if response is None or response.status != 200:
                        raise RuntimeError(f'Bad HTTP response: {response}')
                    await page.locator('flt-glass-pane').wait_for(state='attached', timeout=30000)
                    await page.wait_for_timeout(6500)
                    if name == 'buyer-shell-favorites':
                        # Heart on first home product, then bottom favorites tab.
                        await page.mouse.click(690, 508)
                        await page.wait_for_timeout(800)
                        await page.mouse.click(720, 870)
                        await page.wait_for_timeout(1500)
                        if '/favorites' not in page.url:
                            raise AssertionError(
                                f'Buyer favorites tab did not open: {page.url}')
                        print('Opened favorites after saving the first demo product via UI.')
                    image = output / f'{name}.png'
                    await page.screenshot(path=str(image), full_page=True)
                    if image.stat().st_size < 2500:
                        raise RuntimeError(f'Screenshot is suspiciously small: {image}')
                    print(f'{name}: {image.stat().st_size} bytes, '
                          f'{await page.title()!r}; page errors: {errors[:3]}')
                    if name == 'buyer-shell-home':
                        # Scroll inside the simulated phone to exercise
                        # the 402→75 px pinned header, not the desktop page.
                        await page.mouse.move(724, 540)
                        await page.mouse.wheel(0, 460)
                        await page.wait_for_timeout(1100)
                        compact = output / 'buyer-shell-home-compact.png'
                        await page.screenshot(path=str(compact), full_page=True)
                        head_before = Image.open(image).convert('RGB').crop(
                            (590, 165, 870, 420))
                        head_after = Image.open(compact).convert('RGB').crop(
                            (590, 165, 870, 420))
                        if ImageChops.difference(head_before, head_after).getbbox() is None:
                            raise AssertionError('Pinned home header did not react to scroll')
                        print('Buyer device-shell pinned header changed after real mouse wheel.')
                    if name == 'buyer-home-iphone16pro':
                        # Figma header tag rail lives in this narrow strip.
                        # This is a real mouse pointer drag, not a touch swipe.
                        await page.mouse.move(320, 375)
                        await page.mouse.down()
                        await page.mouse.move(54, 375, steps=24)
                        await page.mouse.up()
                        await page.wait_for_timeout(850)
                        dragged = output / 'buyer-tags-after-mouse-drag.png'
                        await page.screenshot(path=str(dragged), full_page=True)
                        before_strip = Image.open(image).convert('RGB').crop(
                            (30, 362, 372, 392))
                        after_strip = Image.open(dragged).convert('RGB').crop(
                            (30, 362, 372, 392))
                        if ImageChops.difference(before_strip, after_strip).getbbox() is None:
                            raise AssertionError(
                                'Mouse drag did not change the visible tag strip')
                        print('Buyer tag rail changed after real Chrome mouse drag.')
                finally:
                    await context.close()
        finally:
            await browser.close()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--app', choices=['buyer_app', 'seller_app', 'buyer_shell', 'buyer_matrix'], required=True)
    parser.add_argument('--build', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    index = args.build / 'index.html'
    if not index.is_file():
        raise SystemExit(f'Preview index.html missing: {index}')
    verify_manrope_bundle(args.build)
    port = 8765
    server = subprocess.Popen(
        [sys.executable, '-m', 'http.server', str(port), '--bind', '127.0.0.1',
         '--directory', str(args.build.resolve())],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        for _ in range(100):
            try:
                urllib.request.urlopen(f'http://127.0.0.1:{port}/', timeout=1)
                break
            except Exception:
                time.sleep(0.1)
        else:
            raise RuntimeError('Local preview server did not start')
        asyncio.run(capture(args.app, port, args.output))
    finally:
        server.terminate()
        server.wait(timeout=10)


if __name__ == '__main__':
    main()
