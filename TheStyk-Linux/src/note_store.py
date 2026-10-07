import os
import json
import uuid
import stat
from datetime import datetime, timedelta
from typing import List, Dict, Optional, Callable
from models import Note, NoteStyle, NoteFrame, IndexEntry, TrashEntry, NoteColor, NoteFontID, parse_iso_datetime, format_iso_datetime


class UnsafeStorePathError(PermissionError):
    """The store contains a link, special file, or another account's object."""


class NoteStore:
    _instance: Optional["NoteStore"] = None

    @classmethod
    def get_shared(cls) -> "NoteStore":
        if cls._instance is None:
            cls._instance = cls()
        return cls._instance

    def __init__(self):
        self.index_changed_callbacks: List[Callable[[], None]] = []
        
        self.max_note_bytes = 2 * 1024 * 1024  # 2 MB
        self.max_index_bytes = 5 * 1024 * 1024  # 5 MB
        self.max_entries = 10000
        self.max_text_chars = 200000
        self.trash_retention = timedelta(days=5)

        # Custom env data dir (for tests)
        env_dir = os.environ.get("THESTYK_DATA_DIR")
        if env_dir:
            self._data_dir = os.path.abspath(env_dir)
        else:
            self._data_dir = os.path.join(os.path.expanduser("~"), ".config", "the-styk")

        self._notes_dir = os.path.join(self._data_dir, "notes")
        self._trash_dir = os.path.join(self._data_dir, "trash")
        self._index_file = os.path.join(self._data_dir, "index.json")

        # Keep directory descriptors for all I/O. A later path replacement cannot
        # redirect reads or writes outside these verified, owner-only directories.
        self._directory_fds = {}
        try:
            root_fd = self._open_store_root(self._data_dir)
            self._directory_fds[self._data_dir] = root_fd
            self._directory_fds[self._notes_dir] = self._open_private_directory("notes", root_fd)
            self._directory_fds[self._trash_dir] = self._open_private_directory("trash", root_fd)
            self._migrate_store_permissions()
        except Exception:
            self.close()
            raise

        self._index: List[IndexEntry] = []
        self._trash: List[TrashEntry] = []
        self._last_reconcile: datetime = datetime.min

        self.reload_from_disk()
        self.purge_expired_trash()

    def register_callback(self, callback: Callable[[], None]):
        if callback not in self.index_changed_callbacks:
            self.index_changed_callbacks.append(callback)

    def unregister_callback(self, callback: Callable[[], None]):
        if callback in self.index_changed_callbacks:
            self.index_changed_callbacks.remove(callback)

    def post_index_did_change(self):
        for cb in self.index_changed_callbacks:
            try:
                cb()
            except Exception as e:
                print(f"[NoteStore] Error in callback: {e}")

    @property
    def index(self) -> List[IndexEntry]:
        return self._index

    @property
    def trash(self) -> List[TrashEntry]:
        return self._trash

    def reload_from_disk(self):
        loaded_index, loaded_trash = self._load_index_file(self._index_file)
        self._index.clear()
        self._trash.clear()
        self._index.extend(loaded_index)
        self._trash.extend(loaded_trash)
        self.post_index_did_change()

    @staticmethod
    def normalize_path(path: str) -> str:
        if not path:
            return ""
        # POSIX normalize
        normalized = path.replace("\\", "/")
        if normalized.endswith("/") and len(normalized) > 1:
            normalized = normalized.rstrip("/")
        return normalized

    # MARK: - Queries
    def entries(self, folder: str) -> List[IndexEntry]:
        normalized = self.normalize_path(folder)
        return [e for e in self._index if e.folder.lower() == normalized.lower()]

    def folders(self) -> List[str]:
        # Return unique non-orphaned folders, sorted alphabetically
        unique_folders = set(e.folder for e in self._index if e.orphaned is not True)
        return sorted(list(unique_folders), key=lambda x: x.lower())

    def orphans(self) -> List[IndexEntry]:
        return [e for e in self._index if e.orphaned is True]

    # MARK: - Note Lazy Load
    def load_note(self, note_id: uuid.UUID) -> Optional[Note]:
        path = self._get_note_path(note_id)
        try:
            data = self._read_private_file(path, self.max_note_bytes)

            # Handle UTF-8 BOM
            if data.startswith(b"\xef\xbb\xbf"):
                data = data[3:]

            d = json.loads(data.decode("utf-8"))
            if not d:
                print(f"[NoteStore] LoadNote falhou: Deserializacao JSON retornou null")
                return None

            note = Note.from_dict(d)
            if note.id != note_id:
                print(f"[NoteStore] LoadNote falhou: ID nao bate")
                return None

            # Guardrails
            if not note.folder:
                print(f"[NoteStore] LoadNote falhou: Folder esta vazio")
                return None

            note.folder = self.normalize_path(note.folder)
            if len(note.text) > self.max_text_chars:
                note.text = note.text[:self.max_text_chars]

            note.style.fontSize = max(8.0, min(float(note.style.fontSize), 72.0))
            note.frame.x = float(note.frame.x) if hasattr(note.frame, "x") and note.frame.x is not None else 0.0
            note.frame.y = float(note.frame.y) if hasattr(note.frame, "y") and note.frame.y is not None else 0.0
            note.frame.w = max(120.0, min(float(note.frame.w), 4000.0))
            note.frame.h = max(120.0, min(float(note.frame.h), 4000.0))

            return note
        except UnsafeStorePathError:
            raise
        except Exception as e:
            print(f"[NoteStore] Erro ao carregar nota {note_id}: {e}")
            return None

    # MARK: - Mutations
    def create_note(self, folder: str, frame: NoteFrame) -> Note:
        now = datetime.utcnow()
        note = Note(
            id=uuid.uuid4(),
            folder=self.normalize_path(folder),
            text="",
            style=NoteStyle(color=NoteColor.yellow, fontID=NoteFontID.system, fontSize=14.0),
            frame=frame,
            created=now,
            modified=now
        )
        self._write_note_file(note)
        self._index.append(self._create_index_entry(note))
        self._write_index()
        self.post_index_did_change()
        return note

    def save(self, note: Note):
        note.modified = datetime.utcnow()
        note.folder = self.normalize_path(note.folder)
        if len(note.text) > self.max_text_chars:
            note.text = note.text[:self.max_text_chars]

        self._write_note_file(note)

        entry = self._create_index_entry(note)
        idx = -1
        for i, e in enumerate(self._index):
            if e.id == note.id:
                idx = i
                break

        if idx >= 0:
            self._index[idx] = entry
        else:
            self._index.append(entry)

        self._write_index()
        self.post_index_did_change()

    # MARK: - Trash
    def move_to_trash(self, note_id: uuid.UUID):
        idx = -1
        for i, e in enumerate(self._index):
            if e.id == note_id:
                idx = i
                break
        if idx < 0:
            return

        entry = self._index[idx]
        source_path = self._get_note_path(note_id)
        dest_path = os.path.join(self._trash_dir, f"{note_id}.json")
        self._move_private_file(source_path, dest_path)
        del self._index[idx]
        self._trash.append(TrashEntry(
            id=entry.id,
            folder=entry.folder,
            snippet=entry.snippet,
            color=entry.color,
            deletedAt=datetime.utcnow()
        ))

        self._write_index()
        self.post_index_did_change()

    def restore_from_trash(self, note_id: uuid.UUID):
        idx = -1
        for i, t in enumerate(self._trash):
            if t.id == note_id:
                idx = i
                break
        if idx < 0:
            return

        trash_entry = self._trash[idx]
        source_path = os.path.join(self._trash_dir, f"{note_id}.json")
        dest_path = self._get_note_path(note_id)

        self._move_private_file(source_path, dest_path)

        del self._trash[idx]
        folder_exists = os.path.isdir(trash_entry.folder)

        self._index.append(IndexEntry(
            id=trash_entry.id,
            folder=trash_entry.folder,
            snippet=trash_entry.snippet,
            color=trash_entry.color,
            modified=datetime.utcnow(),
            orphaned=None if folder_exists else True
        ))

        self._write_index()
        self.post_index_did_change()

    def delete_permanently(self, note_id: uuid.UUID):
        trash_path = os.path.join(self._trash_dir, f"{note_id}.json")
        self._remove_private_file(trash_path)
        self._trash = [t for t in self._trash if t.id != note_id]

        self._write_index()
        self.post_index_did_change()

    def empty_trash(self):
        for t in self._trash:
            path = os.path.join(self._trash_dir, f"{t.id}.json")
            self._remove_private_file(path)
        self._trash.clear()
        self._write_index()
        self.post_index_did_change()

    def purge_expired_trash(self):
        cutoff = datetime.utcnow() - self.trash_retention
        expired = [t for t in self._trash if t.deletedAt < cutoff]
        if not expired:
            return

        for t in expired:
            path = os.path.join(self._trash_dir, f"{t.id}.json")
            self._remove_private_file(path)

        self._trash = [t for t in self._trash if t.deletedAt >= cutoff]
        self._write_index()
        self.post_index_did_change()

    # MARK: - Anchors
    def reattach(self, note_id: uuid.UUID, to_folder: str):
        note = self.load_note(note_id)
        if not note:
            return

        normalized = self.normalize_path(to_folder)
        note.folder = normalized
        note.modified = datetime.utcnow()

        self._write_note_file(note)

        for entry in self._index:
            if entry.id == note_id:
                entry.folder = normalized
                entry.orphaned = None
                entry.modified = note.modified
                break

        self._write_index()
        self.post_index_did_change()

    def reconcile_anchors_if_stale(self):
        if (datetime.utcnow() - self._last_reconcile).total_seconds() > 30:
            self.reconcile_anchors()

    def reconcile_anchors(self):
        self._last_reconcile = datetime.utcnow()
        changed = False

        unique_folders = set(e.folder for e in self._index)
        for folder in unique_folders:
            exists = os.path.isdir(folder)
            is_orphan = any(e.folder.lower() == folder.lower() and e.orphaned is True for e in self._index)

            if exists:
                if is_orphan:
                    for entry in self._index:
                        if entry.folder.lower() == folder.lower():
                            entry.orphaned = None
                    changed = True
            else:
                if not is_orphan:
                    for entry in self._index:
                        if entry.folder.lower() == folder.lower():
                            entry.orphaned = True
                    changed = True

        if changed:
            self._write_index()
            self.post_index_did_change()

    # MARK: - Disk Helpers
    def _get_note_path(self, note_id: uuid.UUID) -> str:
        return os.path.join(self._notes_dir, f"{note_id}.json")

    def _write_note_file(self, note: Note):
        path = self._get_note_path(note.id)
        json_str = json.dumps(note.to_dict(), indent=2, ensure_ascii=False)
        self._write_file_atomic(path, json_str)

    def _write_index(self):
        root = {
            "version": 1,
            "notes": [e.to_dict() for e in self._index],
            "trash": [t.to_dict() for t in self._trash]
        }
        json_str = json.dumps(root, indent=2, ensure_ascii=False)
        self._write_file_atomic(self._index_file, json_str)

    def close(self):
        for fd in getattr(self, "_directory_fds", {}).values():
            os.close(fd)
        self._directory_fds = {}

    def __del__(self):
        try:
            self.close()
        except Exception:
            pass

    @staticmethod
    def _verify_owned_file(info):
        if info.st_uid != os.geteuid() or not stat.S_ISREG(info.st_mode) or info.st_nlink != 1:
            raise UnsafeStorePathError("Store files must be regular, singly linked, and owned by this account")

    @staticmethod
    def _verify_private_directory(fd):
        info = os.fstat(fd)
        if info.st_uid != os.geteuid() or not stat.S_ISDIR(info.st_mode):
            raise UnsafeStorePathError("Store directories must be owned by this account")
        os.fchmod(fd, 0o700)

    @classmethod
    def _open_private_directory(cls, path, parent_fd=None):
        try:
            os.mkdir(path, mode=0o700, dir_fd=parent_fd)
        except FileExistsError:
            pass
        try:
            fd = os.open(path, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC, dir_fd=parent_fd)
        except OSError as error:
            raise UnsafeStorePathError("Cannot open a private store directory safely") from error
        try:
            cls._verify_private_directory(fd)
            return fd
        except Exception:
            os.close(fd)
            raise

    @classmethod
    def _open_store_root(cls, path):
        # Walk parents without following links. Existing system-owned ancestors
        # may be shared (e.g. /home or sticky /tmp); the application root itself
        # must belong to this account. Do not chmod shared parent directories.
        components = os.path.abspath(path).split(os.sep)[1:]
        if not components or not components[-1]:
            raise UnsafeStorePathError("The filesystem root cannot be a note store")
        flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC
        parent_fd = os.open(os.sep, flags)
        try:
            for component in components[:-1]:
                try:
                    child_fd = os.open(component, flags, dir_fd=parent_fd)
                except FileNotFoundError:
                    try:
                        os.mkdir(component, mode=0o700, dir_fd=parent_fd)
                    except FileExistsError:
                        pass
                    child_fd = os.open(component, flags, dir_fd=parent_fd)
                except OSError as error:
                    raise UnsafeStorePathError("Store parent paths cannot contain links or special files") from error
                info = os.fstat(child_fd)
                unsafe_write = info.st_mode & 0o022 and not (
                    info.st_uid == 0 and info.st_mode & stat.S_ISVTX)
                if info.st_uid not in (0, os.geteuid()) or unsafe_write:
                    os.close(child_fd)
                    raise UnsafeStorePathError("Store parent directory has unsafe ownership or write permissions")
                os.close(parent_fd)
                parent_fd = child_fd
            return cls._open_private_directory(components[-1], parent_fd)
        finally:
            os.close(parent_fd)

    def _file_location(self, path):
        absolute_path = os.path.abspath(path)
        parent = os.path.dirname(absolute_path)
        if parent not in self._directory_fds:
            raise UnsafeStorePathError("File is outside the managed store")
        fd = self._directory_fds[parent]
        self._verify_private_directory(fd)
        return fd, os.path.basename(absolute_path)

    def _open_private_file(self, path):
        parent_fd, name = self._file_location(path)
        try:
            # NONBLOCK prevents FIFO/device paths from hanging before fstat.
            fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC, dir_fd=parent_fd)
        except FileNotFoundError:
            raise
        except OSError as error:
            raise UnsafeStorePathError("Cannot open a store file safely") from error
        try:
            self._verify_owned_file(os.fstat(fd))
            os.fchmod(fd, 0o600)
            return fd
        except Exception:
            os.close(fd)
            raise

    def _verify_existing_file(self, path):
        try:
            fd = self._open_private_file(path)
        except FileNotFoundError:
            return False
        os.close(fd)
        return True

    def _migrate_store_permissions(self):
        # Existing permissive files are tightened before the index is loaded.
        self._verify_existing_file(self._index_file)
        self._verify_existing_file(self._index_file + ".tmp")
        for directory in (self._notes_dir, self._trash_dir):
            for name in os.listdir(self._directory_fds[directory]):
                self._verify_existing_file(os.path.join(directory, name))

    def _read_private_file(self, path, max_bytes):
        fd = self._open_private_file(path)
        with os.fdopen(fd, "rb") as file:
            if os.fstat(file.fileno()).st_size > max_bytes:
                raise ValueError("Store file exceeds the size limit")
            data = file.read(max_bytes + 1)
        if len(data) > max_bytes:
            raise ValueError("Store file exceeds the size limit")
        return data

    def _write_file_atomic(self, file_path: str, content: str):
        parent_fd, name = self._file_location(file_path)
        self._verify_existing_file(file_path)
        # No predictable .tmp file, no following links, and no copy fallback.
        temp_name = f".{name}.{uuid.uuid4().hex}.tmp"
        fd = os.open(temp_name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC,
                     0o600, dir_fd=parent_fd)
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as file:
                os.fchmod(file.fileno(), 0o600)
                file.write(content)
                file.flush()
                os.fsync(file.fileno())
            self._verify_existing_file(file_path)
            os.replace(temp_name, name, src_dir_fd=parent_fd, dst_dir_fd=parent_fd)
            os.fsync(parent_fd)
        finally:
            try:
                os.unlink(temp_name, dir_fd=parent_fd)
            except FileNotFoundError:
                pass

    def _move_private_file(self, source_path, destination_path):
        source_fd, source_name = self._file_location(source_path)
        destination_fd, destination_name = self._file_location(destination_path)
        if not self._verify_existing_file(source_path):
            raise FileNotFoundError(source_path)
        self._verify_existing_file(destination_path)
        os.replace(source_name, destination_name, src_dir_fd=source_fd, dst_dir_fd=destination_fd)
        os.fsync(source_fd)
        os.fsync(destination_fd)

    def _remove_private_file(self, path):
        parent_fd, name = self._file_location(path)
        if self._verify_existing_file(path):
            os.unlink(name, dir_fd=parent_fd)
            os.fsync(parent_fd)

    def _load_index_file(self, path: str) -> tuple:
        entries = []
        trashed = []

        try:
            data = self._read_private_file(path, self.max_index_bytes)

            if data.startswith(b"\xef\xbb\xbf"):
                data = data[3:]

            root = json.loads(data.decode("utf-8"))
            if not root or not isinstance(root, dict):
                return entries, trashed

            if "notes" in root and isinstance(root["notes"], list):
                for item in root["notes"]:
                    if len(entries) >= self.max_entries:
                        break
                    try:
                        entry = IndexEntry.from_dict(item)
                        if entry.folder:
                            entry.folder = self.normalize_path(entry.folder)
                            entry.snippet = self.make_snippet(entry.snippet)
                            entries.append(entry)
                    except Exception:
                        pass

            if "trash" in root and isinstance(root["trash"], list):
                for item in root["trash"]:
                    if len(trashed) >= self.max_entries:
                        break
                    try:
                        entry = TrashEntry.from_dict(item)
                        if entry.folder:
                            entry.folder = self.normalize_path(entry.folder)
                            entry.snippet = self.make_snippet(entry.snippet)
                            trashed.append(entry)
                    except Exception:
                        pass

        except UnsafeStorePathError:
            raise
        except Exception:
            pass

        return entries, trashed

    def _create_index_entry(self, note: Note) -> IndexEntry:
        return IndexEntry(
            id=note.id,
            folder=note.folder,
            snippet=self.make_snippet(note.text),
            color=note.style.color,
            modified=note.modified
        )

    @staticmethod
    def make_snippet(text: str) -> str:
        if not text:
            return "Nota vazia"

        lines = text.splitlines()
        for line in lines:
            # Strip control characters
            clean = "".join(c for c in line if ord(c) >= 32 and ord(c) != 127).strip()
            if clean:
                return clean[:60] if len(clean) > 60 else clean

        return "Nota vazia"
