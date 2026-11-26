#!/usr/bin/env python3
"""Moves a finished snapshot render into the output folder, touching nothing it didn't create.

usage: publish_snapshots.py <stage-dir> <output-dir>

<stage-dir> is where the renderer wrote its PNGs and manifest.txt (one file name per line). The output folder
gets the PNGs and OWN_MANIFEST, which starts with SIGNATURE and lists what was published. The next publish
replaces exactly those files.

Rules (from QA reports on macOS/scripts/render_snapshots.sh):
- File names must look like "worldclock-medium-analog.png" (NAME), in the stage and in a previous manifest.
- A previous render is recognized only by OWN_MANIFEST starting with SIGNATURE. Any other file is left alone,
  including someone else's manifest.txt and the files it lists. An OWN_MANIFEST without the signature, or
  listing an unexpected name, stops the publish.
- Everything is checked before anything changes. Each target path must be absent, or a regular file the
  previous render published. A directory, a symlink or another file with the same name stops the publish,
  and the output folder stays exactly as it was.
- Afterwards, every published file must be a regular file that decodes as a PNG (sips).
Exits 0 on success, 1 (with a message, nothing changed unless stated) otherwise.
"""
import os
import re
import subprocess
import sys
import tempfile

OWN_MANIFEST = "world-clock-widgets-snapshots.txt"
SIGNATURE = "# World Clock Widgets snapshots (scripts/render_snapshots.sh). Files listed here are replaced by the next render."
NAME = re.compile(r"^[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*\.png$")


class PublishError(Exception):
    pass


def decodes_as_png(path):
    result = subprocess.run(["sips", "-g", "pixelWidth", path], capture_output=True, text=True)
    return result.returncode == 0 and re.search(r"pixelWidth: [1-9]", result.stdout) is not None


def is_regular_file(path):
    return os.path.isfile(path) and not os.path.islink(path)


def read_stage(stage):
    manifest = os.path.join(stage, "manifest.txt")
    if not is_regular_file(manifest):
        raise PublishError("the renderer wrote no manifest")
    with open(manifest, encoding="utf-8") as f:
        names = [line.strip() for line in f if line.strip()]
    if not names:
        raise PublishError("no snapshots rendered")
    if len(set(names)) != len(names):
        raise PublishError("the renderer listed a file twice")
    for name in names:
        if not NAME.match(name):
            raise PublishError(f"unexpected file name from the renderer: {name!r}")
        path = os.path.join(stage, name)
        if not is_regular_file(path) or os.path.getsize(path) == 0:
            raise PublishError(f"missing snapshot {name}")
        if not decodes_as_png(path):
            raise PublishError(f"{name} is not a readable PNG")
    return names


def read_previous(out):
    """The names the previous render published here ([] if none)."""
    path = os.path.join(out, OWN_MANIFEST)
    if not os.path.lexists(path):
        return []
    if not is_regular_file(path):
        raise PublishError(f"{path} is not a regular file; nothing changed")
    with open(path, encoding="utf-8", errors="replace") as f:
        lines = [line.rstrip("\n") for line in f]
    if not lines or lines[0] != SIGNATURE:
        raise PublishError(f"{path} wasn't written by this script (no signature); nothing changed")
    names = [line.strip() for line in lines[1:] if line.strip()]
    for name in names:
        if not NAME.match(name):
            raise PublishError(f"{path} lists an unexpected name {name!r}; nothing changed")
    return names


def publish(stage, out):
    names = read_stage(stage)
    if os.path.lexists(out) and (os.path.islink(out) or not os.path.isdir(out)):
        raise PublishError(f"{out} exists and is not a folder; nothing changed")
    previous = read_previous(out) if os.path.isdir(out) else []
    ours = set(previous)

    # Preflight: every path that will be written or removed.
    for name in names:
        target = os.path.join(out, name)
        if os.path.lexists(target):
            if not is_regular_file(target):
                raise PublishError(f"{target} exists and is not a regular file; nothing changed")
            if name not in ours:
                raise PublishError(f"{target} exists and wasn't written by a previous render "
                                   f"(not listed in {OWN_MANIFEST}); move it away or choose another folder; "
                                   "nothing changed")
    stale = [name for name in previous if name not in names]
    for name in stale:
        target = os.path.join(out, name)
        if os.path.lexists(target) and not is_regular_file(target):
            raise PublishError(f"{target} is listed in {OWN_MANIFEST} but is not a regular file; nothing changed")

    # Publish. Each file goes to a temporary name in the output folder first, then replaces its target (a
    # regular file or nothing, checked above).
    os.makedirs(out, exist_ok=True)
    for name in stale:
        target = os.path.join(out, name)
        if os.path.lexists(target):
            os.remove(target)
    for name in names:
        with open(os.path.join(stage, name), "rb") as f:
            replace_with(os.path.join(out, name), f.read(), out)
    manifest = SIGNATURE + "\n" + "".join(name + "\n" for name in names)
    replace_with(os.path.join(out, OWN_MANIFEST), manifest.encode("utf-8"), out)

    # Afterwards: what the manifest lists is really there.
    for name in names:
        target = os.path.join(out, name)
        if not is_regular_file(target) or not decodes_as_png(target):
            raise PublishError(f"{target} is not a readable PNG after publishing")
    return names


def replace_with(target, data, folder):
    fd, temporary = tempfile.mkstemp(prefix=".publishing-", dir=folder)
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(data)
        os.chmod(temporary, 0o644)
        os.replace(temporary, target)
    except BaseException:
        if os.path.lexists(temporary):
            os.remove(temporary)
        raise


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    try:
        names = publish(sys.argv[1], sys.argv[2])
    except PublishError as error:
        sys.exit(f"error: {error}")
    print(f"Published {len(names)} snapshots into {sys.argv[2]} (listed in {OWN_MANIFEST})")


if __name__ == "__main__":
    main()
