import cv2
import numpy as np
from pathlib import Path

out_dir = Path("F:/SourceReadSwift/reader-quality-137/verification/snapshots-c906860/video_frames")
for idx in [100, 130, 150, 165, 175, 185, 190]:
    p = out_dir / f"frame_{idx:04d}.jpg"
    if not p.exists(): continue
    img = cv2.imread(str(p))
    # Sample top, middle, bottom colors
    h, w, _ = img.shape
    top_color = img[50, w//2].tolist()
    mid_color = img[h//2, w//2].tolist()
    print(f"Frame {idx}: shape=({w}x{h}), mid_color(BGR)={mid_color}, top_color={top_color}")
