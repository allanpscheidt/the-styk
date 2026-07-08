import os
import sys
import uuid
import subprocess
from datetime import datetime
import gi
gi.require_version('Gtk', '3.0')
from gi.repository import Gtk, Gdk, GdkPixbuf

from models import Note, NoteColor, NoteFrame, IndexEntry, TrashEntry
from note_store import NoteStore
from window_manager import NoteWindowManager
import theme

# Try to import AppIndicator or AyatanaAppIndicator for system tray
AppIndicator = None
try:
    gi.require_version('AppIndicator3', '0.1')
    from gi.repository import AppIndicator3 as AppIndicator
except (ImportError, ValueError):
    try:
        gi.require_version('AyatanaAppIndicator3', '0.1')
        from gi.repository import AyatanaAppIndicator3 as AppIndicator
    except (ImportError, ValueError):
        pass

COLOR_EMOJIS = {
    NoteColor.yellow: "🟡",
    NoteColor.pink: "💗",
    NoteColor.blue: "🔵",
    NoteColor.green: "🟢",
    NoteColor.orange: "🟠",
    NoteColor.purple: "🟣",
}

class SystemTrayController:
    def __init__(self, observer):
        self.observer = observer
        self.store = NoteStore.get_shared()
        self.window_manager = NoteWindowManager.get_shared()
        
        # Register for changes to automatically refresh the menu
        self.store.register_callback(self.rebuild_menu)
        # Register for active folder changes to update "Nova nota em..."
        self.observer.register_change_callback(self._on_observer_folder_changed)
        
        self.menu = Gtk.Menu()
        self.indicator = None
        self.status_icon = None

        self._setup_tray()
        self.rebuild_menu()

    def _setup_tray(self):
        # Use standard system icon name 'accessories-text-editor' or 'sticky-note-symbolic'
        icon_name = "accessories-text-editor"

        if AppIndicator:
            print("[Tray] Using AppIndicator3 for system tray.")
            self.indicator = AppIndicator.Indicator.new(
                "the-styk",
                icon_name,
                AppIndicator.IndicatorCategory.APPLICATION_STATUS
            )
            self.indicator.set_status(AppIndicator.IndicatorStatus.ACTIVE)
            self.indicator.set_menu(self.menu)
        else:
            print("[Tray] Falling back to Gtk.StatusIcon for system tray.")
            self.status_icon = Gtk.StatusIcon()
            self.status_icon.set_from_icon_name(icon_name)
            self.status_icon.set_tooltip_text("The Styk")
            self.status_icon.connect("popup-menu", self._on_status_icon_popup)

    def _on_status_icon_popup(self, status_icon, button, activate_time):
        self.rebuild_menu()
        self.menu.popup(None, None, None, None, button, activate_time)

    def rebuild_menu(self):
        # Clear existing menu items
        for child in self.menu.get_children():
            self.menu.remove(child)

        # 1. New note in this folder
        current_folder = self.observer.current_folder
        if current_folder:
            folder_name = os.path.basename(current_folder) or current_folder
            item_new = Gtk.MenuItem(label=f"Nova nota em '{folder_name}'")
            item_new.connect("activate", self._on_new_note_clicked, current_folder)
        else:
            item_new = Gtk.MenuItem(label="Abra uma pasta no Gerenciador de Arquivos para criar uma nota")
            item_new.set_sensitive(False)
        self.menu.append(item_new)

        self.menu.append(Gtk.SeparatorMenuItem())

        # 2. Notes Section Header
        notes_header = Gtk.MenuItem(label=f"Notas ({len(self.store.index)})")
        notes_header.set_sensitive(False)
        self.menu.append(notes_header)

        # Group index entries by folder
        folders = self.store.folders()
        for folder_path in folders:
            entries = self.store.entries(folder_path)
            if not entries:
                continue

            # Format folder path for menu (contract home dir)
            display_folder = folder_path
            home_dir = os.path.expanduser("~")
            if folder_path.startswith(home_dir):
                display_folder = folder_path.replace(home_dir, "~", 1)

            folder_menu = Gtk.Menu()
            folder_sub_item = Gtk.MenuItem(label=display_folder)
            folder_sub_item.set_submenu(folder_menu)

            # Folder Action: Open Folder
            item_open_dir = Gtk.MenuItem(label="Abrir pasta no Gerenciador de Arquivos")
            if os.path.isdir(folder_path):
                item_open_dir.connect("activate", self._on_open_folder_clicked, folder_path)
            else:
                item_open_dir.set_sensitive(False)
            folder_menu.append(item_open_dir)
            folder_menu.append(Gtk.SeparatorMenuItem())

            # Notes under this folder
            for entry in entries:
                emoji = COLOR_EMOJIS.get(entry.color, "🟡")
                note_item = Gtk.MenuItem(label=f"{emoji} {entry.snippet}")
                
                note_menu = Gtk.Menu()
                note_item.set_submenu(note_menu)

                # Actions inside note
                item_show = Gtk.MenuItem(label="Abrir nota")
                item_show.connect("activate", self._on_show_note, entry.id)
                note_menu.append(item_show)

                item_export = Gtk.MenuItem(label="Exportar...")
                item_export.connect("activate", self._on_export_note, entry.id)
                note_menu.append(item_export)

                item_delete = Gtk.MenuItem(label="Apagar...")
                item_delete.connect("activate", self._on_delete_note, entry.id)
                note_menu.append(item_delete)

                folder_menu.append(note_item)

            self.menu.append(folder_sub_item)

        # 3. Orphan Notes Section
        orphans = self.store.orphans()
        if orphans:
            self.menu.append(Gtk.SeparatorMenuItem())
            orphans_menu = Gtk.Menu()
            orphans_sub_item = Gtk.MenuItem(label=f"Notas Órfãs ({len(orphans)})")
            orphans_sub_item.set_submenu(orphans_menu)

            for entry in orphans:
                emoji = COLOR_EMOJIS.get(entry.color, "🟡")
                note_item = Gtk.MenuItem(label=f"{emoji} {entry.snippet}")
                
                note_menu = Gtk.Menu()
                note_item.set_submenu(note_menu)

                item_reattach = Gtk.MenuItem(label="Reancorar a uma pasta...")
                item_reattach.connect("activate", self._on_reattach_note, entry.id)
                note_menu.append(item_reattach)

                item_export = Gtk.MenuItem(label="Exportar...")
                item_export.connect("activate", self._on_export_note, entry.id)
                note_menu.append(item_export)

                item_delete = Gtk.MenuItem(label="Apagar...")
                item_delete.connect("activate", self._on_delete_note, entry.id)
                note_menu.append(item_delete)

                orphans_menu.append(note_item)

            self.menu.append(orphans_sub_item)

        # 4. Trash Section
        trash = self.store.trash
        if trash:
            self.menu.append(Gtk.SeparatorMenuItem())
            trash_menu = Gtk.Menu()
            trash_sub_item = Gtk.MenuItem(label=f"Lixeira ({len(trash)})")
            trash_sub_item.set_submenu(trash_menu)

            item_empty = Gtk.MenuItem(label="Esvaziar lixeira...")
            item_empty.connect("activate", self._on_empty_trash)
            trash_menu.append(item_empty)
            trash_menu.append(Gtk.SeparatorMenuItem())

            for entry in trash:
                emoji = COLOR_EMOJIS.get(entry.color, "🟡")
                note_item = Gtk.MenuItem(label=f"{emoji} {entry.snippet}")
                
                note_menu = Gtk.Menu()
                note_item.set_submenu(note_menu)

                item_restore = Gtk.MenuItem(label="Restaurar")
                item_restore.connect("activate", self._on_restore_note, entry.id)
                note_menu.append(item_restore)

                item_purge = Gtk.MenuItem(label="Apagar permanentemente")
                item_purge.connect("activate", self._on_purge_note, entry.id)
                note_menu.append(item_purge)

                trash_menu.append(note_item)

            self.menu.append(trash_sub_item)

        self.menu.append(Gtk.SeparatorMenuItem())

        # 5. About
        item_about = Gtk.MenuItem(label="Sobre o The Styk")
        item_about.connect("activate", self._on_about_clicked)
        self.menu.append(item_about)

        # 6. Exit
        item_exit = Gtk.MenuItem(label="Sair do The Styk")
        item_exit.connect("activate", self._on_exit_clicked)
        self.menu.append(item_exit)

        self.menu.show_all()
        if self.indicator:
            self.indicator.set_menu(self.menu)

    def _on_observer_folder_changed(self, folder, bounds):
        self.rebuild_menu()

    # MARK: - Actions Callback
    def _on_new_note_clicked(self, menu_item, folder_path):
        frame = self.window_manager.suggested_frame()
        note = self.store.create_note(folder_path, frame)
        self.window_manager.show_note_window(note)

    def _on_open_folder_clicked(self, menu_item, folder_path):
        try:
            subprocess.Popen(["xdg-open", folder_path])
        except Exception as e:
            print(f"[Tray] Error opening folder: {e}")

    def _on_show_note(self, menu_item, note_id):
        note = self.store.load_note(note_id)
        if note:
            self.window_manager.show_note_window(note)

    def _on_export_note(self, menu_item, note_id):
        # Open file chooser directly from tray
        note = self.store.load_note(note_id)
        if not note:
            return

        dialog = Gtk.FileChooserDialog(
            title="Exportar Nota",
            action=Gtk.FileChooserAction.SAVE
        )
        dialog.add_buttons(
            Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL,
            Gtk.STOCK_SAVE, Gtk.ResponseType.OK
        )
        dialog.set_do_overwrite_confirmation(True)
        
        snippet = NoteStore.make_snippet(note.text)
        import re
        sanitized = re.sub(r'[/\\:*?"<>|]', "", snippet)
        sanitized = sanitized[:40] if len(sanitized) > 40 else sanitized
        dialog.set_current_name(f"The Styk – {sanitized}.txt")
        
        response = dialog.run()
        if response == Gtk.ResponseType.OK:
            filepath = dialog.get_filename()
            try:
                with open(filepath, "w", encoding="utf-8") as f:
                    f.write(note.text)
            except Exception as e:
                err_dialog = Gtk.MessageDialog(
                    message_type=Gtk.MessageType.ERROR,
                    buttons=Gtk.ButtonsType.OK,
                    text=f"Erro ao exportar arquivo:\n{e}"
                )
                err_dialog.run()
                err_dialog.destroy()
        dialog.destroy()

    def _on_delete_note(self, menu_item, note_id):
        dialog = Gtk.MessageDialog(
            message_type=Gtk.MessageType.QUESTION,
            buttons=Gtk.ButtonsType.YES_NO,
            text="Apagar esta nota?"
        )
        dialog.format_secondary_text("A nota será enviada para a lixeira interna do The Styk.")
        response = dialog.run()
        dialog.destroy()
        
        if response == Gtk.ResponseType.YES:
            self.store.move_to_trash(note_id)

    def _on_reattach_note(self, menu_item, note_id):
        dialog = Gtk.FileChooserDialog(
            title="Selecionar nova pasta para a nota",
            action=Gtk.FileChooserAction.SELECT_FOLDER
        )
        dialog.add_buttons(
            Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL,
            Gtk.STOCK_OPEN, Gtk.ResponseType.OK
        )
        response = dialog.run()
        if response == Gtk.ResponseType.OK:
            folder_path = dialog.get_filename()
            self.store.reattach(note_id, folder_path)
        dialog.destroy()

    def _on_restore_note(self, menu_item, note_id):
        self.store.restore_from_trash(note_id)

    def _on_purge_note(self, menu_item, note_id):
        dialog = Gtk.MessageDialog(
            message_type=Gtk.MessageType.QUESTION,
            buttons=Gtk.ButtonsType.YES_NO,
            text="Apagar esta nota permanentemente?"
        )
        dialog.format_secondary_text("Esta ação é irreversível.")
        response = dialog.run()
        dialog.destroy()
        
        if response == Gtk.ResponseType.YES:
            self.store.delete_permanently(note_id)

    def _on_empty_trash(self, menu_item):
        dialog = Gtk.MessageDialog(
            message_type=Gtk.MessageType.QUESTION,
            buttons=Gtk.ButtonsType.YES_NO,
            text="Esvaziar a lixeira do The Styk?"
        )
        dialog.format_secondary_text("Todas as notas na lixeira serão apagadas permanentemente.")
        response = dialog.run()
        dialog.destroy()
        
        if response == Gtk.ResponseType.YES:
            self.store.empty_trash()

    def _on_about_clicked(self, menu_item):
        dialog = Gtk.AboutDialog()
        dialog.set_program_name("The Styk")
        dialog.set_version("1.0.0 (Linux)")
        dialog.set_comments("Notas adesivas que grudam nas suas pastas.")
        dialog.set_copyright("© 2026 Allan Pscheidt\nTodos os direitos reservados. Licenciado sob Licença MIT.")
        dialog.set_website("https://setor101.com.br/apps/styk")
        dialog.set_website_label("setor101.com.br/apps/styk")
        
        # Add license details specifying the GitHub link
        dialog.set_license("Licenciado sob Licença MIT.\n\nCódigo-fonte: https://github.com/allanpscheidt/the-styk")
        dialog.set_authors(["Allan Pscheidt"])

        # Load logo.png
        script_dir = os.path.dirname(os.path.abspath(__file__))
        logo_path = os.path.join(os.path.dirname(script_dir), "assets", "logo.png")
        if os.path.exists(logo_path):
            try:
                pixbuf = GdkPixbuf.Pixbuf.new_from_file_at_scale(logo_path, 80, 80, True)
                dialog.set_logo(pixbuf)
            except Exception as e:
                print(f"[Tray] Failed to load logo pixbuf: {e}")
        
        dialog.run()
        dialog.destroy()

    def _on_exit_clicked(self, menu_item):
        self.window_manager.flush_all()
        Gtk.main_quit()
        sys.exit(0)
