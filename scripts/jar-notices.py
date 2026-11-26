"""Retain the distinct upstream notices when assembling the host JARs."""

from pathlib import Path
import sys
from zipfile import ZipFile


def main() -> None:
    destination = Path(sys.argv[1])
    for library in dict.fromkeys(map(Path, sys.argv[2:])):
        with ZipFile(library) as jar:
            for index, entry in enumerate(jar.infolist()):
                name = Path(entry.filename).name
                if not entry.is_dir() and name.upper().startswith(
                    ("LICENSE", "NOTICE", "COPYING", "COPYRIGHT")
                ):
                    (destination / f"{library.stem}-{index}-{name}").write_bytes(
                        jar.read(entry)
                    )


if __name__ == "__main__":
    main()
