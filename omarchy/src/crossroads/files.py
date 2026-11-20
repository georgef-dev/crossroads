"""Writing user files so a failure never leaves them cut off."""

import os
from pathlib import Path


def write_atomically(path: Path, text: str, before_replace=None) -> None:
    """Write to a temp file beside `path`, then rename it over `path`.

    `before_replace` runs right before the rename and can raise to keep the old file.
    """
    temp = path.with_name(f".{path.name}.tmp")
    try:
        with open(temp, "w") as file:
            file.write(text)
            file.flush()
            os.fsync(file.fileno())
        if before_replace:
            before_replace()
        os.replace(temp, path)
    finally:
        temp.unlink(missing_ok=True)
