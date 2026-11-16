"""Capture real Chrome screenshots of compiled Flutter Figma preview builds.

This tests a STATIC preview served from the CI artifact, not the user's live
PostgreSQL/API and not a substitute for manual interaction testing.
"""
import argparse
import asyncio
from pathlib import Path
import subprocess
import sys
import time
import urllib.request

from playwright.async_api import async_playwright
from PIL import Image, ImageChops


def cases(app):
    if app == 'buyer_app':
        return [('buyer-home-iphone16pro', '/', 402, 874),
                ('buyer-home-desktop', '/', 1440, 900)]
    return [
        ('seller-profile-iphone16pro', '/?screen=366%3A15805', 402, 874),
        ('seller-settings-iphone16pro', '/?screen=366%3Asettings', 402, 874),
        ('seller-catalog-iphone16pro', '/?screen=366%3A16277', 402, 874),
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
                    response = await page.goto(
                        f'http://127.0.0.1:{port}{path}',
                        wait_until='domcontentloaded', timeout=45000)
                    if response is None or response.status != 200:
                        raise RuntimeError(f'Bad HTTP response: {response}')
                    await page.locator('flt-glass-pane').wait_for(state='attached', timeout=30000)
                    await page.wait_for_timeout(6500)
                    image = output / f'{name}.png'
                    await page.screenshot(path=str(image), full_page=True)
                    if image.stat().st_size < 2500:
                        raise RuntimeError(f'Screenshot is suspiciously small: {image}')
                    print(f'{name}: {image.stat().st_size} bytes, '
                          f'{await page.title()!r}; page errors: {errors[:3]}')
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
    parser.add_argument('--app', choices=['buyer_app', 'seller_app'], required=True)
    parser.add_argument('--build', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    index = args.build / 'index.html'
    if not index.is_file():
        raise SystemExit(f'Preview index.html missing: {index}')
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
