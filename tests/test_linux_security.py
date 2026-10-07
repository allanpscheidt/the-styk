"""Store/focus regressions using temporary data and no GTK desktop session."""
import importlib
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import types
import unittest
from unittest import mock


sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "TheStyk-Linux" / "src"))
from note_store import NoteStore, UnsafeStorePathError
from models import NoteFrame

# Observer policy does not need GTK. Stub only the D-Bus connection/bootstrap.
fake_repository = types.ModuleType("gi.repository")
fake_repository.GLib = types.SimpleNamespace(timeout_add=lambda *args: None)
fake_repository.Gio = types.SimpleNamespace(
    bus_get_sync=lambda *args: None, BusType=types.SimpleNamespace(SESSION=0))
with mock.patch.dict(sys.modules, {"gi": types.ModuleType("gi"), "gi.repository": fake_repository}):
    observer_module = importlib.import_module("observer")


class StorePrivacyTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="thestyk-linux-security-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.data = self.root / "data"
        env = mock.patch.dict(os.environ, {"THESTYK_DATA_DIR": str(self.data)})
        env.start()
        self.addCleanup(env.stop)

    def store(self):
        store = NoteStore()
        self.addCleanup(store.close)
        return store

    def create(self, store):
        note = store.create_note(str(self.root), NoteFrame(0, 0, 200, 200))
        note.text = "Private classroom note"
        store.save(note)
        return note

    def assert_mode(self, path, expected):
        self.assertEqual(stat.S_IMODE(path.stat().st_mode), expected, str(path))

    def test_permissive_umask_still_creates_private_store_and_trash(self):
        old_umask = os.umask(0)
        try:
            store = self.store()
            note = self.create(store)
            store.move_to_trash(note.id)
            self.assert_mode(self.data / "trash" / f"{note.id}.json", 0o600)
            store.restore_from_trash(note.id)
        finally:
            os.umask(old_umask)
        for directory in (self.data, self.data / "notes", self.data / "trash"):
            self.assert_mode(directory, 0o700)
        self.assert_mode(self.data / "index.json", 0o600)
        self.assert_mode(self.data / "notes" / f"{note.id}.json", 0o600)
        self.assertEqual(store.load_note(note.id).text, note.text)

    def test_existing_permissive_modes_migrate_without_changing_data(self):
        original = self.store()
        note = self.create(original)
        original.close()
        paths = [self.data, self.data / "notes", self.data / "trash",
                 self.data / "index.json", self.data / "notes" / f"{note.id}.json"]
        bytes_before = (self.data / "index.json").read_bytes()
        for path in paths:
            path.chmod(0o777 if path.is_dir() else 0o666)
        reopened = self.store()
        for path in paths:
            self.assert_mode(path, 0o700 if path.is_dir() else 0o600)
        self.assertEqual((self.data / "index.json").read_bytes(), bytes_before)
        self.assertEqual(reopened.load_note(note.id).text, note.text)

    def test_store_root_link_is_rejected_without_changing_target(self):
        target = self.root / "target"
        target.mkdir(mode=0o755)
        target.chmod(0o755)
        self.data.symlink_to(target, target_is_directory=True)
        with self.assertRaises(UnsafeStorePathError):
            NoteStore()
        self.assert_mode(target, 0o755)
        self.assertEqual(list(target.iterdir()), [])

    def test_note_directory_link_is_rejected(self):
        self.data.mkdir()
        target = self.root / "target"
        target.mkdir()
        (self.data / "notes").symlink_to(target, target_is_directory=True)
        with self.assertRaises(UnsafeStorePathError):
            NoteStore()
        self.assertEqual(list(target.iterdir()), [])

    def test_link_in_parent_path_is_rejected(self):
        target = self.root / "target"
        target.mkdir()
        link = self.root / "parent-link"
        link.symlink_to(target, target_is_directory=True)
        with mock.patch.dict(os.environ, {"THESTYK_DATA_DIR": str(link / "data")}):
            with self.assertRaises(UnsafeStorePathError):
                NoteStore()
        self.assertEqual(list(target.iterdir()), [])

    def test_existing_parent_write_permissions_are_rejected_without_chmod(self):
        parent = self.root / "shared-parent"
        parent.mkdir()
        parent.chmod(0o777)
        with mock.patch.dict(os.environ, {"THESTYK_DATA_DIR": str(parent / "data")}):
            with self.assertRaises(UnsafeStorePathError):
                NoteStore()
        self.assert_mode(parent, 0o777)
        self.assertFalse((parent / "data").exists())

    def test_note_symlink_cannot_be_read_written_or_trashed(self):
        store = self.store()
        note = self.create(store)
        note_path = self.data / "notes" / f"{note.id}.json"
        outside = self.root / "outside.json"
        outside.write_bytes(note_path.read_bytes())
        outside.chmod(0o644)
        original_bytes = outside.read_bytes()
        note_path.unlink()
        note_path.symlink_to(outside)
        original_index = (self.data / "index.json").read_bytes()
        with self.assertRaises(UnsafeStorePathError):
            store.load_note(note.id)
        with self.assertRaises(UnsafeStorePathError):
            store.save(note)
        with self.assertRaises(UnsafeStorePathError):
            store.move_to_trash(note.id)
        self.assertEqual(outside.read_bytes(), original_bytes)
        self.assert_mode(outside, 0o644)
        self.assertEqual((self.data / "index.json").read_bytes(), original_index)
        self.assertEqual(len(store.index), 1)

    def test_linked_index_fails_closed_on_reload(self):
        store = self.store()
        note = self.create(store)
        index = self.data / "index.json"
        outside = self.root / "index.json"
        outside.write_bytes(index.read_bytes())
        index.unlink()
        index.symlink_to(outside)
        with self.assertRaises(UnsafeStorePathError):
            store.reload_from_disk()
        self.assertEqual(len(store.index), 1)
        self.assertIn(str(note.id), outside.read_text())

    def test_hardlink_and_special_file_are_rejected_at_migration(self):
        self.data.mkdir()
        notes = self.data / "notes"
        notes.mkdir()
        outside = self.root / "outside.json"
        outside.write_text("{}")
        linked = notes / "linked.json"
        os.link(outside, linked)
        with self.assertRaises(UnsafeStorePathError):
            NoteStore()
        linked.unlink()
        os.mkfifo(notes / "fifo.json", 0o600)
        with self.assertRaises(UnsafeStorePathError):
            NoteStore()

    def test_foreign_owner_is_rejected_before_chmod(self):
        real = self.root.stat()
        foreign = types.SimpleNamespace(st_uid=os.geteuid() + 1,
                                        st_mode=stat.S_IFREG | 0o644, st_nlink=1)
        with self.assertRaises(UnsafeStorePathError):
            NoteStore._verify_owned_file(foreign)
        with mock.patch("note_store.os.fstat", return_value=types.SimpleNamespace(
                st_uid=real.st_uid + 1, st_mode=real.st_mode)), \
                mock.patch("note_store.os.fchmod") as chmod:
            with self.assertRaises(UnsafeStorePathError):
                NoteStore._verify_private_directory(100)
            chmod.assert_not_called()

    def test_directory_replacement_cannot_redirect_write(self):
        store = self.store()
        note = self.create(store)
        notes = self.data / "notes"
        original = self.data / "original-notes"
        notes.rename(original)
        outside = self.root / "outside"
        outside.mkdir()
        notes.symlink_to(outside, target_is_directory=True)
        note.text = "Saved through pinned descriptor"
        store.save(note)
        self.assertEqual(list(outside.iterdir()), [])
        self.assertEqual(json.loads((original / f"{note.id}.json").read_text())["text"], note.text)

    def test_atomic_failure_keeps_original_and_cleans_private_temporary_file(self):
        store = self.store()
        note = self.create(store)
        path = self.data / "notes" / f"{note.id}.json"
        original = path.read_bytes()
        note.text = "Do not commit"
        with mock.patch("note_store.os.replace", side_effect=OSError("injected failure")):
            with self.assertRaises(OSError):
                store.save(note)
        self.assertEqual(path.read_bytes(), original)
        self.assertEqual([p.name for p in path.parent.iterdir()], [path.name])

    def test_file_size_read_is_bounded(self):
        store = self.store()
        path = self.data / "notes" / "oversized.json"
        path.write_bytes(b"x" * 65)
        with self.assertRaises(ValueError):
            store._read_private_file(str(path), 64)


class ForegroundPrivacyTests(unittest.TestCase):
    def observer(self):
        observer = observer_module.FileExplorerObserver()
        observer._last_nautilus_path = "/private/classroom"
        observer._nautilus_last_paths["window"] = "/private/classroom"
        return observer

    def test_unknown_foreground_hides_notes_and_clears_cached_path(self):
        observer = self.observer()
        observer._current_folder = "/private/classroom"
        observer._current_bounds = observer_module.RECT(0, 0, 100, 100)
        changes = []
        observer.register_change_callback(lambda *args: changes.append(args))
        with mock.patch.object(observer, "_get_active_window_info", return_value=(None,) * 4):
            self.assertTrue(observer._poll())
        self.assertEqual(changes, [(None, None)])
        self.assertIsNone(observer._last_nautilus_path)
        self.assertEqual(observer._nautilus_last_paths, {})

    def test_cached_navigation_cannot_show_notes_without_foreground_evidence(self):
        observer = self.observer()
        with mock.patch.object(observer, "_get_active_window_info", return_value=(None,) * 4):
            observer._poll()
        self.assertIsNone(observer.current_folder)

    def test_wayland_does_not_trust_xwayland_active_window(self):
        observer = self.observer()
        with mock.patch.dict(os.environ, {"XDG_SESSION_TYPE": "wayland"}), \
                mock.patch.object(observer_module.subprocess, "check_output") as query:
            self.assertEqual(observer._get_active_window_info(), (None,) * 4)
            observer._poll()
            query.assert_not_called()
        self.assertIsNone(observer.current_folder)

    def test_missing_or_timed_out_xprop_hides_current_notes(self):
        for error in (FileNotFoundError("xprop"), subprocess.TimeoutExpired("xprop", 0.5)):
            observer = self.observer()
            observer._current_folder = "/private/classroom"
            with mock.patch.dict(os.environ, {"XDG_SESSION_TYPE": "x11", "WAYLAND_DISPLAY": ""}), \
                    mock.patch.object(observer_module.subprocess, "check_output", side_effect=error) as query:
                observer._poll()
                self.assertEqual(query.call_args.kwargs["timeout"], 0.5)
            self.assertIsNone(observer.current_folder)
            self.assertIsNone(observer._last_nautilus_path)

    def test_verified_file_manager_shows_notes_and_focus_change_hides_them(self):
        observer = self.observer()
        bounds = observer_module.RECT(0, 0, 100, 100)
        changes = []
        observer.register_change_callback(lambda *args: changes.append(args))
        with mock.patch.object(observer, "_get_active_window_info", return_value=("0x1", "Nautilus", "", bounds)):
            observer._poll()
        self.assertEqual(observer.current_folder, "/private/classroom")
        with mock.patch.object(observer, "_get_active_window_info", return_value=("0x2", "Browser", "", bounds)):
            observer._poll()
        self.assertEqual(changes, [("/private/classroom", bounds), (None, None)])


if __name__ == "__main__":
    unittest.main()
