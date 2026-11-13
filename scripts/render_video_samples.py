"""Render bounded timestamped video samples without keeping a full recording in RAM.

Usage: python -B -X utf8 scripts/render_video_samples.py VIDEO OUTPUT --times 0,0.5,1
Run prepare_model_image.py on OUTPUT before opening it in an image viewer.
"""
import argparse
from pathlib import Path

import av
from PIL import Image, ImageDraw


def render_samples(source: Path, output: Path, targets: list[float]) -> None:
    """Decode sequentially and retain only the requested, labelled thumbnails."""
    targets = sorted(set(targets))
    if not targets or len(targets) > 30 or targets[0] < 0:
        raise ValueError("Expected 1–30 non-negative timestamps")
    samples = []
    with av.open(str(source)) as movie:
        for frame in movie.decode(video=0):
            timestamp = float(frame.time or 0)
            if timestamp < targets[len(samples)]:
                continue
            picture = frame.to_image()
            picture.thumbnail((240, 520))
            samples.append((timestamp, picture))
            if len(samples) == len(targets):
                break
    if len(samples) != len(targets):
        raise ValueError(f"Requested {len(targets)} samples; recording only supplied {len(samples)}")
    columns = min(4, len(samples))
    sheet = Image.new("RGB", (240 * columns, 550 * ((len(samples) + columns - 1) // columns)), "white")
    draw = ImageDraw.Draw(sheet)
    for index, (timestamp, picture) in enumerate(samples):
        x, y = (index % columns) * 240, (index // columns) * 550
        draw.text((x + 8, y + 8), f"{timestamp:.3f} s", fill="black")
        sheet.paste(picture, (x, y + 30))
    output.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(output, quality=85, optimize=True)
    print(f"{output.resolve()} | {len(samples)} samples | {output.stat().st_size} bytes")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("video", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--times", required=True)
    args = parser.parse_args()
    render_samples(args.video, args.output, [float(value) for value in args.times.split(",")])
