import cv2
from pathlib import Path

video_path = Path("F:/SourceReadSwift/reader-quality-137/verification/snapshots-c906860/gestures/1AA9106C-1D02-4F84-A3E5-05D7C566EDC1.mp4")
cap = cv2.VideoCapture(str(video_path))
out_dir = Path("F:/SourceReadSwift/reader-quality-137/verification/snapshots-c906860/video_frames")
out_dir.mkdir(parents=True, exist_ok=True)

frame_idx = 0
saved = 0
while True:
    ret, frame = cap.read()
    if not ret: break
    # Save every 10th frame
    if frame_idx % 15 == 0 or frame_idx > 150:
        cv2.imwrite(str(out_dir / f"frame_{frame_idx:04d}.jpg"), frame)
        saved += 1
    frame_idx += 1
cap.release()
print(f"Total read: {frame_idx}, saved: {saved}")
