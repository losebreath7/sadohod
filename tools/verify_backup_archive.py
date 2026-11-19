"""Reject unsafe tar members; inspect or extract only uploads/ and state/.

No links, special files, traversal or unexpected root entries may enter the
recovery process. Integrity of the archive itself is checked by SHA256SUMS.
"""
import argparse
from pathlib import Path, PurePosixPath
import tarfile


def verify_and_extract(archive: Path, destination: Path | None = None) -> None:
    with tarfile.open(archive, "r:gz") as handle:
        members = handle.getmembers()
        if not members:
            raise ValueError("Empty backup archive")
        seen: set[str] = set()
        for member in members:
            name = member.name.removeprefix("./").rstrip("/")
            path = PurePosixPath(name)
            if (
                name in seen or not name or path.is_absolute()
                or any(part in ("", ".", "..") for part in path.parts)
                or path.parts[0] not in {"uploads", "state"}
                or not (member.isfile() or member.isdir())
            ):
                raise ValueError("Unsafe or duplicate archive entry")
            seen.add(name)
        if not {"uploads", "state"}.issubset(seen):
            raise ValueError("Missing uploads/ or state/ in backup")
        if destination is not None:
            destination.mkdir(parents=True, exist_ok=True)
            for member in members:
                name = member.name.removeprefix("./").rstrip("/")
                path = destination.joinpath(*PurePosixPath(name).parts)
                if member.isdir():
                    path.mkdir(parents=True, exist_ok=True)
                else:
                    path.parent.mkdir(parents=True, exist_ok=True)
                    stream = handle.extractfile(member)
                    if stream is None:
                        raise ValueError("Unreadable file in backup")
                    with stream, path.open("xb") as writer:
                        while data := stream.read(1024 * 1024):
                            writer.write(data)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("archive", type=Path)
    parser.add_argument("--destination", type=Path)
    parser.add_argument("--check-only", action="store_true")
    args = parser.parse_args()
    if not args.check_only and args.destination is None:
        parser.error("Provide --destination or --check-only")
    verify_and_extract(args.archive, None if args.check_only else args.destination)
