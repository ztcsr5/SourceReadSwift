import cv2
from pathlib import Path

out_dir = Path("F:/SourceReadSwift/reader-quality-137/verification/snapshots-c906860/video_frames")
frame185 = cv2.imread(str(out_dir / "frame_0185.jpg"))
h, w, _ = frame185.shape
print("Frame 185 size:", w, h)

# Save smaller preview image
preview = cv2.resize(frame185, (w//2, h//2))
cv2.imwrite(str(out_dir / "preview_185.jpg"), preview)
print("Saved preview_185.jpg")
