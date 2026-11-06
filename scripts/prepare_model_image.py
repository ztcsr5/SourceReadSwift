"""Create a verified image of at most 1 MiB without altering original evidence.

Usage: python -B -X utf8 scripts/prepare_model_image.py <IMAGE> [--output-dir <DIR>]
Only the returned path may be passed to the model's image viewer.
"""
import argparse
import hashlib
import io
import json
from pathlib import Path

from PIL import Image, ImageOps, UnidentifiedImageError

MAX_IMAGE_BYTES = 1_048_576


def prepare_model_image(source: Path, output_dir: Path) -> dict:
    """Return a size-checked preview receipt, keeping the source bytes intact."""
    source = source.resolve(strict=True)
    original = source.read_bytes()
    try:
        with Image.open(io.BytesIO(original)) as picture:
            picture.verify()
    except (OSError, ValueError, UnidentifiedImageError) as error:
        raise ValueError(f"Cannot preview {source.name}: expected a decodable image") from error
    if len(original) <= MAX_IMAGE_BYTES:
        return {"path": str(source), "bytes": len(original),
                "sha256": hashlib.sha256(original).hexdigest(), "converted": False}
    with Image.open(io.BytesIO(original)) as picture:
        oriented = ImageOps.exif_transpose(picture).convert("RGBA")
        canvas = Image.new("RGB", oriented.size, "white")
        canvas.paste(oriented, mask=oriented.getchannel("A"))
    canvas.thumbnail((2048, 2048), Image.Resampling.LANCZOS)
    while True:
        for quality in (90, 80, 65):
            encoded = io.BytesIO()
            canvas.save(encoded, format="JPEG", quality=quality, optimize=True)
            preview = encoded.getvalue()
            if len(preview) <= MAX_IMAGE_BYTES:
                output_dir.mkdir(parents=True, exist_ok=True)
                fingerprint = hashlib.sha256(original).hexdigest()[:12]
                target = (output_dir / f"{source.stem}-{fingerprint}-model.jpg").resolve()
                if target == source:
                    raise ValueError("Model preview must not overwrite original evidence")
                target.write_bytes(preview)
                if target.stat().st_size > MAX_IMAGE_BYTES:
                    raise RuntimeError(f"Preview of {source.name} exceeds the 1 MiB limit")
                return {"path": str(target), "bytes": len(preview), "converted": True,
                        "sha256": hashlib.sha256(preview).hexdigest(),
                        "source": str(source), "source_bytes": len(original)}
        if min(canvas.size) < 2:
            raise ValueError(f"Cannot fit {source.name} within the 1 MiB image limit")
        canvas = canvas.resize(tuple(max(1, side * 3 // 4) for side in canvas.size),
                               Image.Resampling.LANCZOS)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=Path)
    parser.add_argument("--output-dir", type=Path)
    arguments = parser.parse_args()
    folder = arguments.output_dir or arguments.image.parent / "model-previews"
    print(json.dumps(prepare_model_image(arguments.image, folder), ensure_ascii=False))
