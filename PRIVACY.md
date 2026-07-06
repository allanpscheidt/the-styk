# Privacy Policy — The Styk

**Last updated: July 6, 2026**

## One-line summary

The Styk does not collect, transmit, or share any data. Everything stays on your Mac.

## What the app stores (and where)

The Styk stores only what it needs to work, **exclusively on your computer**, in
`~/Library/Application Support/The Styk/`:

- the text of your notes, along with color, font, size, and on-screen position;
- the paths of the folders where you created notes (plus a macOS bookmark used to
  follow a folder if it gets moved);
- recently deleted notes (kept in the app's Trash for 5 days, then permanently removed);
- local .zip backups, only if you enable that option — automatic backups live inside
  the app's own data folder (`Backups/`, keeping the 7 most recent); manual backups
  are saved wherever you choose.

The app has **no internet access whatsoever**: there is no networking code,
telemetry, usage analytics, user account, or third-party service of any kind. The
developer receives absolutely nothing — no data, no metrics, no crash reports.

## macOS permissions

- **Automation (Finder):** used solely to ask Finder which folder is currently open
  and where its window is, so the right notes appear in the right place. The app
  does not read file names, file contents, or anything else inside your folders.
- **Launch at login (optional):** only if you enable it in Settings.

## Sharing

Nothing leaves the app without your action. When you use "Export" (AirDrop,
Messages, Mail…), the note's content is sent as plain text to the destination
**you chose** — from that point on it is outside the app's control, like any file
you send. To make the transfer work, the app writes a temporary copy of the note
to the system's temporary folder — it is deleted automatically minutes after
sharing (and any leftovers, the next time the app launches).

## Your rights (LGPD/GDPR)

The developer is based in Brazil; the Brazilian LGPD is the primary legal framework,
alongside the GDPR. Since no personal data ever reaches the developer, you exercise
the applicable rights directly in the app: **access** (open and read your notes
anytime), **portability** (Export — plain text readable by any program),
**rectification** (edit the note), and **erasure** (delete permanently from the
Trash — or remove the `~/Library/Application Support/The Styk/` folder to wipe
everything). Uninstalling the app does not delete that folder; remove it manually
to erase all data.

## Security

Your data lives in files on your Mac, protected by the system's own defenses.
The app's diagnostic messages (never note contents) go only to the local macOS
log, managed by the system. We
recommend keeping **FileVault** (macOS disk encryption) enabled — that is what
protects your notes, just as it protects the rest of your files. The .zip backups
are not encrypted by the app; store them as you would any personal document.

## Children

The Styk collects data from no one — including children.

## Changes to this policy

If this policy changes, the new version ships with the app, with the update date at
the top. Since the app has no network access, nothing can change behind your back.

## Contact

Prof. Dr. Allan Pscheidt — alpscheidt@gmail.com · [allanpscheidt.com.br](https://allanpscheidt.com.br)
