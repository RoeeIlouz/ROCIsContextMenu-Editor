# ==============================================================================
# ACTIONS (no UI)
# ==============================================================================
function Get-RequiredHive($Item, [bool]$Enable) {
    if ($Item.Kind -eq 'Command' -or $Item.Kind -eq 'New') { return $Item.Hive }
    if ($Item.Kind -eq 'SendTo') { return 'HKCU' }
    if ($Enable) {
        if ($Item.BlockedNames.ContainsKey('HKLM')) { return 'HKLM' }
        if ($Item.DashPaths.Count -gt 0) { return $Item.Hive }
    }
    return 'HKCU'
}

function Set-EntryEnabled($Item, [bool]$Enable) {
    if ($Item.Kind -eq 'Command') {
        $k = (Get-HiveRoot $Item.Hive).OpenSubKey($Item.SubPath, $true)
        if (-not $k) { throw "Registry key no longer exists: $($Item.SubPath)" }
        try {
            if ($Enable) {
                $k.DeleteValue('LegacyDisable', $false)
                $k.DeleteValue('ProgrammaticAccessOnly', $false)
            } else {
                $k.SetValue('LegacyDisable', '')
            }
        } finally { $k.Close() }
        return
    }
    if ($Item.Kind -eq 'New') {
        # Windows ignores a ShellNew key under any other name, so renaming it is a reversible off switch.
        Rename-RegKey $Item.Hive $Item.SubPath $(if ($Enable) { 'ShellNew' } else { '_ShellNew' })
        return
    }
    if ($Item.Kind -eq 'SendTo') {
        # Send To skips hidden files (and hidden submenu folders).
        $fi = Get-Item -LiteralPath $Item.FilePath -Force -ErrorAction SilentlyContinue
        if (-not $fi) { throw "File no longer exists: $($Item.FilePath)" }
        $hidden = [int][IO.FileAttributes]::Hidden
        $fi.Attributes = [IO.FileAttributes]$(if ($Enable) { [int]$fi.Attributes -band -bnot $hidden } else { [int]$fi.Attributes -bor $hidden })
        return
    }

    if ($Enable) {
        foreach ($hive in @($Item.BlockedNames.Keys)) {
            $k = (Get-HiveRoot $hive).OpenSubKey($BlockedPath, $true)
            if ($k) { try { $k.DeleteValue($Item.BlockedNames[$hive], $false) } finally { $k.Close() } }
        }
        foreach ($p in $Item.DashPaths) {
            $k = (Get-HiveRoot $Item.Hive).OpenSubKey($p, $true)
            if ($k) { try { $k.SetValue('', ([string]$k.GetValue('')).TrimStart('-')) } finally { $k.Close() } }
        }
    } else {
        $k = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($BlockedPath)
        try { $k.SetValue($Item.Clsid, $Item.Name) } finally { $k.Close() }
    }
}

function Backup-RegKey([string]$Hive, [string]$SubPath, [string]$Label) {
    if (-not (Test-Path -LiteralPath $App.BackupDir)) { New-Item -ItemType Directory -Path $App.BackupDir -Force | Out-Null }
    $safe = $Label -replace '[^\w.-]', '_'
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $file = Join-Path $App.BackupDir "$($stamp)_$safe.reg"
    $i = 2
    while (Test-Path -LiteralPath $file) { $file = Join-Path $App.BackupDir "$($stamp)_$($safe)_$i.reg"; $i++ }
    & reg.exe export "$Hive\$SubPath" $file /y *> $null
    if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $file)) { return $file }
    return $null
}

# Exports several keys into one .reg file. $Keys is a list of "HIVE\SubPath" strings; missing keys are skipped.
function Export-RegKeys([string[]]$Keys, [string]$File) {
    $sb = [Text.StringBuilder]::new()
    [void]$sb.AppendLine('Windows Registry Editor Version 5.00')
    $count = 0
    foreach ($key in $Keys) {
        $p = Split-RegPath $key
        $k = (Get-HiveRoot $p.Hive).OpenSubKey($p.SubPath)
        if (-not $k) { continue }
        $k.Close()
        $tmp = [IO.Path]::GetTempFileName()
        & reg.exe export "$($p.Hive)\$($p.SubPath)" $tmp /y *> $null
        if ($LASTEXITCODE -eq 0) {
            $t = [IO.File]::ReadAllText($tmp)
            [void]$sb.Append($t.Substring($t.IndexOf("`n") + 1))
            $count++
        }
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }
    [IO.File]::WriteAllText($File, $sb.ToString(), [Text.Encoding]::Unicode)
    return $count
}

function Export-FullBackup {
    if (-not (Test-Path -LiteralPath $App.BackupDir)) { New-Item -ItemType Directory -Path $App.BackupDir -Force | Out-Null }
    $file = Join-Path $App.BackupDir ('{0}_full_context_menu.reg' -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
    $paths = @(foreach ($b in $BaseKeys.Keys) { "Software\Classes\$b\shell"; "Software\Classes\$b\shellex\ContextMenuHandlers" }) + $BlockedPath
    $keys = foreach ($hive in 'HKCU', 'HKLM') { foreach ($p in $paths) { "$hive\$p" } }
    [void](Export-RegKeys $keys $file)
    return $file
}

# Your own setup, for moving to another PC: per-user commands and submenus, the per-user Blocked list
# and the classic-menu switch. Machine-wide entries belong to installed programs and are left out.
function Export-Setup([string]$File) {
    $keys = @(foreach ($b in $BaseKeys.Keys) { "HKCU\Software\Classes\$b\shell" }) + "HKCU\$BlockedPath" + "HKCU\$ClassicKey"
    return Export-RegKeys $keys $File
}

function Split-RegPath([string]$Path) {
    $i = $Path.IndexOf('\')
    if ($i -lt 0) { return $null }
    $hive = switch ($Path.Substring(0, $i)) { 'HKEY_CURRENT_USER' { 'HKCU' } 'HKCU' { 'HKCU' } 'HKEY_LOCAL_MACHINE' { 'HKLM' } 'HKLM' { 'HKLM' } default { $null } }
    if (-not $hive) { return $null }
    return @{ Hive = $hive; SubPath = $Path.Substring($i + 1) }
}

function Remove-RegTree([string]$Hive, [string]$SubPath) {
    $i = $SubPath.LastIndexOf('\')
    $parent = (Get-HiveRoot $Hive).OpenSubKey($SubPath.Substring(0, $i), $true)
    if ($parent) { try { $parent.DeleteSubKeyTree($SubPath.Substring($i + 1), $false) } finally { $parent.Close() } }
}

# Deletes a command (with anything inside it) or a broken shell-extension registration.
# Every key is backed up before anything is removed. Returns the backup files.
function Remove-MenuEntry($Item) {
    if (-not $Item.CanDelete) { throw 'Only commands and broken extensions can be deleted. Turn other extensions off instead.' }
    if ($Item.Kind -eq 'SendTo') {
        # Send To items are files or submenu folders: move them into Backups\SendTo\<stamp>-<n>\<path inside
        # Send To>, keeping the submenu folder, so a restore puts them back exactly where they were.
        $root = Join-Path $App.BackupDir 'SendTo'
        $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $n = 1
        while (Test-Path -LiteralPath (Join-Path $root "$stamp-$n")) { $n++ }
        $box = Join-Path $root "$stamp-$n"
        $dest = Join-Path $box $Item.KeyName
        New-Item -ItemType Directory -Path (Split-Path -Parent $dest) -Force | Out-Null
        Move-Item -LiteralPath $Item.FilePath -Destination $dest -Force
        return , @($box)
    }
    $backups = @()
    foreach ($p in $Item.Paths) {
        $b = Backup-RegKey $Item.Hive $p "deleted_$($p.Split('\')[-1])"
        if (-not $b) { throw 'Could not write a backup, so nothing was deleted.' }
        $backups += $b
    }
    foreach ($p in $Item.Paths) { Remove-RegTree $Item.Hive $p }
    return , $backups
}

function Get-BackupInfo([IO.FileInfo]$File) {
    $text = try { [IO.File]::ReadAllText($File.FullName) } catch { '' }
    $roots = [System.Collections.Generic.List[string]]::new()
    foreach ($m in [regex]::Matches($text, '(?m)^\[(?!-)([^\]\r\n]+)\]')) {
        $k = $m.Groups[1].Value
        $covered = $false
        foreach ($r in $roots) { if ($k -eq $r -or $k.StartsWith("$r\", [StringComparison]::OrdinalIgnoreCase)) { $covered = $true; break } }
        if (-not $covered) { $roots.Add($k) }
    }

    $label = $File.BaseName
    $when = $File.LastWriteTime
    $m = [regex]::Match($File.BaseName, '^(\d{8}_\d{6})_(.+)$')
    if ($m.Success) {
        $label = $m.Groups[2].Value
        $when = [datetime]::ParseExact($m.Groups[1].Value, 'yyyyMMdd_HHmmss', [Globalization.CultureInfo]::InvariantCulture)
    }
    $action, $name = switch -Regex ($label) {
        '^deleted_(.+)$'        { 'Deleted', $Matches[1]; break }
        '^edited_(.+)$'         { 'Before edit', $Matches[1]; break }
        '^before-restore_(.+)$' { 'Before restore', $Matches[1]; break }
        '^full_context_menu'    { 'Full backup', 'All context menu keys'; break }
        default                 { 'Backup', $label }
    }
    $isFull = $action -eq 'Full backup' -or $roots.Count -gt 1
    if (-not $isFull) {
        $mv = [regex]::Match($text, '(?m)^"MUIVerb"="((?:[^"\\]|\\.)*)"')
        if (-not $mv.Success) { $mv = [regex]::Match($text, '(?m)^@="((?:[^"\\]|\\.)*)"') }
        if ($mv.Success) {
            $friendly = Resolve-MenuText ($mv.Groups[1].Value -replace '\\(.)', '$1')
            if ($friendly) { $name = $friendly }
        }
    }

    $whenText = Format-When $when
    $keyText = if ($roots.Count -eq 1) { $roots[0] -replace '^HKEY_CURRENT_USER', 'HKCU' -replace '^HKEY_LOCAL_MACHINE', 'HKLM' }
               else { "$($roots.Count) registry keys" }

    [pscustomobject]@{
        File = $File.FullName; FileName = $File.Name; Name = $name; Action = $action; When = $when; WhenText = $whenText
        Roots = $roots.ToArray(); KeyText = $keyText; IsFull = $isFull
        NeedsAdmin = [bool]($roots | Where-Object { $_ -like 'HKEY_LOCAL_MACHINE*' })
    }
}

function Format-When([datetime]$When) {
    $today = (Get-Date).Date
    if ($When.Date -eq $today) { return 'Today, ' + $When.ToString('HH:mm') }
    if ($When.Date -eq $today.AddDays(-1)) { return 'Yesterday, ' + $When.ToString('HH:mm') }
    if ($When.Year -eq $today.Year) { return $When.ToString('MMM d, HH:mm') }
    return $When.ToString('MMM d yyyy, HH:mm')
}

function Get-Backups {
    if (-not (Test-Path -LiteralPath $App.BackupDir)) { return @() }
    $list = [System.Collections.Generic.List[object]]::new()
    foreach ($f in Get-ChildItem -LiteralPath $App.BackupDir -Filter *.reg -File) { $list.Add((Get-BackupInfo $f)) }
    $sendDir = Join-Path $App.BackupDir 'SendTo'
    if (Test-Path -LiteralPath $sendDir) {
        foreach ($f in Get-ChildItem -LiteralPath $sendDir -Force) {
            # Current format: folder "<stamp>-<n>" holding the item at its path inside Send To.
            # Older format: file "<stamp>_<name>" that lived at the top of Send To.
            $box = [regex]::Match($f.Name, '^(\d{8}_\d{6})-\d+$')
            $old = [regex]::Match($f.Name, '^(\d{8}_\d{6})_(.+)$')
            if ($box.Success -and $f.PSIsContainer) {
                $inner = Get-ChildItem -LiteralPath $f.FullName -Force | Select-Object -First 1
                if (-not $inner) { continue }
                $rel = $inner.Name
                if ($inner.PSIsContainer) {
                    # One item inside means a single entry of that submenu was deleted; several means the whole submenu.
                    $leaf = @(Get-ChildItem -LiteralPath $inner.FullName -Force | Where-Object Name -ine 'desktop.ini')
                    if ($leaf.Count -eq 1) { $rel = "$($inner.Name)\$($leaf[0].Name)" }
                }
                $when = [datetime]::ParseExact($box.Groups[1].Value, 'yyyyMMdd_HHmmss', [Globalization.CultureInfo]::InvariantCulture)
                $display = ([IO.Path]::GetFileNameWithoutExtension($rel.Split('\')[-1]))
                if ($rel.Contains('\')) { $display = "$($rel.Split('\')[0]) > $display" }
                $list.Add([pscustomobject]@{
                    File = $f.FullName; FileName = $f.Name; Name = $display; Action = 'Deleted'
                    When = $when; WhenText = Format-When $when; Roots = @(); KeyText = "Send to: $rel"; IsFull = $false; NeedsAdmin = $false
                })
            } elseif (-not $f.PSIsContainer) {
                $orig = if ($old.Success) { $old.Groups[2].Value } else { $f.Name }
                $when = if ($old.Success) { [datetime]::ParseExact($old.Groups[1].Value, 'yyyyMMdd_HHmmss', [Globalization.CultureInfo]::InvariantCulture) } else { $f.LastWriteTime }
                $list.Add([pscustomobject]@{
                    File = $f.FullName; FileName = $f.Name; Name = [IO.Path]::GetFileNameWithoutExtension($orig); Action = 'Deleted'
                    When = $when; WhenText = Format-When $when; Roots = @(); KeyText = "Send to: $orig"; IsFull = $false; NeedsAdmin = $false
                })
            }
        }
    }
    return @($list | Sort-Object When -Descending)
}

# Replace mode (default) deletes each key in the file first so the result matches the backup exactly;
# merge mode only adds what the file contains. The current state is backed up before anything is removed,
# and put back if the import fails.
function Restore-BackupFile([string]$File, [switch]$Merge) {
    if (Test-Path -LiteralPath $File -PathType Container) {
        # A Send To item moved aside by Remove-MenuEntry: merge the box's contents back into Send To,
        # which also recreates a submenu folder if it was removed.
        foreach ($inner in Get-ChildItem -LiteralPath $File -Force) {
            $dest = Join-Path (Get-SendToDir) $inner.Name
            if ($inner.PSIsContainer -and (Test-Path -LiteralPath $dest)) {
                foreach ($c in Get-ChildItem -LiteralPath $inner.FullName -Force) { Copy-Item -LiteralPath $c.FullName -Destination (Join-Path $dest $c.Name) -Recurse -Force }
            } else {
                Copy-Item -LiteralPath $inner.FullName -Destination $dest -Recurse -Force
            }
        }
        return , @()
    }
    if ([IO.Path]::GetExtension($File) -ne '.reg') {
        # Older Send To backups: a single file "<stamp>_<name>" from the top of Send To.
        $orig = [IO.Path]::GetFileName($File) -replace '^\d{8}_\d{6}_', ''
        Copy-Item -LiteralPath $File -Destination (Join-Path (Get-SendToDir) $orig) -Force
        return , @()
    }
    $info = Get-BackupInfo ([IO.FileInfo]::new($File))
    $pre = @()
    if (-not $Merge) {
        foreach ($r in $info.Roots) {
            $p = Split-RegPath $r
            if (-not $p) { continue }
            $k = (Get-HiveRoot $p.Hive).OpenSubKey($p.SubPath)
            if (-not $k) { continue }
            $k.Close()
            $b = Backup-RegKey $p.Hive $p.SubPath "before-restore_$($p.SubPath.Split('\')[-1])"
            if (-not $b) { throw 'Could not back up the current version, so nothing was restored.' }
            $pre += $b
            Remove-RegTree $p.Hive $p.SubPath
        }
    }
    & reg.exe import $File *> $null
    if ($LASTEXITCODE -ne 0) {
        foreach ($b in $pre) { & reg.exe import $b *> $null }
        throw "Windows could not import $([IO.Path]::GetFileName($File)). Nothing was changed."
    }
    return , $pre
}

# Creates or updates a static verb or submenu. $ShellPath is the "...\shell" key it lives in
# (a submenu's own "shell" key for commands inside it). Returns the entry Id of the saved item.
function Save-MenuCommand {
    param($Existing, [string]$Name, [string]$Command, [string]$Icon, [string]$Hive, [string]$ShellPath,
          [bool]$Extended, [bool]$Shield, [string]$Position, [bool]$IsSubmenu)

    $root = Get-HiveRoot $Hive
    $moving = $Existing -and ($Existing.Hive -ne $Hive -or $Existing.ShellPath -ne $ShellPath)

    $App.LastBackup = $null
    if ($Existing) {
        $App.LastBackup = Backup-RegKey $Existing.Hive $Existing.SubPath "edited_$($Existing.KeyName)"
        if (-not $App.LastBackup) { throw 'Could not back up the current version, so nothing was changed.' }
    }

    if ($Existing -and -not $moving) {
        $keyName = $Existing.KeyName
    } else {
        $stem = if ($Existing) { $Existing.KeyName } else { ConvertTo-KeyName $Name }
        $keyName = $stem
        $taken = @()
        $sk = $root.OpenSubKey($ShellPath)
        if ($sk) { $taken = $sk.GetSubKeyNames(); $sk.Close() }
        $i = 2
        while ($taken -contains $keyName) { $keyName = "$stem$i"; $i++ }
    }

    $k = $root.CreateSubKey("$ShellPath\$keyName")
    try {
        if ($moving) {
            $src = (Get-HiveRoot $Existing.Hive).OpenSubKey($Existing.SubPath)
            if ($src) { try { Copy-RegTree $src $k } finally { $src.Close() } }
        }

        if (-not $Existing -or $Name -ne $Existing.Name) {
            # A single & is a keyboard accelerator in menus; double it so the name shows as typed.
            $menuText = $Name.Replace('&', '&&')
            $k.SetValue('MUIVerb', $menuText)
            if (-not $Existing) { $k.SetValue('', $menuText) }
        }

        if (-not $Existing -or $Icon -ne $Existing.IconValue) {
            if ($Icon) { Set-RegString $k 'Icon' $Icon } else { $k.DeleteValue('Icon', $false) }
        }

        if ($IsSubmenu) {
            # SubCommands="" plus a nested "shell" key is the static cascading-menu format.
            if (-not $Existing) {
                $k.SetValue('SubCommands', '')
                $k.CreateSubKey('shell').Close()
            }
        } elseif (-not $Existing -or $Command -ne $Existing.Command) {
            $ck = $k.CreateSubKey('command')
            try {
                if ($Command) {
                    Set-RegString $ck '' $Command
                    $ck.DeleteValue('DelegateExecute', $false)
                }
            } finally { $ck.Close() }
        }

        if ($Extended) { $k.SetValue('Extended', '') } else { $k.DeleteValue('Extended', $false) }
        if ($Shield) { $k.SetValue('HasLUAShield', '') } else { $k.DeleteValue('HasLUAShield', $false) }
        if ($Position) { $k.SetValue('Position', $Position) } else { $k.DeleteValue('Position', $false) }
    } finally { $k.Close() }

    if ($moving) { Remove-RegTree $Existing.Hive $Existing.SubPath }
    return "cmd|$Hive|$ShellPath\$keyName"
}

function Test-ClassicMenu {
    $k = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey("$ClassicKey\InprocServer32")
    if ($k) { $k.Close(); return $true }
    return $false
}

function Set-ClassicMenu([bool]$On) {
    if ($On) {
        $k = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey("$ClassicKey\InprocServer32")
        try { $k.SetValue('', '') } finally { $k.Close() }
    } else {
        [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($ClassicKey, $false)
    }
}
