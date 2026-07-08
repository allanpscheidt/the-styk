import sys
import os
import signal

# Add current directory to path so imports work correctly when executing main.py directly
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

import gi
gi.require_version('Gtk', '3.0')
from gi.repository import Gtk, GLib

from observer import FileExplorerObserver
from window_manager import NoteWindowManager
from tray import SystemTrayController
from note_store import NoteStore

def sigint_handler(sig, frame):
    """Handles Ctrl+C to exit cleanly."""
    print("\n[The Styk] Exiting...")
    NoteWindowManager.get_shared().flush_all()
    Gtk.main_quit()
    sys.exit(0)

def main():
    # Setup exit signal handler for terminal termination (Ctrl+C)
    signal.signal(signal.SIGINT, sigint_handler)

    print("[The Styk] Initializing Linux version...")

    # 1. Initialize Observer
    observer = FileExplorerObserver()

    # 2. Initialize Window Manager
    window_manager = NoteWindowManager.get_shared()

    # Connect observer to Window Manager
    observer.register_change_callback(window_manager.set_visible_folder)

    # 3. Initialize System Tray Controller
    tray_controller = SystemTrayController(observer)

    # Start polling the active file manager window
    observer.start()

    # 4. Reconcile anchors periodically (every 10 seconds check if folders disappeared/reappeared)
    GLib.timeout_add(10000, lambda: [NoteStore.get_shared().reconcile_anchors_if_stale(), True][1])

    # 5. Start GTK Main Loop
    print("[The Styk] Application is running. Checking for active folders...")
    Gtk.main()

if __name__ == "__main__":
    main()
