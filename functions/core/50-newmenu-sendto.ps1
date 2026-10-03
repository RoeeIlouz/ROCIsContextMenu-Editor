# ------------------------------------------------------------------------------
# "New" menu (ShellNew keys) and "Send to" (files in the SendTo folder)
# ------------------------------------------------------------------------------
$ShellNewBuiltIn = @('Folder', '.lnk', '.library-ms')

# Class keys that hold a ShellNew key (or our disabled _ShellNew). Walking all of HKCR takes ~250 ms,
# so the list is cached for the session; each scan only re-reads the state of these keys.
function Get-ShellNewParents {
    if ($null -ne $App.ShellNewParents) { return $App.ShellNewParents }
    $list = [System.Collections.Generic.List[string]]::new()
    $hkcr = [Microsoft.Win32.Registry]::ClassesRoot
    $skip = @('OpenWithProgids', 'OpenWithList', 'PersistentHandler', 'ShellEx')
    foreach ($ext in $hkcr.GetSubKeyNames()) {
        if (-not $ext.StartsWith('.')) { continue }
        $k = $null
        try { $k = $hkcr.OpenSubKey($ext) } catch {}
        if (-not $k) { continue }
        try {
            foreach ($sub in $k.GetSubKeyNames()) {
                if ($sub -eq 'ShellNew' -or $sub -eq '_ShellNew') { if (-not $list.Contains($ext)) { $list.Add($ext) }; continue }
                if ($skip -contains $sub) { continue }
                $s2 = $null
                try { $s2 = $k.OpenSubKey($sub) } catch {}
                if (-not $s2) { continue }
                foreach ($n in $s2.GetSubKeyNames()) { if ($n -eq 'ShellNew' -or $n -eq '_ShellNew') { $list.Add("$ext\$sub"); break } }
                $s2.Close()
            }
        } finally { $k.Close() }
    }
    $list.Add('Folder')
    $App.ShellNewParents = $list
    return $list
}

function Get-ProgIdName([string]$ProgId) {
    if (-not $ProgId) { return '' }
    $k = [Microsoft.Win32.Registry]::ClassesRoot.OpenSubKey($ProgId)
    if (-not $k) { return '' }
    try {
        $n = Resolve-MenuText ([string]$k.GetValue('FriendlyTypeName'))
        if (-not $n) { $n = Resolve-MenuText ([string]$k.GetValue('')) }
        return $n
    } finally { $k.Close() }
}

function Read-ShellNew($Out) {
    $hkcr = [Microsoft.Win32.Registry]::ClassesRoot
    foreach ($parent in (Get-ShellNewParents)) {
        foreach ($hive in 'HKCU', 'HKLM') {
            $pk = $null
            try { $pk = (Get-HiveRoot $hive).OpenSubKey("Software\Classes\$parent") } catch {}
            if (-not $pk) { continue }
            $names = $pk.GetSubKeyNames()
            $leaf = if ($names -contains 'ShellNew') { 'ShellNew' } elseif ($names -contains '_ShellNew') { '_ShellNew' } else { $null }
            $sk = if ($leaf) { $pk.OpenSubKey($leaf) } else { $null }
            $pk.Close()
            if (-not $sk) { continue }
            $vals = @{}
            foreach ($n in $sk.GetValueNames()) { $vals[$n.ToLowerInvariant()] = [string]$sk.GetValue($n, '', 'DoNotExpandEnvironmentNames') }
            $sk.Close()

            $ext = $parent.Split('\')[0]
            $progId = if ($parent.Contains('\')) { $parent.Split('\')[1] } elseif ($parent -eq 'Folder') { 'Folder' } else {
                $ek = $hkcr.OpenSubKey($ext)
                if ($ek) { [string]$ek.GetValue(''); $ek.Close() } else { '' }
            }
            $name = if ($vals.itemname) { Resolve-MenuText $vals.itemname } else { '' }
            if (-not $name) { $name = Get-ProgIdName $progId }
            if (-not $name) { $name = "$($ext.TrimStart('.').ToUpperInvariant()) file" }

            $how = if ($parent -eq 'Folder') { 'Creates a folder' }
                   elseif ($vals.ContainsKey('nullfile')) { 'Creates an empty file' }
                   elseif ($vals.filename) { 'Copies a template file' }
                   elseif ($vals.command) { 'Runs a program' }
                   elseif ($vals.ContainsKey('data')) { 'Creates a file from built-in data' }
                   else { 'Built-in handler' }
            $broken = ''
            if ($vals.filename -and (Test-MissingFile $vals.filename)) { $broken = "Template file not found: $($vals.filename)" }
            elseif ($vals.command -and (Test-MissingFile (Get-ExeFromCommand $vals.command))) { $broken = "Program not found: $(Get-ExeFromCommand $vals.command)" }

            $Out.Add((Complete-Entry @{
                Id = "new|$hive|$parent"; Kind = 'New'; Name = $name; Sub = $(if ($parent -eq 'Folder') { $how } else { "$ext  /  $how" })
                KeyName = $ext; Hive = $hive; SubPath = "Software\Classes\$parent\$leaf"; Paths = @("Software\Classes\$parent\$leaf")
                LocIds = @('newmenu'); LocLabel = 'New menu'; Enabled = $leaf -eq 'ShellNew'; IsBuiltIn = $ShellNewBuiltIn -contains $parent
                IconSpec = $(if ($vals.iconpath) { $vals.iconpath } elseif ($parent -eq 'Folder') { 'imageres.dll,-3' } else { "ext:$ext" })
                Command = [string]$vals.command; Target = [string]$vals.filename; Added = $vals.ContainsKey('cmeadded')
                Broken = [bool]$broken; BrokenReason = $broken
            }))
        }
    }
}

function Get-SendToDir { return [Environment]::GetFolderPath('SendTo') }

function Get-Wsh {
    if (-not $App.Wsh) { $App.Wsh = New-Object -ComObject WScript.Shell }
    return $App.Wsh
}

function Get-SendToFileInfo([IO.FileInfo]$File) {
    # Shell display names and shortcut targets are slow to read; cache them per file version.
    $cacheKey = "$($File.FullName)|$($File.LastWriteTimeUtc.Ticks)"
    if (-not $App.SendToCache.ContainsKey($cacheKey)) {
        $info = @{ Name = [CME.Native]::DisplayName($File.FullName); Target = ''; Arguments = ''; Description = '' }
        if ($File.Extension -ieq '.lnk') {
            try {
                $sc = (Get-Wsh).CreateShortcut($File.FullName)
                $info.Target = [string]$sc.TargetPath
                $info.Arguments = [string]$sc.Arguments
                $info.Description = [string]$sc.Description
            } catch {}
        }
        $App.SendToCache[$cacheKey] = $info
    }
    return $App.SendToCache[$cacheKey]
}

function New-SendToFileEntry([IO.FileInfo]$File, [string]$RelPath, [string]$ParentName, [string]$ParentPath) {
    $info = Get-SendToFileInfo $File
    $name = if ($info.Name) { $info.Name } else { $File.BaseName }
    $target = $info.Target; $arguments = $info.Arguments; $broken = ''
    if ($target -and (Test-MissingFile $target)) { $broken = "Shortcut target not found: $target" }
    $sub = if ($target -like '*\CmeSendTo.exe') { if ($info.Description) { $info.Description } else { 'Windows 11 menu command' } }
           elseif ($target) { $target } else {
        switch ($File.Extension.ToLowerInvariant()) {
            '.zfsendtotarget' { 'Built-in: add to a zip file' }
            '.desklink'       { 'Built-in: shortcut on the desktop' }
            '.mapimail'       { 'Built-in: attach to an e-mail' }
            default           { $File.Name }
        }
    }
    return Complete-Entry @{
        Id = "sendto|$RelPath"; Kind = 'SendTo'; Name = $name; Sub = $sub; KeyName = $RelPath; Hive = 'HKCU'
        Paths = @($File.FullName); FilePath = $File.FullName; Target = ((@($target, $arguments) | Where-Object { $_ }) -join ' ')
        LocIds = @('sendto'); LocLabel = 'Send to'; IconSpec = "shell:$($File.FullName)"
        Enabled = -not ($File.Attributes -band [IO.FileAttributes]::Hidden)
        Broken = [bool]$broken; BrokenReason = $broken; ParentName = $ParentName; ParentPath = $ParentPath
    }
}

# Files in the Send To folder are menu items; subfolders show up as submenus of their contents.
function Read-SendTo($Out) {
    $dir = Get-SendToDir
    if (-not $dir -or -not (Test-Path -LiteralPath $dir)) { return }
    foreach ($f in Get-ChildItem -LiteralPath $dir -Force -ErrorAction SilentlyContinue) {
        if ($f.Name -ieq 'desktop.ini') { continue }
        if (-not $f.PSIsContainer) {
            $Out.Add((New-SendToFileEntry $f $f.Name '' ''))
            continue
        }
        $children = @(Get-ChildItem -LiteralPath $f.FullName -Force -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ine 'desktop.ini' })
        foreach ($c in $children) { $Out.Add((New-SendToFileEntry $c "$($f.Name)\$($c.Name)" $f.Name $f.FullName)) }
        $Out.Add((Complete-Entry @{
            Id = "sendto|$($f.Name)"; Kind = 'SendTo'; Name = $f.Name; KeyName = $f.Name; Hive = 'HKCU'
            Sub = "Submenu with $($children.Count) item$(if ($children.Count -ne 1) { 's' })"
            Paths = @($f.FullName); FilePath = $f.FullName; LocIds = @('sendto'); LocLabel = 'Send to'; IconSpec = "shell:$($f.FullName)"
            Enabled = -not ($f.Attributes -band [IO.FileAttributes]::Hidden); Submenu = $true; Children = $children.Count
        }))
    }
}

function Rename-RegKey([string]$Hive, [string]$SubPath, [string]$NewLeaf) {
    $i = $SubPath.LastIndexOf('\')
    $leaf = $SubPath.Substring($i + 1)
    if ($leaf -eq $NewLeaf) { return }
    $parent = (Get-HiveRoot $Hive).OpenSubKey($SubPath.Substring(0, $i), $true)
    if (-not $parent) { throw "Registry key no longer exists: $SubPath" }
    try {
        $src = $parent.OpenSubKey($leaf)
        if (-not $src) { throw "Registry key no longer exists: $SubPath" }
        $dst = $parent.CreateSubKey($NewLeaf)
        try { Copy-RegTree $src $dst } finally { $src.Close(); $dst.Close() }
        $parent.DeleteSubKeyTree($leaf, $false)
    } finally { $parent.Close() }
}

# Adds "New > <type>" (creates an empty file). Returns @{ Hive; SubPath } of the created key.
# Uses HKCU only when the user already has their own key for the extension; creating a fresh
# HKCU\Software\Classes\.ext could shadow the machine-wide association, so otherwise it goes to HKLM.
function Add-ShellNewType([string]$Ext) {
    $ext = '.' + $Ext.Trim().TrimStart('.').ToLowerInvariant()
    if ($ext -match '[^.a-z0-9_+-]' -or $ext -eq '.') { throw 'Enter a file extension such as .txt' }
    $hkcr = [Microsoft.Win32.Registry]::ClassesRoot
    $ek = $hkcr.OpenSubKey($ext)
    $progId = if ($ek) { [string]$ek.GetValue('') } else { '' }
    $existing = if ($ek) { $ek.GetSubKeyNames() } else { @() }
    if ($ek) { $ek.Close() }
    if (-not $progId -or -not (Get-ProgIdName $progId)) {
        throw "Windows names New menu items after the file type's registered program (ProgID), and $ext has none on this PC (its ProgID is '$progId'). Install or set a default app for $ext first."
    }
    if ($existing -contains 'ShellNew') { throw "$ext is already in the New menu." }
    if ($existing -contains '_ShellNew') { throw "$ext is already in the list, turned off. Switch it back on instead." }

    $userKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey("Software\Classes\$ext")
    $hive = if ($userKey) { $userKey.Close(); 'HKCU' } else { 'HKLM' }
    $subPath = "Software\Classes\$ext\ShellNew"
    $k = (Get-HiveRoot $hive).CreateSubKey($subPath)
    try {
        $k.SetValue('NullFile', '')
        $k.SetValue('CMEAdded', '1')
    } finally { $k.Close() }
    if ($App.ShellNewParents -and -not $App.ShellNewParents.Contains($ext)) { $App.ShellNewParents.Add($ext) }
    return @{ Hive = $hive; SubPath = $subPath }
}

# Creates a shortcut in the SendTo folder. Returns its path.
function Add-SendToShortcut([string]$Target) {
    $dir = Get-SendToDir
    $name = if (Test-Path -LiteralPath $Target -PathType Container) { Split-Path -Leaf $Target } else {
        $desc = try { [Diagnostics.FileVersionInfo]::GetVersionInfo($Target).FileDescription } catch { '' }
        if ($desc) { $desc } else { [IO.Path]::GetFileNameWithoutExtension($Target) }
    }
    $name = $name -replace '[\\/:*?"<>|]', '_'
    $path = Join-Path $dir "$name.lnk"
    $i = 2
    while (Test-Path -LiteralPath $path) { $path = Join-Path $dir "$name ($i).lnk"; $i++ }
    $sc = (Get-Wsh).CreateShortcut($path)
    $sc.TargetPath = $Target
    $sc.Save()
    return $path
}
