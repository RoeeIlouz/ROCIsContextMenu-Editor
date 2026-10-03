---
ontology: true
type: tool
domain: rocis-utils
summary: Portable PowerShell + WPF editor for Windows Explorer right-click menu entries (commands, shell extensions, Windows 11 packaged items)
tags: [windows, context-menu, registry, powershell, wpf]
status: active
---

<img src="assets/app-icon-1024.png" width="96" alt="">

# ROCI's Context Menu Editor

A portable, dependency-free editor for the Windows right-click menu, by [ROCIs Apps](https://rocisapps.com). It's a single PowerShell script with a WPF UI.

## Run it

Open PowerShell and run:

```powershell
irm https://rocisapps.com/cme | iex
```

That always downloads the latest release. Nothing is installed: backups go to `%LOCALAPPDATA%\ContextMenuEditor\Backups`, and "run as administrator" downloads the script again the same way.

To run a downloaded copy instead, double-click `Launch.bat`. It starts the editor without a console window and uses PowerShell 7 if it's installed, otherwise Windows PowerShell 5.1. From a terminal:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\ContextMenuEditor.ps1
```

Run from a file, the editor keeps its backups in a `Backups` folder next to it.

## What it shows

Windows builds the right-click menu from three different sources. The editor lists all three together:

| Kind | Where it lives | How "off" works |
|------|----------------|-----------------|
| Command | `HKCU`/`HKLM\Software\Classes\<class>\shell\<verb>` | `LegacyDisable` value on the verb (nothing is deleted) |
| Shell extension | `<class>\shellex\ContextMenuHandlers` (7-Zip, PowerToys, antivirus, ...) | CLSID added to `Shell Extensions\Blocked` |
| Windows 11 menu | Packaged apps declaring `windows.fileExplorerContextMenus` (Terminal, Notepad, NanaZip, Paint, ...) | CLSID added to `Shell Extensions\Blocked` |

The sidebar filters entries by where they appear: files, folders, folder background, desktop, drives, or one file type. That file-type view combines `SystemFileAssociations\.ext`, the extension's ProgID, its perceived type, and the default app's ProgID. Windows' own entries (Open, Print, Properties, ...) are hidden until you turn on **Windows built-ins**.

## What you can do

- Turn any entry on or off with its switch. Extension changes apply after an Explorer restart; the status bar offers one.
- Add or edit commands: name, command line (`%1` for the clicked item, `%V` for the folder), icon, location, Shift-only, UAC shield, and position. You can also move a command to another location or scope.
- Group commands into **submenus**. In New command, switch Type to Submenu, then add commands and choose it under "Inside submenu". You can also select a submenu first and click New command. Submenus use the static `SubCommands=""` + nested `shell` key format, so moving a command in or out of one is just an edit.
- Delete commands. Shell extensions and packaged items can only be turned off, unless they are broken.
- **Broken entries**: lists entries whose program or DLL no longer exists, or whose handler CLSID isn't registered anywhere. These are usually leftovers from uninstalled apps, and "Remove all" cleans them up. To avoid false alarms, only absolute paths are checked: bare names like `wt.exe`, UNC paths and Store app folders are never flagged.
- **Backups**: lists every `.reg` backup with what it was and when. Restore puts a single entry back exactly as it was, deleting the current key first and backing that up too. Full backups are merged instead, so nothing is deleted.
- **Undo**: the status bar offers Undo after any toggle, edit, delete, cleanup or restore.
- **New menu**: lists the file types under New (`ShellNew` keys). Turning one off renames its key to `_ShellNew`, which Windows ignores, so nothing is lost. "Add a file type" creates `.ext\ShellNew` with `NullFile`. Windows names New entries after the type's registered ProgID, so types without one are refused. If a built-in entry such as New > Text Document is missing, its type's ProgID is usually not registered.
- **Send to**: lists the shortcuts in your Send To folder. Turning one off sets the file's Hidden attribute, and deleting moves it to `Backups\SendTo` so it can be restored. Add program and Add folder create new shortcuts.
- **Add to Send to**: the detail panel's "Add to Send to" button turns an existing right-click entry into Send To items that run the same thing. A submenu (Pushbullet's or Blip's devices, for example) gets one item per entry, and you pick which ones in a dialog. With "Put them in a submenu" on (the default), they go into a subfolder of Send To, which Windows shows as a submenu (Send to > Blip > Laptop). The folder gets the app's icon via `desktop.ini`. Identical shortcuts already elsewhere in Send To are moved in rather than duplicated. In the Send to view, submenu folders list their items beneath them; turning a folder off hides the whole submenu, and deleting or restoring works on single items and whole folders.
  - Commands whose file argument comes last (`app.exe -x "%1"`) become a plain shortcut to `app.exe -x`. Send To appends the selected files, which is what `%1` was. Commands that need the file elsewhere are refused with an explanation.
  - Windows 11 menu items such as Blip have no command line; they are COM handlers that Explorer calls directly. Their Send To shortcut points at a small bridge, `%LOCALAPPDATA%\ContextMenuEditor\CmeSendTo.exe`, which calls the same handler on the files the way Explorer does. Submenu items are matched by title (position is only a fallback), so pairing a new device doesn't change where an existing shortcut sends. The bridge is compiled from source embedded in the script, using Windows PowerShell's `Add-Type`, the first time it's needed. It lives outside this folder so shortcuts keep working if you move the editor.
- **Bulk changes**: Ctrl+click or Shift+click several rows to turn them all on or off, or delete them, in one undoable step.
- **Test**: the Test button in the command editor runs the command on a file or folder you pick, with `%1`/`%V` filled in, the way Explorer would.
- **Export / import setup** (Backups page): exports your per-user commands, submenus, turned-off extensions and the classic-menu switch to a `.reg` file for another PC. Machine-wide entries belong to installed programs and are left out. Import merges a `.reg` file in after saving a full backup, and warns if the file touches keys outside the context menu.
- Open any entry in Registry Editor at its key.
- **About** (sidebar): the version, the launch command with a Copy button, where the editor runs from and keeps its backups, and links to this repo and rocisapps.com.
- **Tweaks**: check tweaks, or pick a preset (**Minimal**, **Standard**), then **Run tweaks**. **Undo selected** writes the original values back, and the status bar Undo reverts the last run. Toggle tweaks, such as the Windows 11 classic full menu, apply as soon as you switch them. Rows show which tweaks are already applied. The tweaks:
  - **Clean up the menu**: remove Give access to, Include in library, Cast to device, Troubleshoot compatibility, Restore previous versions, Share and Pin to Start, plus Open in Terminal, Edit in Notepad, Edit with Paint and Edit with Photos (Windows 11 menu). Each one adds its handler's CLSID to the per-user `Shell Extensions\Blocked` list. Tweaks that can't apply on a PC, for example because the app isn't installed, show as unavailable with the reason.
  - **Add useful entries** (per user, `HKCU`): Open with VS Code, PowerShell 7 here, Take ownership, Copy full path, SHA-256 hash, God Mode. Every key these write is tagged with `CMEPreset`, so undoing never touches keys it didn't create.

## Safety

- Every edit and delete first exports the key to `Backups\<timestamp>_<name>.reg`. Double-click the file to restore it. The toolbar download button exports all context menu keys to a single `.reg`.
- `HKCU` entries need no admin rights. Changing an `HKLM` (all users) entry asks to restart the editor as administrator.
- All registry access uses the .NET registry API. The PowerShell registry provider is avoided because it treats `*` in `*\shell` as a wildcard.

## Source layout and building

The source is split into small files, and `Compile.ps1` stitches them into the single `ContextMenuEditor.ps1` you run. Edit the source files, never the compiled script, then run `.\Compile.ps1` (`-Run` to start it).

| Path | Contents |
|------|----------|
| `scripts\header.ps1` | Help block and `param()`; always first in the output |
| `scripts\start.ps1` | Assemblies, native types, launch mode, state and constants |
| `functions\core\*.ps1` | Scanning, registry, New menu, Send To, bridge, actions, presets and tweak engine. These work without a window, so `-LibraryOnly` stops after them |
| `functions\ui\*.ps1` | Dialogs, views, undo, the command editor and the Tweaks page |
| `scripts\main.ps1` | Builds the window, wires events, starts |
| `xaml\*.xaml` | The main window, the command editor, message and About dialogs, and shared styles |
| `native\*.cs` | Win32 interop (`Native.cs`) and the Send To bridge (`CmeSendTo.cs`), compiled at runtime |
| `config\tweaks.json` | Tweak definitions: `Content`, `Description`, `category`, `registry` with `Value`/`OriginalValue`/`<RemoveEntry>`, `InvokeScript`/`UndoScript`, `Type: "Toggle"`, `DetectScript`, `UnavailableScript` and `RestartExplorer` |
| `config\preset.json` | Preset name to list of tweak ids |
| `assets\` | App icon and wordmark, embedded by the compiler. `tools\Build-Assets.ps1` rebuilds them from the ROCIs Apps brand files |

### Publishing a release

```powershell
.\Compile.ps1 -Version 26.10.03.3 -LaunchUrl https://github.com/RoeeIlouz/ROCIsContextMenu-Editor/releases/latest/download/ContextMenuEditor.ps1
```

`-Version` is what About shows (it defaults to the build date). `-LaunchUrl` is where "run as administrator" downloads the script from. Attach the compiled `ContextMenuEditor.ps1` to a new GitHub release; `rocisapps.com/cme` redirects to the latest release's copy, so it's live right away.

Files in each folder are included in name order. The compiler also:
- checks that the JSON and XAML are valid and that the output parses;
- refuses non-ASCII characters. The output is written without a BOM because `irm | iex` would pass a BOM through as code, and Windows PowerShell 5.1 reads BOM-less files as ANSI.

## Testing

`-LibraryOnly` loads every function without opening the window, so the scanner and the write operations can be scripted:

```powershell
. .\ContextMenuEditor.ps1 -LibraryOnly
Invoke-Scan
$App.Items | Where-Object { -not $_.IsBuiltIn } | Format-Table Kind, Hive, Name, LocLabel, Enabled
```

## License

MIT. See [LICENSE](LICENSE).
