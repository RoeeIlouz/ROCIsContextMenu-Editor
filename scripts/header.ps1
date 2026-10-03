<#
.SYNOPSIS
    ROCI's Context Menu Editor v3 - view, toggle, add, edit and remove Windows Explorer right-click entries.

.DESCRIPTION
    Portable PowerShell + WPF tool. Covers the three kinds of context menu entries Windows has:
      - Commands          static verbs under <class>\shell (HKCU and HKLM)
      - Shell extensions  COM handlers under <class>\shellex\ContextMenuHandlers
      - Win 11 menu items packaged app entries declared in AppxManifest (Terminal, Notepad, NanaZip, ...)
    Commands are disabled with LegacyDisable; extensions and packaged items via the
    "Shell Extensions\Blocked" list. Every edit and delete writes a .reg backup to .\Backups first.

    All registry access goes through the .NET Registry API, never the PowerShell provider,
    because class keys such as "*\shell" are wildcards to the provider.

.PARAMETER LibraryOnly
    Load the functions without showing the window (for testing / dot-sourcing).
#>
param([switch]$LibraryOnly)
