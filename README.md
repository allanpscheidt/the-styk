# The Styk

<p align="center">
  <img src="assets/logo.png" width="128" alt="The Styk Logo" /><br>
  <sub>
    <b>Versions:</b> macOS (Apple Silicon 11+ / Intel 10.15+) | Windows 10/11<br>
    <b>Languages:</b> Português (Brasil), English, Deutsch, Français, 日本語, 简体中文
  </sub>
</p>

Digital notes that live inside your folders.

The Styk is a tiny program that keeps digital notes anchored to your folders. The notes float on the screen while you are in the folder where you created them (Finder on macOS or File Explorer on Windows) -- leave the folder, they disappear; return, they reappear.

## Installation

### macOS
Download The Styk for macOS at https://setor101.com.br/apps/styk or from the GitHub [Releases](https://github.com/allanpscheidt/the-styk/releases) page and drag it into your Applications folder, then double-click the icon to launch it.

> [!NOTE]
> **macOS Security Warning (Gatekeeper)**
>
> If you see the warning "Apple cannot verify that this app is free of malware...", please note that this is due to Apple's requirement for developers to pay annual fees to digitally sign applications. Since The Styk is a free and open-source project, we believe this financial requirement is unfair to independent developers.
> 
> To open the app anyway:
> 1. Try to open the app once to trigger the warning, then close it.
> 2. Go to **System Settings** > **Privacy & Security** on your Mac.
> 3. Scroll down to the **Security** section and click the **Open Anyway** button below the message about `The Styk.app`.
> 4. Enter your password or use Touch ID to confirm.

### Windows
Download the latest `TheStyk-Windows-x64.exe` from the [Releases](https://github.com/allanpscheidt/the-styk/releases) page and run it to start anchoring notes to your File Explorer folders.

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
The primary Apple Silicon version requires macOS 11 (Big Sur) or later. However, an Intel legacy version is available that runs on macOS 10.15 (Catalina) and newer.

### How is The Styk different from standard sticky notes?
Unlike standard sticky note apps where notes clutter your desktop indefinitely, The Styk contextually anchors notes to specific folders. They only appear when you actually open and view that folder in Finder (macOS) or File Explorer (Windows).
