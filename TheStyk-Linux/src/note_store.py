import os
import json
import uuid
import shutil
from datetime import datetime, timedelta
from typing import List, Dict, Optional, Callable
from models import Note, NoteStyle, NoteFrame, IndexEntry, TrashEntry, NoteColor, NoteFontID, parse_iso_datetime, format_iso_datetime

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
            self._data_dir = env_dir
        else:
            self._data_dir = os.path.join(os.path.expanduser("~"), ".config", "the-styk")

        self._notes_dir = os.path.join(self._data_dir, "notes")
        self._trash_dir = os.path.join(self._data_dir, "trash")
        self._index_file = os.path.join(self._data_dir, "index.json")

        os.makedirs(self._data_dir, exist_ok=True)
        os.makedirs(self._notes_dir, exist_ok=True)
        os.makedirs(self._trash_dir, exist_ok=True)

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
        self._index.clear()
        self._trash.clear()

        loaded_index, loaded_trash = self._load_index_file(self._index_file)
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
        if not os.path.exists(path):
            print(f"[NoteStore] LoadNote falhou: Arquivo nao existe em '{path}'")
            return None

        try:
            sz = os.path.getsize(path)
            if sz > self.max_note_bytes:
                print(f"[NoteStore] LoadNote falhou: Tamanho do arquivo {sz} excede o limite {self.max_note_bytes}")
                return None

            with open(path, "rb") as f:
                data = f.read()

            if len(data) > self.max_note_bytes:
                print(f"[NoteStore] LoadNote falhou: Tamanho dos bytes {len(data)} excede o limite {self.max_note_bytes}")
                return None

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
        del self._index[idx]

        source_path = self._get_note_path(note_id)
        dest_path = os.path.join(self._trash_dir, f"{note_id}.json")

        try:
            if os.path.exists(dest_path):
                os.remove(dest_path)
            if os.path.exists(source_path):
                shutil.move(source_path, dest_path)
                self._trash.append(TrashEntry(
                    id=entry.id,
                    folder=entry.folder,
                    snippet=entry.snippet,
                    color=entry.color,
                    deletedAt=datetime.utcnow()
                ))
        except Exception as ex:
            print(f"[NoteStore] Falha ao mover nota {note_id} para lixeira: {ex}")
            if os.path.exists(source_path):
                try:
                    os.remove(source_path)
                except Exception:
                    pass

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

        try:
            if os.path.exists(source_path):
                if os.path.exists(dest_path):
                    os.remove(dest_path)
                shutil.move(source_path, dest_path)
        except Exception as ex:
            print(f"[NoteStore] Falha ao restaurar nota {note_id}: {ex}")
            return

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
        self._trash = [t for t in self._trash if t.id != note_id]
        trash_path = os.path.join(self._trash_dir, f"{note_id}.json")
        try:
            if os.path.exists(trash_path):
                os.remove(trash_path)
        except Exception:
            pass

        self._write_index()
        self.post_index_did_change()

    def empty_trash(self):
        for t in self._trash:
            path = os.path.join(self._trash_dir, f"{t.id}.json")
            try:
                if os.path.exists(path):
                    os.remove(path)
            except Exception:
                pass
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
            try:
                if os.path.exists(path):
                    os.remove(path)
            except Exception:
                pass

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
        try:
            path = self._get_note_path(note.id)
            json_str = json.dumps(note.to_dict(), indent=2, ensure_ascii=False)
            self._write_file_atomic(path, json_str)
        except Exception as e:
            print(f"[NoteStore] Falha ao gravar nota {note.id}: {e}")

    def _write_index(self):
        try:
            root = {
                "version": 1,
                "notes": [e.to_dict() for e in self._index],
                "trash": [t.to_dict() for t in self._trash]
            }
            json_str = json.dumps(root, indent=2, ensure_ascii=False)
            self._write_file_atomic(self._index_file, json_str)
        except Exception as e:
            print(f"[NoteStore] Falha ao gravar index.json: {e}")

    @staticmethod
    def _write_file_atomic(file_path: str, content: str):
        temp_path = file_path + ".tmp"
        with open(temp_path, "w", encoding="utf-8") as f:
            f.write(content)

        # Atomic replacement
        try:
            if os.path.exists(file_path):
                os.replace(temp_path, file_path)
            else:
                os.rename(temp_path, file_path)
        except Exception:
            shutil.copy(temp_path, file_path)
            try:
                os.remove(temp_path)
            except Exception:
                pass

    def _load_index_file(self, path: str) -> tuple:
        entries = []
        trashed = []

        if not os.path.exists(path):
            return entries, trashed

        try:
            sz = os.path.getsize(path)
            if sz > self.max_index_bytes:
                return entries, trashed

            with open(path, "rb") as f:
                data = f.read()

            if len(data) > self.max_index_bytes:
                return entries, trashed

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
