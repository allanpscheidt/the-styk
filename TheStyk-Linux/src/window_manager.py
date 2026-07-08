import os
import uuid
import urllib.parse
import cairo
from typing import Dict, Optional
import gi
gi.require_version('Gtk', '3.0')
from gi.repository import Gtk, Gdk, GLib, Pango

from models import Note, NoteFrame, NoteStyle, NoteColor, NoteFontID
from note_store import NoteStore
import theme

class Debouncer:
    def __init__(self, delay_ms: int, callback):
        self.delay_ms = delay_ms
        self.callback = callback
        self.source_id = None

    def trigger(self, *args):
        if self.source_id:
            GLib.source_remove(self.source_id)
        self.source_id = GLib.timeout_add(self.delay_ms, self._timeout_callback, *args)

    def _timeout_callback(self, *args):
        self.source_id = None
        self.callback(*args)
        return False  # Run once

    def cancel(self):
        if self.source_id:
            GLib.source_remove(self.source_id)
            self.source_id = None

class NoteWindowController(Gtk.Window):
    def __init__(self, note: Note):
        super().__init__(type=Gtk.WindowType.TOPLEVEL)
        self.note = note
        self.note_id = note.id
        
        self._is_loaded = False
        self._is_positioning_from_explorer = False
        self._anchor_dx = 0
        self._anchor_dy = 0
        
        # Window setup
        self.set_title("The Styk Note")
        self.set_role("TheStyk")
        self.set_keep_above(True)
        self.set_skip_taskbar_hint(True)
        self.set_decorated(False)
        self.set_resizable(True)
        
        # Transparent background setup
        screen = self.get_screen()
        visual = screen.get_rgba_visual()
        if visual:
            self.set_visual(visual)
        self.set_app_paintable(True)

        # Set default size and position
        self.set_default_size(int(note.frame.w), int(note.frame.h))
        self.move(int(note.frame.x), int(note.frame.y))

        # CSS Styling Provider
        self.css_provider = Gtk.CssProvider()
        self.get_style_context().add_class("note-window")
        
        # Timers
        self.save_text_debouncer = Debouncer(1500, self._save_text)
        self.save_frame_debouncer = Debouncer(500, self._save_frame)

        # Layout
        self.main_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        self.add(self.main_box)

        # 1. Hover Toolbar
        self.toolbar_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=4)
        self.toolbar_box.get_style_context().add_class("note-toolbar")
        self.toolbar_box.set_size_request(-1, 30)
        self.main_box.pack_start(self.toolbar_box, False, False, 0)
        
        self._build_toolbar()

        # 2. Text Editor Area
        self.scroll_win = Gtk.ScrolledWindow()
        self.scroll_win.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)
        self.scroll_win.set_shadow_type(Gtk.ShadowType.NONE)
        self.main_box.pack_start(self.scroll_win, True, True, 0)

        self.text_view = Gtk.TextView()
        self.text_view.set_wrap_mode(Gtk.WrapMode.WORD)
        self.text_view.set_left_margin(12)
        self.text_view.set_right_margin(12)
        self.text_view.set_top_margin(8)
        self.text_view.set_bottom_margin(12)
        self.text_view.get_style_context().add_class("note-textview")
        self.scroll_win.add(self.text_view)

        # Load note content
        self.text_buffer = self.text_view.get_buffer()
        self.text_buffer.set_text(note.text)

        # Apply styles
        self.apply_style()

        # Events connection
        self.connect("button-press-event", self._on_button_press)
        self.connect("configure-event", self._on_configure)
        self.connect("key-press-event", self._on_key_press)
        self.connect("draw", self._on_draw)
        self.connect("destroy", self._on_destroy)
        
        # Connect text changed
        self.text_buffer.connect("changed", self._on_text_changed)

        # Hover visibility on toolbar
        self.toolbar_box.set_opacity(0.0)
        self.connect("enter-notify-event", self._on_hover_enter)
        self.connect("leave-notify-event", self._on_hover_leave)

        self.show_all()
        self._is_loaded = True

    def _build_toolbar(self):
        # Drag handle / spacing
        spacing = Gtk.Label(label="  ")
        self.toolbar_box.pack_start(spacing, False, False, 0)

        # Color dots
        for color in NoteColor:
            dot = Gtk.Button()
            dot.get_style_context().add_class("note-button")
            
            # Colored circle image/drawing
            dot_color = theme.get_color_hex(color)
            dot_label = Gtk.Label()
            dot_label.set_markup(f'<span foreground="{dot_color}">●</span>')
            dot.add(dot_label)
            
            dot.connect("clicked", self._on_color_clicked, color)
            self.toolbar_box.pack_start(dot, False, False, 0)

        # Separator
        sep = Gtk.Separator(orientation=Gtk.Orientation.VERTICAL)
        self.toolbar_box.pack_start(sep, False, False, 4)

        # Font minus A-
        btn_minus = Gtk.Button(label="A−")
        btn_minus.get_style_context().add_class("note-button")
        btn_minus.connect("clicked", lambda w: self.adjust_font_size(-2))
        self.toolbar_box.pack_start(btn_minus, False, False, 0)

        # Font plus A+
        btn_plus = Gtk.Button(label="A+")
        btn_plus.get_style_context().add_class("note-button")
        btn_plus.connect("clicked", lambda w: self.adjust_font_size(2))
        self.toolbar_box.pack_start(btn_plus, False, False, 0)

        # Font family Aa
        btn_font = Gtk.Button(label="Aa")
        btn_font.get_style_context().add_class("note-button")
        btn_font.connect("clicked", self._on_font_cycle_clicked)
        self.toolbar_box.pack_start(btn_font, False, False, 0)

        # Spacer to push buttons to the right
        spacer = Gtk.Box()
        self.toolbar_box.pack_start(spacer, True, True, 0)

        # Share button
        btn_share = Gtk.Button()
        btn_share.get_style_context().add_class("note-button")
        share_label = Gtk.Label(label="🔗")
        btn_share.add(share_label)
        btn_share.set_tooltip_text("Exportar / Copiar nota")
        btn_share.connect("clicked", self._on_share_clicked)
        self.toolbar_box.pack_start(btn_share, False, False, 0)

        # Delete button
        btn_delete = Gtk.Button()
        btn_delete.get_style_context().add_class("note-button")
        delete_label = Gtk.Label()
        delete_label.set_markup('<span foreground="#FF453A">🗑</span>')
        btn_delete.add(delete_label)
        btn_delete.set_tooltip_text("Apagar nota")
        btn_delete.connect("clicked", self._on_delete_clicked)
        self.toolbar_box.pack_start(btn_delete, False, False, 0)

        # Spacing right
        spacing_r = Gtk.Label(label=" ")
        self.toolbar_box.pack_start(spacing_r, False, False, 0)

    def apply_style(self):
        style_ctx = self.get_style_context()
        # Remove previous custom provider if any
        style_ctx.remove_provider(self.css_provider)
        
        # Load new CSS
        css_data = theme.get_css(self.note.style.color, self.note.style.fontID, self.note.style.fontSize)
        self.css_provider.load_from_data(css_data.encode('utf-8'))
        
        # Apply provider
        style_ctx.add_provider(self.css_provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        
        # Also apply provider recursively to children (TextView, ScrolledWindow, Toolbar, etc.)
        self.scroll_win.get_style_context().add_provider(self.css_provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        self.text_view.get_style_context().add_provider(self.css_provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        self.toolbar_box.get_style_context().add_provider(self.css_provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        self.queue_draw()

    def update_position_from_explorer(self, explorer_bounds):
        self._is_positioning_from_explorer = True
        
        # If anchors are not set yet, set them relative to current bounds
        if self._anchor_dx == 0 and self._anchor_dy == 0:
            x, y = self.get_position()
            self._anchor_dx = x - explorer_bounds.left
            self._anchor_dy = y - explorer_bounds.top

        # Reposition note keeping the same relative offset
        target_x = int(explorer_bounds.left + self._anchor_dx)
        target_y = int(explorer_bounds.top + self._anchor_dy)
        
        self.move(target_x, target_y)
        self._is_positioning_from_explorer = False

    def recalculate_anchors(self, explorer_bounds):
        x, y = self.get_position()
        self._anchor_dx = x - explorer_bounds.left
        self._anchor_dy = y - explorer_bounds.top

    def flush_pending_save(self):
        # If the note was deleted, it won't be in the index anymore.
        # Check this to prevent resurrecting deleted notes on destroy.
        in_index = any(e.id == self.note_id for e in NoteStore.get_shared().index)
        if not in_index:
            return

        self.save_text_debouncer.cancel()
        self._save_text()
        
        self.save_frame_debouncer.cancel()
        self._save_frame()

    def adjust_font_size(self, delta: int):
        new_size = max(8.0, min(self.note.style.fontSize + delta, 72.0))
        if new_size != self.note.style.fontSize:
            self.note.style.fontSize = new_size
            self.apply_style()
            self.save_frame_debouncer.trigger()

    def _save_text(self):
        start_iter, end_iter = self.text_buffer.get_bounds()
        current_text = self.text_buffer.get_text(start_iter, end_iter, True)
        if current_text != self.note.text:
            self.note.text = current_text
            NoteStore.get_shared().save(self.note)

    def _save_frame(self):
        x, y = self.get_position()
        w, h = self.get_size()
        
        self.note.frame = NoteFrame(x=float(x), y=float(y), w=float(w), h=float(h))
        NoteStore.get_shared().save(self.note)

    # MARK: - Event Handlers
    def _on_hover_enter(self, widget, event):
        self.toolbar_box.set_opacity(1.0)
        return False

    def _on_hover_leave(self, widget, event):
        # Check if cursor is actually outside the window bounds
        x, y = self.get_pointer()
        w, h = self.get_size()
        if x < 0 or y < 0 or x >= w or y >= h:
            self.toolbar_box.set_opacity(0.0)
        return False

    def _on_draw(self, widget, cr):
        # Clear background (fully transparent)
        cr.set_source_rgba(0, 0, 0, 0)
        cr.set_operator(cairo.OPERATOR_SOURCE)
        cr.paint()

        # Draw rounded rectangle note body
        w, h = self.get_size()
        r = 12.0 # Border radius

        cr.set_operator(cairo.OPERATOR_OVER)
        
        # Create rounded rectangle path
        cr.new_sub_path()
        cr.arc(w - r, r, r, -1.5707963, 0) # Top-Right
        cr.arc(w - r, h - r, r, 0, 1.5707963) # Bottom-Right
        cr.arc(r, h - r, r, 1.5707963, 3.1415926) # Bottom-Left
        cr.arc(r, r, r, 3.1415926, 4.7123889) # Top-Left
        cr.close_path()

        # Fill background with note color (90% opacity)
        rgba = theme.get_rgb_color(self.note.style.color)
        cr.set_source_rgba(rgba[0], rgba[1], rgba[2], 0.90)
        cr.fill_preserve()

        # Stroke subtle dark border (1px)
        cr.set_source_rgba(0, 0, 0, 0.1)
        cr.set_line_width(1.0)
        cr.stroke()

        return False

    def _on_button_press(self, widget, event):
        # Drag window by clicking background/toolbar (but not editor)
        if event.button == 1:
            # Check if clicked on TextView widget
            text_allocation = self.scroll_win.get_allocation()
            x, y = event.x, event.y
            if (x >= text_allocation.x and x < text_allocation.x + text_allocation.width and
                y >= text_allocation.y and y < text_allocation.y + text_allocation.height):
                return False  # Let TextView handle clicks
                
            self.begin_move_drag(event.button, int(event.x_root), int(event.y_root), event.time)
            return True
        return False

    def _on_configure(self, widget, event):
        if not self._is_loaded:
            return False
            
        if not self._is_positioning_from_explorer:
            # Moved or resized manually: recalculate relative anchor offsets
            manager = NoteWindowManager.get_shared()
            if manager.current_explorer_bounds:
                self.recalculate_anchors(manager.current_explorer_bounds)
            
            # Trigger save frame timer
            self.save_frame_debouncer.trigger()
            
        return False

    def _on_key_press(self, widget, event):
        # Keyboard shortcuts: Ctrl + and Ctrl -
        state = event.state & Gtk.accelerator_get_default_mod_mask()
        if state == Gdk.ModifierType.CONTROL_MASK:
            keyval = event.keyval
            if keyval == Gdk.KEY_plus or keyval == Gdk.KEY_equal:
                self.adjust_font_size(2)
                return True
            elif keyval == Gdk.KEY_minus:
                self.adjust_font_size(-2)
                return True
        return False

    def _on_text_changed(self, buffer):
        if not self._is_loaded:
            return
        self.save_text_debouncer.trigger()

    def _on_color_clicked(self, button, color: NoteColor):
        if self.note.style.color != color:
            self.note.style.color = color
            self.apply_style()
            self.save_frame_debouncer.trigger()

    def _on_font_cycle_clicked(self, button):
        fonts = list(NoteFontID)
        curr_idx = fonts.index(self.note.style.fontID)
        next_idx = (curr_idx + 1) % len(fonts)
        self.note.style.fontID = fonts[next_idx]
        self.apply_style()
        self.save_frame_debouncer.trigger()

    def _on_share_clicked(self, button):
        # Create a simple popover or menu with option to copy to clipboard or export to file
        menu = Gtk.Menu()
        
        item_copy = Gtk.MenuItem(label="Copiar Texto")
        item_copy.connect("activate", self._share_copy_to_clipboard)
        menu.append(item_copy)
        
        item_export = Gtk.MenuItem(label="Exportar para arquivo .txt...")
        item_export.connect("activate", self._share_export_to_file)
        menu.append(item_export)
        
        menu.show_all()
        menu.popup_at_widget(button, Gdk.Gravity.SOUTH, Gdk.Gravity.NORTH, None)

    def _share_copy_to_clipboard(self, menu_item):
        clipboard = Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD)
        clipboard.set_text(self.note.text, -1)

    def _share_export_to_file(self, menu_item):
        # Open Gtk.FileChooserDialog to save file
        dialog = Gtk.FileChooserDialog(
            title="Exportar Nota",
            parent=self,
            action=Gtk.FileChooserAction.SAVE
        )
        dialog.add_buttons(
            Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL,
            Gtk.STOCK_SAVE, Gtk.ResponseType.OK
        )
        dialog.set_do_overwrite_confirmation(True)
        
        # Suggest filename: The Styk - <snippet>.txt
        snippet = NoteStore.make_snippet(self.note.text)
        # Sanitization
        sanitized = re.sub(r'[/\\:*?"<>|]', "", snippet)
        sanitized = sanitized[:40] if len(sanitized) > 40 else sanitized
        dialog.set_current_name(f"The Styk – {sanitized}.txt")
        
        response = dialog.run()
        if response == Gtk.ResponseType.OK:
            filepath = dialog.get_filename()
            try:
                with open(filepath, "w", encoding="utf-8") as f:
                    f.write(self.note.text)
            except Exception as e:
                # Show error dialog
                err_dialog = Gtk.MessageDialog(
                    parent=self,
                    flags=0,
                    message_type=Gtk.MessageType.ERROR,
                    buttons=Gtk.ButtonsType.OK,
                    text=f"Erro ao exportar arquivo:\n{e}"
                )
                err_dialog.run()
                err_dialog.destroy()
        dialog.destroy()

    def _on_delete_clicked(self, button):
        # Open confirmation dialog
        dialog = Gtk.MessageDialog(
            parent=self,
            flags=Gtk.DialogFlags.MODAL,
            message_type=Gtk.MessageType.QUESTION,
            buttons=Gtk.ButtonsType.YES_NO,
            text="Apagar esta nota?"
        )
        dialog.format_secondary_text("A nota será enviada para a lixeira interna do The Styk.")
        response = dialog.run()
        dialog.destroy()
        
        if response == Gtk.ResponseType.YES:
            NoteStore.get_shared().move_to_trash(self.note_id)

    def _on_destroy(self, widget):
        self.flush_pending_save()


class NoteWindowManager:
    _instance: Optional["NoteWindowManager"] = None

    @classmethod
    def get_shared(cls) -> "NoteWindowManager":
        if cls._instance is None:
            cls._instance = cls()
        return cls._instance

    def __init__(self):
        self._open_windows: Dict[uuid.UUID, NoteWindowController] = {}
        self._current_folder: Optional[str] = None
        self._current_bounds: Optional[object] = None
        self._is_reconciling = False
        
        # Connect to NoteStore index changes to dynamically close deleted notes
        NoteStore.get_shared().register_callback(self._on_index_changed)

    def _on_index_changed(self):
        if self._is_reconciling:
            return
        if self._current_folder:
            self.set_visible_folder(self._current_folder, self._current_bounds)

    @property
    def current_explorer_bounds(self):
        return self._current_bounds

    @property
    def current_folder(self) -> Optional[str]:
        return self._current_folder

    def set_visible_folder(self, folder: Optional[str], bounds):
        self._is_reconciling = True
        try:
            self._current_folder = folder
            self._current_bounds = bounds

            if not folder:
                # Close all open windows
                open_ids = list(self._open_windows.keys())
                for nid in open_ids:
                    win = self._open_windows.get(nid)
                    if win:
                        win.flush_pending_save()
                        win.destroy()
                self._open_windows.clear()
                return

            # Reconcile open windows
            # 1. Close windows from other folders
            to_close = []
            for nid, win in self._open_windows.items():
                in_index = any(e.id == nid for e in NoteStore.get_shared().index)
                if not in_index or win.note.folder.lower() != folder.lower():
                    to_close.append(nid)

            for nid in to_close:
                win = self._open_windows.get(nid)
                if win:
                    win.flush_pending_save()
                    win.destroy()

            # 2. Open windows for the current folder
            entries = NoteStore.get_shared().entries(folder)
            for entry in entries:
                if entry.id not in self._open_windows:
                    note = NoteStore.get_shared().load_note(entry.id)
                    if note:
                        self._create_and_show_note_window(note)

            # 3. Update positions to stick with the file manager window bounds (only if bounds exist)
            if bounds:
                for win in self._open_windows.values():
                    win.update_position_from_explorer(bounds)
        finally:
            self._is_reconciling = False

    def suggested_frame(self) -> NoteFrame:
        # Default suggested size: 260x240 centered on display or explorer window
        w, h = 260.0, 240.0
        
        # Center of screen fallback
        screen = Gdk.Screen.get_default()
        width = screen.get_width()
        height = screen.get_height()
        x = (width - w) / 2.0
        y = (height - h) / 2.0

        # Center relative to explorer window if available
        if self._current_bounds:
            eb = self._current_bounds
            x = eb.left + (eb.width - w) / 2.0
            y = eb.top + (eb.height - h) / 2.0

        # Cascade effect
        offset = len(self._open_windows) * 24
        x += offset
        y += offset

        return NoteFrame(x=float(x), y=float(y), w=w, h=h)

    def show_note_window(self, note: Note):
        if note.id in self._open_windows:
            self._open_windows[note.id].present()
            return

        self._create_and_show_note_window(note)
        if self._current_bounds:
            self._open_windows[note.id].update_position_from_explorer(self._current_bounds)

    def close_note_window(self, note_id: uuid.UUID):
        win = self._open_windows.get(note_id)
        if win:
            win.flush_pending_save()
            win.destroy()

    def flush_all(self):
        for win in self._open_windows.values():
            win.flush_pending_save()

    def _create_and_show_note_window(self, note: Note):
        win = NoteWindowController(note)
        
        def on_window_destroyed(w):
            self._open_windows.pop(note.id, None)
                
        win.connect("destroy", on_window_destroyed)
        self._open_windows[note.id] = win
        win.show_all()
