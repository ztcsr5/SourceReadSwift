import cv2
from pathlib import Path

out_dir = Path("F:/SourceReadSwift/reader-quality-137/verification/snapshots-c906860/video_frames")
for idx in range(160, 194):
    p = out_dir / f"frame_{idx:04d}.jpg"
    if not p.exists(): continue
    img = cv2.imread(str(p))
    h, w, _ = img.shape
    mid = img[h//2, w//2].tolist()
    # Green bookshelf has BGR around [216, 237, 175] (high G, high R, slightly lower B)
    is_shelf = mid[1] > 200 and mid[0] < 230 and mid[2] < 200
    print(f"Frame {idx} ({idx/4.615:.2f}s): mid={mid}, is_shelf={is_shelf}")
