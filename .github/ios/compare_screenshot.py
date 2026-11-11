import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageChops, ImageOps


BASELINE = Path(__file__).with_name("baselines") / "products.png"
PRODUCTS_SIZE = (1206, 2622)


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

    difference = ImageChops.difference(expected, actual)
    if difference.getbbox(alpha_only=False):
        mask = difference.getchannel("R")
        for channel in ("G", "B", "A"):
            mask = ImageChops.lighter(mask, difference.getchannel(channel))
        mask = mask.point(lambda value: 255 if value else 0)
        grayscale = ImageOps.grayscale(actual).convert("RGB")
        red = Image.new("RGB", actual.size, (255, 0, 0))
        Image.composite(red, grayscale, mask).save(screenshots / "diff.png")
        raise SystemExit("Products screenshot differs from the baseline. See screenshots/diff.png.")

    print("Products screenshot matches the baseline.")


if __name__ == "__main__":
    compare(Path(sys.argv[1]))
