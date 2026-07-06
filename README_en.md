# The Styk
Digital notes that live inside your Mac folders.

The Styk is a tiny program that keeps digital notes anchored to your Finder folders. The notes float on the screen while you are in the folder where you created them -- leave the folder, they disappear; return, they reappear.

## Installation

Download The Styk at https://setor101.com.br/apps and drag it into your Applications folder, then double-click the icon to launch it.

## Usage

The Styk puts a note icon in the right side of your menu bar. Click the icon to show the menu. From here, you can choose **"New note in this folder"** to create a note. Write in it; the note saves automatically.

### Menubar
The status bar menu lists all notes, grouped by folder. Click any note to jump straight to that folder in Finder, export it, or delete it.

### Notes Interaction
Hover over a note to reveal its action bar. From here you can:
- Change note colors.
- Adjust font size (A− / A+) and font style (Aa).
- Share the note (via AirDrop, Messages, Mail, etc.).
- Delete the note.

Drag the note by its background to move it, or drag its borders to resize. Inside the note, use `⌘ +` and `⌘ −` to quickly adjust text size.

### Preferences
From the bar menu, open Preferences to configure:
- **Language**: Switch between Portuguese (Brazil), English, Chinese, Japanese, German, or French.
- **Finder Permission**: Manage the Apple Events automation permissions required to track the active Finder window.
- **Start at Login**: Toggle whether The Styk opens automatically when you start your Mac.
- **Backups**: Configure automatic daily local backups or manually export/restore all notes.

## FAQ

### Does this require special permissions?
Yes. On first launch, macOS will ask for permission to control Finder. This is necessary so The Styk can detect which folder is active and show its respective notes. If you deny this by mistake, you can re-trigger the prompt via Preferences -> "Request Finder permission...".

### What happens when I delete a note?
Deletion is fully reversible. Deleted notes go to the app's internal Trash (accessible from the menu bar) and are automatically purged after 5 days.

### What happens if I move, rename, or delete a folder?
- **Moved/Renamed Folders**: The Styk uses macOS bookmarks, so notes automatically follow the folder even if you rename it or move it to another drive.
- **Deleted Folders**: Notes are not lost; they are moved to the "Orphan notes" section in the menu, where you can re-anchor, export, or trash them.

### Does this work with macOS 10.x?
The primary Apple Silicon version requires macOS 11 (Big Sur) or later. However, an Intel legacy version is available that runs on macOS 10.13 (High Sierra) and newer.

### How is The Styk different from standard sticky notes?
Unlike standard sticky note apps where notes clutter your desktop indefinitely, The Styk contextually anchors notes to specific folders. They only appear when you actually open and view that folder in Finder.
