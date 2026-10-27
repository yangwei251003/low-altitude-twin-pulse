"""Bounded local development outputs. No source/save discovery or automatic sweep."""
from pathlib import Path
from contextlib import contextmanager
import ctypes
import hashlib
import json
import os
import re
import shutil
import stat
import uuid
import zipfile

GiB = 1024 ** 3
MiB = 1024 ** 2
LIMITS = {"builds": 3 * GiB, "recovery": 8 * GiB, "evidence": 2 * GiB}
RESERVE = 15 * GiB
CODE_LIMIT = 256 * MiB
QA_LIMIT = 384 * MiB
EXPECTED_PROJECT = Path(".")
ENV_HOME = "LOW_ALTITUDE_DEV_HOME"


class PolicyError(RuntimeError):
    pass


def plain_path(value, *, existing=False):
    """Reject reparse ancestors BEFORE resolution, including junctions on Windows."""
    path = Path(os.path.expandvars(os.path.expanduser(os.fspath(value))))
    if not path.is_absolute() or str(path).startswith(("\\\\", "//")):
        raise PolicyError("absolute ordinary local-drive path required")
    for part in (path, *path.parents):
        try:
            info = part.lstat()
        except FileNotFoundError:
            continue
        if stat.S_ISLNK(info.st_mode) or getattr(info, "st_file_attributes", 0) & 0x400:
            raise PolicyError("reparse/symlink ancestor refused: " + str(part))
    return path.resolve(strict=existing)


def desktop_paths():
    paths = [Path.home() / "Desktop"]
    if os.name == "nt":
        for folder in (0x10, 0x19):  # User and common physical Desktop, including redirects.
            buffer = ctypes.create_unicode_buffer(32768)
            if ctypes.windll.shell32.SHGetFolderPathW(None, folder, None, 0, buffer) != 0:
                raise PolicyError("cannot establish actual Desktop directory")
            paths.append(Path(buffer.value))
    return [p.resolve(strict=False) for p in paths]


def sha256(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(MiB), b""):
            digest.update(block)
    return digest.hexdigest()


def atomic_json(path, value):
    temp = path.with_name(path.name + "." + uuid.uuid4().hex + ".tmp")
    try:
        with temp.open("x", encoding="utf-8", newline="\n") as stream:
            json.dump(value, stream, ensure_ascii=False, indent=2)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temp, path)
    finally:
        if temp.exists():
            temp.unlink()


class StoragePolicy:
    def __init__(self, project=EXPECTED_PROJECT, home=None):
        self.project = plain_path(project, existing=True)
        if self.project != plain_path(EXPECTED_PROJECT, existing=True):
            raise PolicyError("wrong real project root")
        chosen = home if home is not None else os.environ.get(ENV_HOME)
        if chosen is None:
            local = os.environ.get("LOCALAPPDATA")
            if not local:
                raise PolicyError("LOCALAPPDATA is unavailable")
            chosen = Path(local) / "LowAltitudeTwinPulseDev"
        self.root = plain_path(chosen)
        if self.root.name.casefold() != "lowaltitudetwinpulsedev":
            raise PolicyError("managed directory must be named LowAltitudeTwinPulseDev")
        if any(self.root == d or self.root.is_relative_to(d) for d in desktop_paths()):
            raise PolicyError("Desktop output refused")
        if self.root == self.project or self.root.is_relative_to(self.project):
            raise PolicyError("project/source output refused")
        marker = self.root / "owner.json"
        default = plain_path(Path(os.environ.get("LOCALAPPDATA", "")) / "LowAltitudeTwinPulseDev")
        if self.root.exists() and not marker.exists() and any(self.root.iterdir()):
            if self.root != default or any(p.name not in {*LIMITS, "authoring"} for p in self.root.iterdir()):
                raise PolicyError("nonempty unowned directory refused")
        self.root.mkdir(parents=True, exist_ok=True)
        plain_path(self.root, existing=True)
        info = self.project.stat()
        binding = {"schema": 1, "kind": "LowAltitudeTwinPulseDev", "project": str(self.project),
                   "project_identity": [info.st_dev, info.st_ino], "home": str(self.root)}
        if not marker.exists():
            try:
                with marker.open("x", encoding="utf-8") as stream:
                    json.dump({**binding, "owner": uuid.uuid4().hex}, stream)
            except FileExistsError:
                pass
        plain_path(marker, existing=True)
        self.owner = json.loads(marker.read_text(encoding="utf-8-sig"))
        if any(self.owner.get(k) != v for k, v in binding.items()) or not re.fullmatch(r"[0-9a-f]{32}", self.owner.get("owner", "")):
            raise PolicyError("owner/project identity mismatch")
        self._locked = False
        for kind in LIMITS:
            self.path(kind).mkdir(exist_ok=True)

    def path(self, kind, *parts):
        if kind not in LIMITS:
            raise PolicyError("unknown output category")
        for value in parts:
            p = Path(value)
            if p.is_absolute() or not p.parts or any(s in ("..", ".") or ":" in s for s in p.parts):
                raise PolicyError("relative contained output required")
        path = plain_path(self.root / kind / Path(*parts))
        if not path.is_relative_to(self.root / kind):
            raise PolicyError("output escaped category")
        return path

    def size(self, path):
        path = plain_path(path)
        if (path != self.root and not path.is_relative_to(self.root)
                and path != plain_path(self.project / "artifacts" / "v3")
                and not self._qa_path_allowed(path)):
            raise PolicyError("size outside managed/game QA tree")
        if not path.exists():
            return 0
        if path.is_file():
            return path.stat().st_size
        total = 0
        pending = [path]
        while pending:
            directory = pending.pop()
            with os.scandir(directory) as entries:
                for entry in entries:
                    info = entry.stat(follow_symlinks=False)
                    if stat.S_ISLNK(info.st_mode) or getattr(info, "st_file_attributes", 0) & 0x400:
                        raise PolicyError("reparse/symlink descendant refused: " + entry.path)
                    if stat.S_ISDIR(info.st_mode):
                        pending.append(Path(entry.path))
                    elif stat.S_ISREG(info.st_mode):
                        total += info.st_size
                    else:
                        raise PolicyError("non-regular managed entry refused: " + entry.path)
        return total

    def _qa_home(self):
        # Match the game's Windows Roaming user-data root, independently of STATE.
        if os.name == "nt":
            buffer = ctypes.create_unicode_buffer(32768)
            if ctypes.windll.shell32.SHGetFolderPathW(None, 0x1A, None, 0, buffer) != 0:
                raise PolicyError("cannot establish actual Roaming directory")
            roaming = Path(buffer.value)
        else:
            if not os.environ.get("APPDATA"):
                raise PolicyError("Roaming APPDATA is unavailable")
            roaming = Path(os.environ["APPDATA"])
        return plain_path(roaming / "LowAltitudeTwinPulseV3")

    def _qa_path_allowed(self, path):
        base = self._qa_home()
        if not path.is_relative_to(base):
            return False
        parts = path.relative_to(base).parts
        if len(parts) >= 2 and parts[0].casefold() == "profiles_v3" and parts[1].casefold().startswith("qa"):
            anchor = base / parts[0] / parts[1]
        elif parts and (parts[0].casefold() == "qa_v3" or parts[0].casefold().startswith("qa_v3_")):
            anchor = base / parts[0]
        else:
            return False
        return not anchor.exists() or anchor.is_dir()

    def qa_usage(self):
        """Metadata only; QA-like names affect accounting, never ownership/removal."""
        base = self._qa_home()
        selected = []
        if base.exists():
            if not base.is_dir():
                raise PolicyError("game Roaming root is not a directory")
            with os.scandir(base) as entries:
                for entry in entries:
                    name = entry.name.casefold()
                    if name == "profiles_v3":
                        profiles = plain_path(entry.path, existing=True)
                        if not profiles.is_dir():
                            raise PolicyError("profiles_v3 is not a directory")
                        with os.scandir(profiles) as profiles_entries:
                            for profile in profiles_entries:
                                if profile.name.casefold().startswith("qa"):
                                    path = plain_path(profile.path, existing=True)
                                    if path.is_dir():
                                        selected.append(path)
                    elif name == "qa_v3" or name.startswith("qa_v3_"):
                        path = plain_path(entry.path, existing=True)
                        if path.is_dir():
                            selected.append(path)
        return {"root": str(base), "used": sum(self.size(p) for p in set(selected)),
                "directories": len(set(selected))}

    def preflight_qa(self, estimated):
        if type(estimated) is not int or estimated < 0:
            raise PolicyError("estimated QA bytes must be nonnegative integer")
        usage = self.qa_usage()
        target = plain_path(usage["root"])
        while not target.exists():
            if target == target.parent:
                raise PolicyError("QA target volume is unavailable")
            target = plain_path(target.parent)
        free = shutil.disk_usage(target).free
        if usage["used"] + estimated > QA_LIMIT:
            raise PolicyError(f"QA quota exceeded: {usage['used']}+{estimated}>{QA_LIMIT}")
        if free < RESERVE + estimated:
            raise PolicyError(f"QA target free-space reserve refused: {free}<{RESERVE}+{estimated}")
        return {"category": "qa_userdata", **usage, "additional": estimated,
                "limit": QA_LIMIT, "free": free, "volume_probe": str(target)}

    def preflight(self, kind, additional):
        if type(additional) is not int or additional < 0:
            raise PolicyError("estimated additional bytes must be nonnegative integer")
        locations = {self.path(kind)}
        if kind == "evidence":
            locations.add(plain_path(self.project / "artifacts" / "v3"))
            locations.add(plain_path(self.root / "authoring"))
        used = sum(self.size(p) for p in locations)
        free = min(shutil.disk_usage(p).free for p in ({self.root, self.project} if kind == "evidence" else {self.root}))
        if used + additional > LIMITS[kind]:
            raise PolicyError(f"{kind} quota exceeded: {used}+{additional}>{LIMITS[kind]}")
        if free < RESERVE + additional:
            raise PolicyError(f"free-space reserve refused: {free}<{RESERVE}+{additional}")
        return {"category": kind, "used": used, "additional": additional, "limit": LIMITS[kind], "free": free}

    @contextmanager
    def lock(self):
        lock = self.root / ".policy.lock"
        plain_path(lock)
        token = uuid.uuid4().hex
        try:
            with lock.open("x", encoding="ascii") as stream:
                stream.write(token)
        except FileExistsError as error:
            raise PolicyError("another operation/stale lock exists; inspect, never auto-break") from error
        self._locked = True
        try:
            yield self
        finally:
            self._locked = False
            plain_path(lock, existing=True)
            if lock.read_text(encoding="ascii") != token:
                raise PolicyError("policy lock ownership changed")
            lock.unlink()

    def _require_lock(self):
        if not self._locked:
            raise PolicyError("mutating operation requires policy.lock()")

    def _owned_child(self, directory, kind, identity):
        directory = plain_path(directory, existing=True)
        if kind == "candidate":
            valid = directory == self.path("builds", self.candidate_id(identity))
        elif kind == "code" and re.fullmatch(r"snapshot-[0-9]{8}_[0-9]{6}-[0-9a-f]{8}", identity):
            valid = directory.parent == self.path("recovery", "code") and directory.name in (identity, ".pending-" + identity)
        else:
            valid = False
        if not valid:
            raise PolicyError("only explicit candidate/code child is owned for removal")
        return directory

    def mark(self, directory, kind, identity):
        self._require_lock()
        directory = self._owned_child(directory, kind, identity)
        atomic_json(directory / ".owned.json", {"owner": self.owner["owner"], "kind": kind, "id": identity})

    def remove_owned(self, directory, kind, identity):
        self._require_lock()
        directory = self._owned_child(directory, kind, identity)
        marker = plain_path(directory / ".owned.json", existing=True)
        expected = {"owner": self.owner["owner"], "kind": kind, "id": identity}
        if json.loads(marker.read_text(encoding="utf-8")) != expected:
            raise PolicyError("owned child marker mismatch")
        self.size(directory)  # Refuse every nested reparse point before recursive deletion.
        plain_path(directory, existing=True)
        shutil.rmtree(directory)

    def _index(self):
        path = self.path("builds", "index.json")
        value = json.loads(path.read_text(encoding="utf-8")) if path.exists() else {"owner": self.owner["owner"], "current": None, "retired": [], "pending": [], "share": None}
        if value.get("owner") != self.owner["owner"]:
            raise PolicyError("build index owner mismatch")
        return value

    @staticmethod
    def candidate_id(value):
        if not re.fullmatch(r"V3Dev[0-9]+Candidate(?:Release)?|V3Development(?:Release)?", value):
            raise PolicyError("invalid explicit candidate id")
        return value

    def begin_candidate(self, identity, estimated_bytes):
        self._require_lock()
        identity = self.candidate_id(identity)
        self.preflight("builds", estimated_bytes)
        target = self.path("builds", identity)
        target.mkdir(exist_ok=False)
        self.mark(target, "candidate", identity)
        index = self._index()
        index.setdefault("pending", []).append(identity)
        atomic_json(self.path("builds", "index.json"), index)
        return target

    def retire_candidates(self, current):
        """Call ONLY after dev's successful export + exact BUILD SHA creation."""
        self._require_lock()
        current = self.candidate_id(current)
        target = self.path("builds", current)
        build = json.loads(plain_path(target / "BUILD.json", existing=True).read_text(encoding="utf-8"))
        exe = plain_path(target / "LowAltitudeTwinPulse-Dev.exe", existing=True)
        if build.get("exe_bytes") != exe.stat().st_size or not re.fullmatch(r"[0-9a-f]{64}", build.get("exe_sha256", "")):
            raise PolicyError("successful exact BUILD metadata required")
        marker = json.loads(plain_path(target / ".owned.json", existing=True).read_text(encoding="utf-8"))
        if marker != {"owner": self.owner["owner"], "kind": "candidate", "id": current}:
            raise PolicyError("current candidate not owned")
        index = self._index()
        if index["current"] and index["current"] != current:
            index["retired"].append(index["current"])
        index["retired"].extend(p for p in index.get("pending", []) if p != current)
        index["pending"] = []
        index["current"] = current
        atomic_json(self.path("builds", "index.json"), index)
        for old in list(dict.fromkeys(index["retired"])):
            old = self.candidate_id(old)
            if old == current:
                raise PolicyError("current candidate cannot be retired")
            source = self.path("builds", old)
            if source.exists():
                self.size(source)
                kept = [source / n for n in ("BUILD.json", "README.md", "VERIFICATION.md", "THIRD_PARTY_NOTICES.md", "licenses") if (source / n).exists()]
                amount = sum(self.size(p) for p in kept)
                if amount > 8 * MiB:
                    raise PolicyError("retirement metadata too large")
                self.preflight("evidence", amount + 4096)
                receipt = self.path("evidence", "retired-builds", old)
                receipt.mkdir(parents=True, exist_ok=True)
                for item in kept:
                    if item.is_dir():
                        shutil.copytree(item, receipt / item.name, dirs_exist_ok=True)
                    else:
                        shutil.copy2(item, receipt / item.name)
                self.remove_owned(source, "candidate", old)
            index["retired"].remove(old)
            atomic_json(self.path("builds", "index.json"), index)
        self.preflight("builds", 0)

    def register_share(self, filename, expected_sha=None):
        """Only one SHA+CRC verified ZIP. Caller preflights BEFORE creating it."""
        self._require_lock()
        if Path(filename).name != filename or not filename.endswith(".zip"):
            raise PolicyError("share must be one explicit ZIP filename")
        path = self.path("builds", "share", filename)
        digest = sha256(path)
        if expected_sha is not None and digest != expected_sha:
            raise PolicyError("share SHA mismatch")
        expected_sha = digest
        with zipfile.ZipFile(path) as archive:
            if archive.testzip() is not None:
                raise PolicyError("share CRC mismatch")
        index = self._index()
        old = index["share"]
        index["share"] = {"file": filename, "sha256": expected_sha, "bytes": path.stat().st_size, "crc_verified": True}
        atomic_json(self.path("builds", "index.json"), index)
        if old and old["file"] != filename:
            if Path(old["file"]).name != old["file"] or not old["file"].endswith(".zip"):
                raise PolicyError("invalid retired share filename")
            retired = self.path("builds", "share", old["file"])
            if retired.is_file() and sha256(retired) == old["sha256"]:
                retired.unlink()
