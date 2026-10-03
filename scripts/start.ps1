
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

# WPF windows need a single-threaded apartment. Windows PowerShell and pwsh consoles are STA by default,
# but a host started with -MTA (or some embedded hosts) is not.
if (-not $LibraryOnly -and [Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    Write-Host 'Context Menu Editor needs an STA PowerShell. Start PowerShell normally (without -MTA) and run it again.' -ForegroundColor Yellow
    return
}

# Compiling the helper types costs 0.1 to 0.3 s per start; loading a cached copy costs about 15 ms.
# The cache is keyed by source and PowerShell edition. An elevated run never loads it, because an admin
# process must not load code from a folder the standard user can write to.
if (-not ('CME.Native' -as [type])) {
    $isElevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isElevated) {
        try {
            $hash = [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes("$NativeSource|$($PSVersionTable.PSEdition)"))).Replace('-', '').Substring(0, 16)
            $cacheDir = Join-Path $env:LOCALAPPDATA 'ContextMenuEditor\cache'
            $nativeDll = Join-Path $cacheDir "CME.Native.$hash.dll"
            if (-not (Test-Path -LiteralPath $nativeDll)) {
                New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
                Get-ChildItem -LiteralPath $cacheDir -Filter 'CME.Native.*.dll' -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
                Add-Type -TypeDefinition $NativeSource -OutputAssembly $nativeDll -OutputType Library
            }
            Add-Type -LiteralPath $nativeDll
        } catch { if ($nativeDll) { Remove-Item -LiteralPath $nativeDll -Force -ErrorAction SilentlyContinue } }
    }
    if (-not ('CME.Native' -as [type])) { Add-Type -TypeDefinition $NativeSource }
}

if (-not $LibraryOnly) {
    # Hide the console only when it was created for this process (double-click / Launch.bat),
    # never when the user started us from their own terminal.
    try {
        $consoleHwnd = [CME.Native]::GetConsoleWindow()
        if ($consoleHwnd -ne [IntPtr]::Zero -and [CME.Native]::OwnsConsole()) { [void][CME.Native]::ShowWindow($consoleHwnd, 0) }
    } catch {}
}

# ==============================================================================
# STATE
# ==============================================================================
# Run from a file, backups live next to it (portable). Run as "irm <url> | iex" there is no file,
# so they go to %LOCALAPPDATA%\ContextMenuEditor, next to the Send To bridge.
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Join-Path $env:LOCALAPPDATA 'ContextMenuEditor' }

$App = @{
    IsAdmin     = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    IsWin11     = [Environment]::OSVersion.Version.Build -ge 22000
    ScriptPath  = $PSCommandPath
    BackupDir   = Join-Path $ScriptDir 'Backups'
    IconCache   = [System.Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)
    ClsidCache  = @{}
    PathCache   = @{}
    MissingCache = @{}
    SendToCache = @{}
    Packaged    = $null
    Items       = [System.Collections.Generic.List[object]]::new()
    View        = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
    Nav         = 'all'
    Kind        = 'all'
    ShowBuiltIn = $false
    Search      = ''
    Ext         = '.txt'
    LastBackup  = $null
    Undo        = $null
}

$AppRepoUrl       = 'https://github.com/RoeeIlouz/ROCIsContextMenu-Editor'
$AppSiteUrl       = 'https://rocisapps.com'
$AppLaunchCommand = 'irm https://rocisapps.com/cme | iex'

$BlockedPath ='Software\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked'
$ClassicKey  = 'Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}'

# Class keys that hold context menu entries, where they show up, and how to label them.
$BaseKeys = [ordered]@{
    '*'                    = @{ Label = 'Files';           Locs = @('files') }
    'AllFilesystemObjects' = @{ Label = 'Files & folders'; Locs = @('files', 'folders') }
    'Directory'            = @{ Label = 'Folders';         Locs = @('folders') }
    'Folder'               = @{ Label = 'Folders';         Locs = @('folders') }
    'Directory\Background' = @{ Label = 'Background';      Locs = @('background', 'desktop') }
    'DesktopBackground'    = @{ Label = 'Desktop';         Locs = @('desktop') }
    'Drive'                = @{ Label = 'Drives';          Locs = @('drives') }
}

$SystemVerbs = [System.Collections.Generic.HashSet[string]]::new([string[]]@(
    'open', 'opennewwindow', 'opennewprocess', 'opennewtab', 'opencontaining', 'explore', 'find', 'print', 'printto',
    'edit', 'runas', 'runasuser', 'properties', 'cut', 'copy', 'paste', 'delete', 'rename', 'play', 'enqueue',
    'pintohome', 'preview', 'mount', 'format', 'eject', 'manage', 'cmd', 'cmdprompt', 'powershell', 'wsl',
    'setdesktopwallpaper', 'setbackground', 'share', 'organize', 'UpdateEncryptionSettings', 'UpdateEncryptionSettingsWork',
    'change-passphrase', 'change-pin', 'encrypt-bde', 'encrypt-bde-elev', 'manage-bde', 'resume-bde', 'resume-bde-elev',
    'unlock-bde', 'burn', 'install', 'connectNetworkDrive', 'disconnectNetworkDrive', 'CastToDevMenu'
), [StringComparer]::OrdinalIgnoreCase)

$KnownVerbNames = @{
    open = 'Open'; opennewwindow = 'Open in new window'; opennewprocess = 'Open in new process'; opennewtab = 'Open in new tab'
    explore = 'Explore'; find = 'Search'; print = 'Print'; printto = 'Print to'; edit = 'Edit'; runas = 'Run as administrator'
    runasuser = 'Run as different user'; properties = 'Properties'; play = 'Play'; enqueue = 'Add to queue'
    pintohome = 'Pin to Quick access'; mount = 'Mount'; format = 'Format'; eject = 'Eject'; preview = 'Preview'
    cmd = 'Open command window here'; powershell = 'Open PowerShell window here'; wsl = 'Open Linux shell here'
    setdesktopwallpaper = 'Set as desktop background'
}

# Material Design icon paths (24x24)
$G = @{
    List      = 'M3,4H7V8H3V4M9,5V7H21V5H9M3,10H7V14H3V10M9,11V13H21V11H9M3,16H7V20H3V16M9,17V19H21V17H9Z'
    File      = 'M14,2H6A2,2 0 0,0 4,4V20A2,2 0 0,0 6,22H18A2,2 0 0,0 20,20V8L14,2M13,3.5L18.5,9H13V3.5M6,20V4H12V10H18V20H6Z'
    Folder    = 'M10,4H4C2.89,4 2,4.89 2,6V18A2,2 0 0,0 4,20H20A2,2 0 0,0 22,18V8C22,6.89 21.1,6 20,6H12L10,4Z'
    FolderBg  = 'M19,20H4C2.89,20 2,19.1 2,18V6C2,4.89 2.89,4 4,4H10L12,6H19A2,2 0 0,1 21,8H21L4,8V18L6.14,10H23.21L20.93,18.5C20.7,19.37 19.92,20 19,20Z'
    Desktop   = 'M21,16H3V4H21M21,2H3C1.89,2 1,2.89 1,4V16A2,2 0 0,0 3,18H10V20H8V22H16V20H14V18H21A2,2 0 0,0 23,16V4C23,2.89 22.1,2 21,2Z'
    Drive     = 'M6,2H18A2,2 0 0,1 20,4V20A2,2 0 0,1 18,22H6A2,2 0 0,1 4,20V4A2,2 0 0,1 6,2M12,4A6,6 0 0,0 6,10C6,13.31 8.69,16 12.1,16L11.22,13.77C10.95,13.29 11.11,12.68 11.59,12.4L12.45,11.9C12.93,11.63 13.54,11.79 13.82,12.27L15.74,14.69C17.12,13.59 18,11.9 18,10A6,6 0 0,0 12,4M12,9A1,1 0 0,1 13,10A1,1 0 0,1 12,11A1,1 0 0,1 11,10A1,1 0 0,1 12,9M7,18A1,1 0 0,0 6,19A1,1 0 0,0 7,20A1,1 0 0,0 8,19A1,1 0 0,0 7,18M12.09,13.27L14.58,19.58L17.17,18.08L12.95,12.77L12.09,13.27Z'
    FileType  = 'M13,9V3.5L18.5,9M6,2C4.89,2 4,2.89 4,4V20A2,2 0 0,0 6,22H18A2,2 0 0,0 20,20V8L14,2H6Z'
    Tweak     = 'M12,15.5A3.5,3.5 0 0,1 8.5,12A3.5,3.5 0 0,1 12,8.5A3.5,3.5 0 0,1 15.5,12A3.5,3.5 0 0,1 12,15.5M19.43,12.97C19.47,12.65 19.5,12.33 19.5,12C19.5,11.67 19.47,11.34 19.43,11L21.54,9.37C21.73,9.22 21.78,8.95 21.66,8.73L19.66,5.27C19.54,5.05 19.27,4.96 19.05,5.05L16.56,6.05C16.04,5.66 15.5,5.32 14.87,5.07L14.5,2.42C14.46,2.18 14.25,2 14,2H10C9.75,2 9.54,2.18 9.5,2.42L9.13,5.07C8.5,5.32 7.96,5.66 7.44,6.05L4.95,5.05C4.73,4.96 4.46,5.05 4.34,5.27L2.34,8.73C2.21,8.95 2.27,9.22 2.46,9.37L4.57,11C4.53,11.34 4.5,11.67 4.5,12C4.5,12.33 4.53,12.65 4.57,12.97L2.46,14.63C2.27,14.78 2.21,15.05 2.34,15.27L4.34,18.73C4.46,18.95 4.73,19.03 4.95,18.95L7.44,17.94C7.96,18.34 8.5,18.68 9.13,18.93L9.5,21.58C9.54,21.82 9.75,22 10,22H14C14.25,22 14.46,21.82 14.5,21.58L14.87,18.93C15.5,18.67 16.04,18.34 16.56,17.94L19.05,18.95C19.27,19.03 19.54,18.95 19.66,18.73L21.66,15.27C21.78,15.05 21.73,14.78 21.54,14.63L19.43,12.97Z'
    App       = 'M19,4C20.11,4 21,4.9 21,6V18A2,2 0 0,1 19,20H5C3.89,20 3,19.1 3,18V6A2,2 0 0,1 5,4H19M19,18V8H5V18H19Z'
    NewFile   = 'M14,2H6A2,2 0 0,0 4,4V20A2,2 0 0,0 6,22H18A2,2 0 0,0 20,20V8L14,2M18,20H6V4H13V9H18V20M13,12V10H11V12H9V14H11V16H13V14H15V12H13Z'
    Send      = 'M2,21L23,12L2,3V10L17,12L2,14V21Z'
    Puzzle    = 'M20.5,11H19V7C19,5.89 18.1,5 17,5H13V3.5A2.5,2.5 0 0,0 10.5,1A2.5,2.5 0 0,0 8,3.5V5H4A2,2 0 0,0 2,7V10.8H3.5C5,10.8 6.2,12 6.2,13.5C6.2,15 5,16.2 3.5,16.2H2V20A2,2 0 0,0 4,22H7.8V20.5C7.8,19 9,17.8 10.5,17.8C12,17.8 13.2,19 13.2,20.5V22H17A2,2 0 0,0 19,20V16H20.5A2.5,2.5 0 0,0 23,13.5A2.5,2.5 0 0,0 20.5,11Z'
}
