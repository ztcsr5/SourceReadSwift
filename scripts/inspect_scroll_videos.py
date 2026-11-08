"""Extract timestamped review sheets and frame motion from user-supplied recordings.

Usage: python -B -X utf8 scripts/inspect_scroll_videos.py <OUTPUT_FOLDER> <VIDEO> [VIDEO ...]
Original recordings remain unchanged; frame displacement is not a device FPS measurement.
"""
import argparse
import csv
import hashlib
import json
from pathlib import Path

import av
import cv2
import numpy as np
from PIL import Image, ImageDraw


def inspect_video(source: Path, output: Path) -> dict:
    frames = []
    with av.open(str(source)) as movie:
        stream = movie.streams.video[0]
        nominal_rate = float(stream.average_rate) if stream.average_rate else None
        for frame in movie.decode(stream):
            frames.append((float(frame.time or 0), frame.to_ndarray(format='rgb24')))
    if not frames:
        raise ValueError(f'Expected video frames in {source.name}; decoded none')
    folder = output / source.stem
    folder.mkdir(parents=True, exist_ok=True)
    height, width = frames[0][1].shape[:2]
    chosen = np.linspace(0, len(frames) - 1, 6, dtype=int)
    thumb_width = 240
    thumb_height = round(height * thumb_width / width)
    sheet = Image.new('RGB', (thumb_width * 3, (thumb_height + 30) * 2), 'white')
    labels = ImageDraw.Draw(sheet)
    for number, index in enumerate(chosen):
        timestamp, pixels = frames[index]
        picture = Image.fromarray(pixels).resize((thumb_width, thumb_height))
        x, y = (number % 3) * thumb_width, (number // 3) * (thumb_height + 30)
        sheet.paste(picture, (x, y + 30))
        labels.text((x + 8, y + 8), f'{timestamp:.3f} s / frame {index}', fill='black')
    sheet.save(folder / 'contact.jpg', quality=85)
    rows = []
    previous = None
    previous_time = None
    for timestamp, pixels in frames:
        scaled = cv2.resize(pixels, (360, round(height * 360 / width)))
        gray = cv2.cvtColor(scaled, cv2.COLOR_RGB2GRAY)
        roi = gray[int(gray.shape[0] * .16):int(gray.shape[0] * .85), 20:-20]
        if previous is not None:
            corners = cv2.goodFeaturesToTrack(previous, maxCorners=200, qualityLevel=.03, minDistance=8)
            dy, support = None, 0
            if corners is not None:
                points, valid, errors = cv2.calcOpticalFlowPyrLK(previous, roi, corners, None,
                    winSize=(21, 21), maxLevel=3)
                shift = (points - corners).reshape(-1, 2)
                selected = shift[(valid.ravel() == 1) & (errors.ravel() < 25) & (np.abs(shift[:, 0]) < 2)]
                if len(selected) >= 10:
                    dy = float(np.median(selected[:, 1])) * width / 360
                    support = len(selected)
            rows.append({'seconds': timestamp, 'dt': timestamp - previous_time,
                         'vertical_pixels': dy, 'tracked_points': support,
                         'pixel_difference': float(np.mean(cv2.absdiff(previous, roi)))})
        previous, previous_time = roi, timestamp
    with (folder / 'motion.csv').open('w', newline='', encoding='utf8') as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader(); writer.writerows(rows)
    record = {'path': str(source), 'bytes': source.stat().st_size,
              'sha256': hashlib.sha256(source.read_bytes()).hexdigest(), 'frames': len(frames),
              'nominal_fps': nominal_rate, 'duration_seconds': frames[-1][0], 'width': width, 'height': height,
              'contact': str(folder / 'contact.jpg'), 'motion': str(folder / 'motion.csv')}
    (folder / 'metadata.json').write_text(json.dumps(record, ensure_ascii=False, indent=2), encoding='utf8')
    return record


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    parser.add_argument('videos', nargs='+', type=Path)
    arguments = parser.parse_args()
    for source in arguments.videos:
        print(json.dumps(inspect_video(source, arguments.output), ensure_ascii=False), flush=True)
