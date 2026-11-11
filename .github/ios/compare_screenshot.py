import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageChops, ImageOps


BASELINE = Path(__file__).with_name("baselines") / "products.png"
PRODUCTS_SIZE = (1206, 2622)
# Independent captures on iOS 26.2 differed by one RGB level around the demo badge shadow.
DEMO_BADGE_SHADOW = (800, 100, 1206, 450)


def export_products_screenshot(result, destination):
    with tempfile.TemporaryDirectory() as directory:
        attachments = Path(directory)
        subprocess.run(
            [
                "xcrun", "xcresulttool", "export", "attachments",
                "--path", str(result), "--output-path", directory,
            ],
            check=True,
        )
        manifest = json.loads((attachments / "manifest.json").read_text())
        screenshots = [
            attachment["exportedFileName"]
            for test in manifest
            for attachment in test["attachments"]
            if attachment["suggestedHumanReadableName"].startswith("almostready-products")
        ]
        if len(screenshots) != 1:
            raise SystemExit(f"Expected one Products screenshot, found {len(screenshots)}")
        shutil.copyfile(attachments / screenshots[0], destination)


def compare(reports):
    screenshots = reports / "screenshots"
    screenshots.mkdir(exist_ok=True)
    actual_file = screenshots / "actual.png"
    expected_file = screenshots / "expected.png"
    if BASELINE.is_file():
        shutil.copyfile(BASELINE, expected_file)

    result = reports / "screenshots.xcresult"
    if not result.is_dir():
        raise SystemExit(f"XCTest did not produce {result}")
    export_products_screenshot(result, actual_file)

    with Image.open(actual_file) as image:
        actual = image.convert("RGBA")
    if actual.size != PRODUCTS_SIZE:
        raise SystemExit(f"Expected iPhone 17 Pro portrait {PRODUCTS_SIZE}, got {actual.size}")
    if not expected_file.is_file():
        raise SystemExit(f"Missing {BASELINE}. Review actual.png from ios-screenshots-reports.")

    with Image.open(expected_file) as image:
        expected = image.convert("RGBA")
    if expected.size != actual.size:
        raise SystemExit(f"Baseline has size {expected.size}, actual has size {actual.size}")

    red, green, blue, alpha = ImageChops.difference(expected, actual).split()
    rgb_difference = ImageChops.lighter(ImageChops.lighter(red, green), blue)
    shadow_difference = rgb_difference.crop(DEMO_BADGE_SHADOW)
    rounding_pixels = shadow_difference.histogram()[1]
    rgb_difference.paste(shadow_difference.point(lambda value: 0 if value == 1 else value), DEMO_BADGE_SHADOW)
    mask = ImageChops.lighter(rgb_difference, alpha)
    if mask.getbbox():
        mask = mask.point(lambda value: 255 if value else 0)
        grayscale = ImageOps.grayscale(actual).convert("RGB")
        highlight = Image.new("RGB", actual.size, (255, 0, 0))
        Image.composite(highlight, grayscale, mask).save(screenshots / "diff.png")
        raise SystemExit("Products screenshot differs from the baseline. See screenshots/diff.png.")

    print(f"Products screenshot matches the baseline ({rounding_pixels} RGB rounding pixels in the badge shadow).")


if __name__ == "__main__":
    compare(Path(sys.argv[1]))
