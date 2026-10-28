"""Prepare a reproducible benchmark from six public scikit-image photographs.

The destination must not exist. Only standard-library Python is required.
"""

import argparse
import hashlib
from pathlib import Path
import shutil
import urllib.request

BASE = "https://raw.githubusercontent.com/scikit-image/scikit-image/v0.25.2/skimage/data/"
FILES = {
    "astronaut.png": "88431cd9653ccd539741b555fb0a46b61558b301d4110412b5bc28b5e3ea6cb5",
    "camera.png": "b0793d2adda0fa6ae899c03989482bff9a42d3d5690fc7e3648f2795d730c23a",
    "chelsea.png": "596aa1e7cb875eb79f437e310381d26b338a81c2da23439704a73c4651e8c4bb",
    "clock_motion.png": "f029226b28b642e80113d86622e9b215ee067a0966feaf5e60604a1e05733955",
    "coffee.png": "cc02f8ca188b167c775a7101b5d767d1e71792cf762c33d6fa15a4599b5a8de7",
    "rocket.jpg": "c2dd0de7c538df8d111e479619b129464d0269d0ae5fd18ca91d33a7fdfea95c",
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("destination", type=Path, help="new directory for the downloaded photos and test cases")
    parser.add_argument("--copies", type=int, default=1, help="repeat each case this many times (1..100)")
    args = parser.parse_args()
    if not 1 <= args.copies <= 100:
        parser.error("--copies must be between 1 and 100")
    root = args.destination.resolve()
    root.mkdir(parents=True, exist_ok=False)
    source = root / "source"
    source.mkdir()
    for name, expected in FILES.items():
        with urllib.request.urlopen(BASE + name, timeout=60) as response:
            data = response.read()
        if hashlib.sha256(data).hexdigest() != expected:
            raise ValueError(f"SHA-256 mismatch for {name}")
        (source / name).write_bytes(data)
    for index in range(args.copies):
        library = root / "library" / f"batch-{index:03}"
        incoming = root / "incoming" / f"batch-{index:03}"
        library.mkdir(parents=True)
        incoming.mkdir(parents=True)
        for name in ("astronaut.png", "camera.png", "coffee.png"):
            shutil.copyfile(source / name, library / name)
        # A duplicate with a different name, a same-name conflict, and two new photos.
        for src, dst in (("coffee.png", "coffee-copy.png"),
                         ("chelsea.png", "astronaut.png"),
                         ("rocket.jpg", "rocket.jpg"),
                         ("clock_motion.png", "clock_motion.png")):
            shutil.copyfile(source / src, incoming / dst)
    print(f"Prepared {args.copies} batches: {args.copies * 3} existing and {args.copies * 4} incoming files.")
    print(f"Existing: {root / 'library'}\nIncoming: {root / 'incoming'}")


if __name__ == "__main__":
    main()
