# ==============================================================================
# MENU PREVIEW
# ==============================================================================
# The preview asks Windows for the real classic ("Show more options") menu of a sample item through
# the same shell API Explorer uses (CME.MenuReader), then matches each row back to an entry:
#   - commands by their verb (the registry key name),
#   - Windows 11 app items by the CLSID they report as their verb,
#   - shell extensions by asking each handler which rows it adds (their rows carry no verb),
#   - Send to items by display name.
#
# What can be reordered, and how (tested on Windows 11 24H2):
#   - Commands sort by key name inside their class (*, then AllFilesystemObjects, ...); Position=Top/Bottom
#     overrides that. Moving one renames its key, so the label (MUIVerb) is unchanged.
#   - Shell extensions sort by handler key name inside their class; moving one renames its handler key.
#   - Send to items sort by display name: files first, then submenu folders, then drives. Moving one
#     prefixes its display name with zero-width spaces via desktop.ini; the files keep their names.
#   - Fixed: Windows 11 app items, Send to itself, and Explorer's own rows (Cut, Copy, Delete, ...).

$PreviewTargets = [ordered]@{
    file       = @{ Label = 'File';              Locs = @('files', 'filetypes', 'sendto') }
    folder     = @{ Label = 'Folder';            Locs = @('folders', 'sendto') }
    background = @{ Label = 'Folder background'; Locs = @('background') }
    desktop    = @{ Label = 'Desktop';           Locs = @('desktop', 'background') }
    drive      = @{ Label = 'Drive';             Locs = @('drives', 'sendto') }
    shortcut   = @{ Label = 'Shortcut';          Locs = @('files', 'shortcuts', 'sendto') }
    program    = @{ Label = 'Program';           Locs = @('files', 'programs', 'sendto') }
    thispc     = @{ Label = 'This PC';           Locs = @('thispc') }
    recyclebin = @{ Label = 'Recycle Bin';       Locs = @('recyclebin') }
}

$SendToClsid = '{7BA4C740-9E81-11CF-99D3-00AA004AE837}'

# Verbs Explorer adds itself. Renaming them would break them, so they never move.
$FixedVerbs = [System.Collections.Generic.HashSet[string]]::new([string[]]@(
    'cut', 'copy', 'paste', 'link', 'delete', 'rename', 'properties', 'openas', 'pintohome', 'pintohomefile', 'PinToStartScreen',
    'Windows.ModernShare', 'PreviousVersions', 'copyaspath', 'format', 'eject', 'manage', 'runas', 'runasuser', 'open', 'explore',
    'opennewwindow', 'opennewprocess', 'opennewtab', 'find', 'print', 'printto', 'edit', 'play', 'enqueue', 'empty', 'mount'
), [StringComparer]::OrdinalIgnoreCase)

# Sample items to right-click. Created once under %LOCALAPPDATA%; never anything of the user's.
function Get-PreviewSubject([string]$Target) {
    $dir = Join-Path $env:LOCALAPPDATA 'ContextMenuEditor\Preview'
    if ($Target -in 'file', 'folder', 'background', 'shortcut' -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    switch ($Target) {
        'file' {
            $ext = if ($App.Ext) { $App.Ext } else { '.txt' }
            $p = Join-Path $dir "Sample$ext"
            if (-not (Test-Path -LiteralPath $p)) { [IO.File]::WriteAllBytes($p, [byte[]]@()) }
            return @{ Path = $p; Background = $false; Label = "Sample$ext" }
        }
        'folder' {
            $p = Join-Path $dir 'Sample folder'
            if (-not (Test-Path -LiteralPath $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
            return @{ Path = $p; Background = $false; Label = 'Sample folder' }
        }
        'background' { return @{ Path = $dir; Background = $true; Label = 'Empty space in a folder' } }
        'desktop'    { return @{ Path = ''; Background = $true; Label = 'Empty space on the desktop' } }
        'drive'      { return @{ Path = "$($env:SystemDrive)\"; Background = $false; Label = "$($env:SystemDrive)\" } }
        'shortcut' {
            $p = Join-Path $dir 'Sample shortcut.lnk'
            if (-not (Test-Path -LiteralPath $p)) {
                $sc = (Get-Wsh).CreateShortcut($p)
                $sc.TargetPath = Join-Path $env:SystemRoot 'notepad.exe'
                $sc.Save()
            }
            return @{ Path = $p; Background = $false; Label = 'Sample shortcut.lnk' }
        }
        'program'    { return @{ Path = (Join-Path $env:SystemRoot 'notepad.exe'); Background = $false; Label = 'notepad.exe' } }
        'thispc'     { return @{ Path = '::{20D04FE0-3AEA-1069-A2D8-08002B30309D}'; Background = $false; Label = 'This PC' } }
        'recyclebin' { return @{ Path = '::{645FF040-5081-101B-9F08-00AA002F954E}'; Background = $false; Label = 'Recycle Bin' } }
    }
    throw "Unknown preview target: $Target"
}

# Where the class of a registry path ("Software\Classes\<class>\shell..." or "...\shellex\...") shows up.
function Get-PathLocs([string]$Path) {
    $m = [regex]::Match($Path, '^Software\\Classes\\(.+?)\\(shell|shellex)\\')
    if (-not $m.Success) { return @() }
    $base = $m.Groups[1].Value
    if ($BaseKeys.Contains($base)) { return $BaseKeys[$base].Locs }
    return @('filetypes')
}

function ConvertTo-PlainText([string]$Text) { return Remove-SortPrefix (Resolve-MenuText $Text) }

# Parent key of an extension's handler key for one class, e.g. Software\Classes\*\shellex\ContextMenuHandlers.
function Get-HandlerContainer($Entry, [string]$Path) { return $Path.Substring(0, $Path.LastIndexOf('\')) }

function New-PreviewRow([hashtable]$d) {
    $defaults = @{
        Text = ''; Separator = $false; IsDefault = $false; Disabled = $false; Children = @(); Entry = $null; Group = ''
        SortKey = ''; Movable = $false; Lock = ''; Source = ''; Container = ''; HandlerPath = ''; Synthetic = $false
    }
    foreach ($k in $defaults.Keys) { if (-not $d.ContainsKey($k)) { $d[$k] = $defaults[$k] } }
    $d.HasChildren = @($d.Children).Count -gt 0
    $d.IconImage = if ($d.Entry) { $d.Entry.IconImage } else { $null }
    $d.Weight = if ($d.IsDefault) { 'SemiBold' } else { 'Normal' }
    $d.Opacity = if ($d.Disabled) { 0.45 } else { 1.0 }
    $d.LockVisible = if (-not $d.Separator -and -not $d.Movable) { 'Visible' } else { 'Collapsed' }
    $d.ChevronVisible = if ($d.HasChildren) { 'Visible' } else { 'Collapsed' }
    $d.RowVisible = if ($d.Separator) { 'Collapsed' } else { 'Visible' }
    $d.SepVisible = if ($d.Separator) { 'Visible' } else { 'Collapsed' }
    $d.Tip = if ($d.Separator) { $null } elseif ($d.Movable) { "Drag to move. $($d.Source)" } else { $d.Lock }
    return [pscustomobject]$d
}

# How many zero-width spaces Set-SendToOrder put in front of an item's display name, read from desktop.ini.
# (The shell caches display names per process, so asking it would show the order from before a move.)
function Get-SendToPrefix($Entry, $IniCache) {
    $ini = if ($Entry.Submenu) { Join-Path $Entry.FilePath 'desktop.ini' } else { Join-Path (Split-Path -Parent $Entry.FilePath) 'desktop.ini' }
    if (-not $IniCache.ContainsKey($ini)) { $IniCache[$ini] = Read-IniLines $ini }
    $v = if ($Entry.Submenu) { Get-IniValue $IniCache[$ini] '.ShellClassInfo' 'LocalizedResourceName' }
         else { Get-IniValue $IniCache[$ini] 'LocalizedFileNames' (Split-Path -Leaf $Entry.FilePath) }
    if (-not $v) { return 0 }
    return $v.Length - (Remove-SortPrefix $v).Length
}

# Send to's own order, which compares display names: items with more zero-width spaces in front come
# first, then Explorer's logical name order.
function Sort-SendToEntries([object[]]$Entries) {
    $cache = @{}
    $list = [System.Collections.Generic.List[object]]::new()
    foreach ($e in $Entries) { $list.Add([pscustomobject]@{ Entry = $e; Prefix = (Get-SendToPrefix $e $cache) }) }
    $list.Sort([Comparison[object]]{
        param($a, $b)
        if ($a.Prefix -ne $b.Prefix) { return $b.Prefix - $a.Prefix }
        return [CME.Native]::CompareLogical($a.Entry.Name, $b.Entry.Name)
    })
    return @($list | ForEach-Object Entry)
}

# Send to's top level: single items, then submenu folders, then what Windows adds (drives, phones).
function Get-SendToRootRows($Ctx, $Nodes) {
    $root = Get-SendToDir
    $mine = @($Ctx.SendTo | Where-Object Enabled)
    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($e in (Sort-SendToEntries @($mine | Where-Object { -not $_.Submenu }))) {
        $rows.Add((New-PreviewRow @{ Text = $e.Name; Entry = $e; Group = 'sendto|root|file'; SortKey = $e.Name; Movable = $true; Container = $root
            Source = 'Moves among the Send to items. Submenu folders and drives always come after them.' }))
    }
    foreach ($e in (Sort-SendToEntries @($mine | Where-Object Submenu))) {
        $rows.Add((New-PreviewRow @{ Text = $e.Name; Entry = $e; Group = 'sendto|root|folder'; SortKey = $e.Name; Movable = $true; Container = $root
            Children = @(Get-SendToFolderRows $e); Source = 'Submenu folders always come after the single items; they move among themselves.' }))
    }
    $names = @($mine | ForEach-Object Name)
    $extra = @($Nodes | Where-Object { -not $_.Separator } | ForEach-Object { ConvertTo-PlainText $_.Text } | Where-Object { $_ -and $names -notcontains $_ })
    # After a Send to change this process's shell cache can return the submenu half-built; keep the last full list.
    if ($extra.Count) { $App.SendToExtras = $extra } elseif ($App.SendToExtras) { $extra = $App.SendToExtras }
    foreach ($t in $extra) { $rows.Add((New-PreviewRow @{ Text = $t; Lock = 'Drives and devices are added by Windows and always come last.' })) }
    return $rows.ToArray()
}

# Rows for a Send to submenu folder, which Windows fills only when it opens: built from the folder itself.
function Get-SendToFolderRows($Folder) {
    $kids = @($App.Items | Where-Object { $_.Kind -eq 'SendTo' -and $_.ParentPath -eq $Folder.FilePath -and $_.Enabled })
    foreach ($k in (Sort-SendToEntries $kids)) {
        New-PreviewRow @{
            Text = $k.Name; Entry = $k; Group = "sendto|$($Folder.FilePath)|file"; SortKey = $k.Name; Movable = $true
            Source = "Moves within the `"$($Folder.Name)`" submenu."; Container = $Folder.FilePath
        }
    }
}

function ConvertTo-PreviewRows($Nodes, $Ctx, $Parent) {
    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($n in $Nodes) {
        if ($n.Separator) {
            # Windows drops doubled and trailing separators when it shows the menu.
            if ($rows.Count -and -not $rows[$rows.Count - 1].Separator) { $rows.Add((New-PreviewRow @{ Separator = $true })) }
            continue
        }
        $text = ConvertTo-PlainText $n.Text
        $d = @{ Text = $text; IsDefault = $n.IsDefault; Disabled = $n.Disabled }
        $verb = [string]$n.Verb
        $clsid = ConvertTo-Clsid $verb
        $childRows = @()

        if ($Parent -and $Parent.Kind -eq 'Command') {
            $e = $Ctx.Commands | Where-Object { $_.ParentPath -eq $Parent.Entry.SubPath -and $_.KeyName -eq $verb } | Select-Object -First 1
            if ($e) {
                $d.Entry = $e; $d.SortKey = $e.KeyName; $d.Movable = $true
                $d.Group = "cmd|$($e.ShellPath)|$($e.Position)"
                $d.Source = "Moves within the `"$($Parent.Entry.Name)`" submenu."
            } else {
                $d.Lock = "Part of the `"$($Parent.Entry.Name)`" submenu."
            }
        } elseif ($Parent) {
            $d.Lock = "Part of the `"$($Parent.Text)`" submenu, which its app builds."
        } elseif ($clsid -or (-not $verb -and ($m = $Ctx.Modern | Where-Object { $_.Name -eq $text } | Select-Object -First 1))) {
            $d.Entry = if ($clsid) { $Ctx.Modern | Where-Object { $_.Clsid -eq $clsid } | Select-Object -First 1 } else { $m }
            $d.Lock = 'A Windows 11 app item. Windows decides where these go; you can turn it off.'
        } elseif (($verb -and ($c = $Ctx.Commands | Where-Object { -not $_.ParentName -and $_.KeyName -eq $verb } | Sort-Object { $_.Hive -ne 'HKCU' } | Select-Object -First 1)) -or
                  (-not $verb -and @($n.Children).Count -and ($c = $Ctx.Commands | Where-Object { -not $_.ParentName -and $_.Submenu -and $_.Name -eq $text } | Sort-Object { $_.Hive -ne 'HKCU' } | Select-Object -First 1))) {
            $d.Entry = $c
            if ($FixedVerbs.Contains($c.KeyName) -or $SystemVerbs.Contains($c.KeyName)) {
                $d.Lock = 'A standard Windows verb. Its key name is what makes it work, so it stays where Windows puts it.'
            } elseif ($c.Position) {
                $d.Movable = $true; $d.SortKey = $c.KeyName; $d.Group = "cmd|$($c.ShellPath)|$($c.Position)"
                $d.Source = "Pinned to the $($c.Position.ToLower()); moves among the other pinned commands. Unpin it to move it with the rest."
            } else {
                $d.Movable = $true; $d.SortKey = $c.KeyName; $d.Group = "cmd|$($c.ShellPath)|"
                $d.Source = "Moves among the commands registered for $($c.LocLabel.ToLower()) ($($c.BaseKey)). Pin it to the top to put it above everything."
            }
        } elseif (-not $verb -and $Ctx.HandlerText.ContainsKey($text)) {
            $h = $Ctx.HandlerText[$text]
            $d.Entry = $h.Entry
            if ($h.Entry.Clsid -eq $SendToClsid) {
                $d.Lock = 'Windows always puts Send to in its own section above Cut and Copy. Its items can be reordered.'
            } else {
                $d.Movable = $true; $d.SortKey = $h.KeyName; $d.Group = "ext|$($h.Container)"; $d.HandlerPath = $h.Path; $d.Container = $h.Container
                $d.Source = 'Moves among the shell extensions registered for the same kind of item.'
            }
        } elseif ($verb -and $FixedVerbs.Contains($verb)) {
            $d.Lock = 'Built into Explorer. It always appears in this spot.'
        } else {
            $d.Lock = 'Built into Windows, or added by something this editor can''t reorder.'
        }

        if (-not $Parent -and $text -and $d.Entry -and $d.Entry.Clsid -eq $SendToClsid) {
            $childRows = @(Get-SendToRootRows $Ctx $n.Children)
        } elseif (-not $childRows -and @($n.Children).Count) {
            $p = if ($d.Entry -and $d.Entry.Kind -eq 'Command') { @{ Kind = 'Command'; Entry = $d.Entry } } else { @{ Kind = 'Other'; Text = $text } }
            $childRows = @(ConvertTo-PreviewRows $n.Children $Ctx $p)
        }
        $d.Children = $childRows
        $rows.Add((New-PreviewRow $d))
    }
    while ($rows.Count -and $rows[$rows.Count - 1].Separator) { $rows.RemoveAt($rows.Count - 1) }
    return $rows.ToArray()
}

# Returns @{ Rows; Subject; Off } for a preview target. Off lists entries for that place that are turned off.
function Get-MenuPreview([string]$Target, [bool]$Shift) {
    $subject = Get-PreviewSubject $Target
    $locs = $PreviewTargets[$Target].Locs
    $nodes = [CME.MenuReader]::Read($subject.Path, $subject.Background, $Shift)

    $here = @($App.Items | Where-Object { $_.Kind -eq 'Modern' -or @($_.LocIds | Where-Object { $locs -contains $_ }).Count })
    $ctx = @{
        Modern   = @($here | Where-Object Kind -eq 'Modern')
        Commands = @($here | Where-Object Kind -eq 'Command')
        SendTo   = @($here | Where-Object { $_.Kind -eq 'SendTo' -and -not $_.ParentName })
        HandlerText = @{}
    }
    # Which handler adds which row: ask each one for its own rows.
    foreach ($e in @($here | Where-Object { $_.Kind -eq 'Extension' -and $_.Enabled -and -not $_.DragDrop })) {
        # The handler key of the class that applies here (an extension can be registered for several).
        $path = $e.Paths | Where-Object { @((Get-PathLocs $_) | Where-Object { $locs -contains $_ }).Count } | Select-Object -First 1
        if (-not $path) { continue }
        $texts = @()
        try { $texts = [CME.MenuReader]::ReadHandler($subject.Path, $subject.Background, $e.Clsid, $Shift) } catch {}
        $keyName = $path.Substring($path.LastIndexOf('\') + 1)
        foreach ($t in $texts) {
            $plain = ConvertTo-PlainText $t
            if ($plain -and -not $ctx.HandlerText.ContainsKey($plain)) {
                $ctx.HandlerText[$plain] = @{ Entry = $e; Path = $path; KeyName = $keyName; Container = (Get-HandlerContainer $e $path) }
            }
        }
    }

    $rows = @(ConvertTo-PreviewRows $nodes $ctx $null)
    if ($subject.Background) {
        # The folder window adds these itself; the menu API doesn't include them.
        $lock = 'Added by the folder window itself.'
        $top = @('View', 'Sort by', 'Group by') | ForEach-Object { New-PreviewRow @{ Text = $_; Lock = $lock; Synthetic = $true } }
        $mid = @('Refresh') + $(if ($Target -eq 'background') { @('Paste', 'Paste shortcut') } else { @('Paste') }) |
            ForEach-Object { New-PreviewRow @{ Text = $_; Lock = $lock; Synthetic = $true } }
        $rows = @($top) + @($mid) + @(New-PreviewRow @{ Separator = $true }) + $rows
    }
    $off = @($here | Where-Object { -not $_.Enabled -and $_.Kind -ne 'Modern' -and ($App.ShowBuiltIn -or -not $_.IsBuiltIn) } | Sort-Object Kind, Name)
    $offModern = @($ctx.Modern | Where-Object { -not $_.Enabled -and @($_.LocIds | Where-Object { $locs -contains $_ }).Count })
    return @{ Rows = $rows; Subject = $subject; Off = @($off) + @($offModern) }
}

# ------------------------------------------------------------------------------
# Reordering
# ------------------------------------------------------------------------------
# $Order is the group's rows in their new order; $Row is the one that moved.
# Returns @{ Undo = record for Set-Undo; Label; NeedsAdmin }.
function Move-MenuRow($Row, [object[]]$Order) {
    $i = [Array]::IndexOf($Order, $Row)
    $prev = if ($i -gt 0) { $Order[$i - 1] } else { $null }
    $next = if ($i -lt $Order.Count - 1) { $Order[$i + 1] } else { $null }
    if ($Row.Group -like 'sendto|*') { return Set-SendToOrder $Row $Order }

    $frac = Get-KeyBetween $(if ($prev) { $prev.SortKey } else { '' }) $(if ($next) { $next.SortKey } else { '' })
    if ($null -eq $frac) { throw 'There is no room for it there: the names of the entries around it are too close. Try moving one of them instead.' }
    $e = $Row.Entry
    $base = if ($e.OrigKey) { $e.OrigKey } else { $Row.SortKey }
    $newKey = "$frac-$base"

    if ($Row.Group -like 'cmd|*') {
        $hive = $e.Hive; $sub = $e.SubPath
        $parentPath = $sub.Substring(0, $sub.LastIndexOf('\'))
        $backup = Backup-RegKey $hive $sub "reorder_$($e.KeyName)"
        $k = (Get-HiveRoot $hive).OpenSubKey($sub, $true)
        if (-not $k) { throw "Registry key no longer exists: $sub" }
        try {
            # The label must not depend on the key name, which is about to change.
            if (-not [string]$k.GetValue('MUIVerb') -and -not [string]$k.GetValue('')) { $k.SetValue('MUIVerb', $e.Name) }
            if (-not $e.OrigKey) { $k.SetValue('CMEOrigKey', $e.KeyName) }
        } finally { $k.Close() }
        Rename-RegKey $hive $sub $newKey
        # A class's default verb is named by its shell key; keep pointing at the renamed key.
        $pk = (Get-HiveRoot $hive).OpenSubKey($parentPath, $true)
        if ($pk) { try { if ([string]$pk.GetValue('') -eq $e.KeyName) { $pk.SetValue('', $newKey) } } finally { $pk.Close() } }
        $files = @($backup | Where-Object { $_ })
        return @{ Label = "moved $($e.Name)"; Undo = @{ Type = 'restore'; Files = $files; DeletePaths = @(@{ Hive = $hive; SubPath = "$parentPath\$newKey" }); NeedsAdmin = $hive -eq 'HKLM'; Label = "moving $($e.Name)" } }
    }

    # Shell extension: rename its handler key in this class.
    $hive = $e.Hive; $sub = $Row.HandlerPath
    $backup = Backup-RegKey $hive $sub "reorder_$($Row.SortKey)"
    $k = (Get-HiveRoot $hive).OpenSubKey($sub, $true)
    if (-not $k) { throw "Registry key no longer exists: $sub" }
    try {
        # A handler named by its CLSID with no value gets its CLSID from the name; keep it once renamed.
        if (-not (ConvertTo-Clsid ([string]$k.GetValue('')))) { $k.SetValue('', $e.Clsid) }
        if (-not $e.OrigKey) { $k.SetValue('CMEOrigKey', $Row.SortKey) }
    } finally { $k.Close() }
    Rename-RegKey $hive $sub $newKey
    $files = @($backup | Where-Object { $_ })
    return @{ Label = "moved $($e.Name)"; Undo = @{ Type = 'restore'; Files = $files; DeletePaths = @(@{ Hive = $hive; SubPath = "$($Row.Container)\$newKey" }); NeedsAdmin = $hive -eq 'HKLM'; Label = "moving $($e.Name)" } }
}

# Puts a command or shell extension back under its original key name.
function Reset-MenuOrder($Entry, [string]$Path) {
    if (-not $Entry.OrigKey) { return $null }
    $backup = Backup-RegKey $Entry.Hive $Path "reorder_reset_$($Entry.OrigKey)"
    $parentPath = $Path.Substring(0, $Path.LastIndexOf('\'))
    $current = $Path.Substring($Path.LastIndexOf('\') + 1)
    $k = (Get-HiveRoot $Entry.Hive).OpenSubKey($Path, $true)
    if ($k) { try { $k.DeleteValue('CMEOrigKey', $false) } finally { $k.Close() } }
    Rename-RegKey $Entry.Hive $Path $Entry.OrigKey
    $pk = (Get-HiveRoot $Entry.Hive).OpenSubKey($parentPath, $true)
    if ($pk) { try { if ([string]$pk.GetValue('') -eq $current) { $pk.SetValue('', $Entry.OrigKey) } } finally { $pk.Close() } }
    return @{ Type = 'restore'; Files = @($backup | Where-Object { $_ }); DeletePaths = @(@{ Hive = $Entry.Hive; SubPath = "$parentPath\$($Entry.OrigKey)" }); NeedsAdmin = $Entry.Hive -eq 'HKLM'; Label = "resetting $($Entry.Name)" }
}

# ------------------------------------------------------------------------------
# Send to order (desktop.ini display names)
# ------------------------------------------------------------------------------
function Read-IniLines([string]$Path) {
    # The comma keeps PowerShell from unrolling the list into a fixed-size array.
    if (-not (Test-Path -LiteralPath $Path)) { return , [System.Collections.Generic.List[string]]::new() }
    return , [System.Collections.Generic.List[string]]::new([string[]]([IO.File]::ReadAllLines($Path)))
}

# Sets key=value in [Section], adding the section or line as needed. $null removes the key.
function Set-IniValue($Lines, [string]$Section, [string]$Key, $Value) {
    $start = -1
    for ($i = 0; $i -lt $Lines.Count; $i++) { if ($Lines[$i].Trim() -ieq "[$Section]") { $start = $i; break } }
    if ($start -lt 0) {
        if ($null -eq $Value) { return }
        if ($Lines.Count -and $Lines[$Lines.Count - 1].Trim()) { $Lines.Add('') }
        $Lines.Add("[$Section]"); $Lines.Add("$Key=$Value"); return
    }
    $end = $Lines.Count
    for ($i = $start + 1; $i -lt $Lines.Count; $i++) { if ($Lines[$i].TrimStart().StartsWith('[')) { $end = $i; break } }
    for ($i = $start + 1; $i -lt $end; $i++) {
        $eq = $Lines[$i].IndexOf('=')
        if ($eq -gt 0 -and $Lines[$i].Substring(0, $eq).Trim() -ieq $Key) {
            if ($null -eq $Value) { $Lines.RemoveAt($i) } else { $Lines[$i] = "$Key=$Value" }
            return
        }
    }
    if ($null -ne $Value) {
        $at = $end
        while ($at -gt $start + 1 -and -not $Lines[$at - 1].Trim()) { $at-- }
        $Lines.Insert($at, "$Key=$Value")
    }
}

function Get-IniValue($Lines, [string]$Section, [string]$Key) {
    $in = $false
    foreach ($l in $Lines) {
        $t = $l.Trim()
        if ($t.StartsWith('[')) { $in = $t -ieq "[$Section]"; continue }
        $eq = $l.IndexOf('=')
        if ($in -and $eq -gt 0 -and $l.Substring(0, $eq).Trim() -ieq $Key) { return $l.Substring($eq + 1) }
    }
    return $null
}

# desktop.ini is Hidden+System; writing needs the attributes off for a moment. Returns a backup record.
function Write-DesktopIni([string]$Path, $Lines, $Backups) {
    $exists = Test-Path -LiteralPath $Path
    if (-not $Backups.ContainsKey($Path)) {
        $Backups[$Path] = if ($exists) { [IO.File]::ReadAllBytes($Path) } else { $null }
    }
    if ($exists) { (Get-Item -LiteralPath $Path -Force).Attributes = 'Normal' }
    [IO.File]::WriteAllLines($Path, [string[]]$Lines, [Text.Encoding]::Unicode)
    (Get-Item -LiteralPath $Path -Force).Attributes = 'Hidden, System'
}

# The shell caches display names; tell it (and Explorer) which folders changed.
function Send-SendToChanged($IniPaths) {
    $App.SendToCache.Clear()
    foreach ($p in @($IniPaths)) { try { [CME.Native]::NotifyFolderChanged((Split-Path -Parent $p)) } catch {} }
}

# Restores desktop.ini files from Write-DesktopIni backups (a $null backup means it didn't exist).
function Restore-DesktopIni($Backups) {
    foreach ($p in @($Backups.Keys)) {
        if (Test-Path -LiteralPath $p) { (Get-Item -LiteralPath $p -Force).Attributes = 'Normal' }
        if ($null -eq $Backups[$p]) { Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue; continue }
        [IO.File]::WriteAllBytes($p, $Backups[$p])
        (Get-Item -LiteralPath $p -Force).Attributes = 'Hidden, System'
    }
    Send-SendToChanged $Backups.Keys
}

# Gives each Send to item in $Order a display name that sorts in that order. Files go through the
# containing folder's [LocalizedFileNames]; submenu folders through their own LocalizedResourceName.
# The original value is kept in [CMEOriginalNames] so the order can be reset.
function Set-SendToOrder($Row, [object[]]$Order) {
    $backups = @{}
    $n = $Order.Count
    for ($i = 0; $i -lt $n; $i++) {
        $e = $Order[$i].Entry
        $name = ($SortMark * ($n - 1 - $i)) + $e.Name
        if ($e.Submenu) {
            $ini = Join-Path $e.FilePath 'desktop.ini'
            $lines = Read-IniLines $ini
            if ((Get-IniValue $lines '.ShellClassInfo' 'LocalizedResourceName') -eq $name) { continue }
            if ($null -eq (Get-IniValue $lines 'CMEOriginalNames' 'LocalizedResourceName')) {
                $orig = Get-IniValue $lines '.ShellClassInfo' 'LocalizedResourceName'
                Set-IniValue $lines 'CMEOriginalNames' 'LocalizedResourceName' $(if ($null -eq $orig) { '' } else { $orig })
            }
            Set-IniValue $lines '.ShellClassInfo' 'LocalizedResourceName' $name
            Write-DesktopIni $ini $lines $backups
            # Explorer reads desktop.ini only for read-only or system folders.
            $dir = Get-Item -LiteralPath $e.FilePath -Force
            $dir.Attributes = $dir.Attributes -bor [IO.FileAttributes]::ReadOnly
        } else {
            $file = Split-Path -Leaf $e.FilePath
            $ini = Join-Path (Split-Path -Parent $e.FilePath) 'desktop.ini'
            $lines = Read-IniLines $ini
            if ((Get-IniValue $lines 'LocalizedFileNames' $file) -eq $name) { continue }
            if ($null -eq (Get-IniValue $lines 'CMEOriginalNames' $file)) {
                $orig = Get-IniValue $lines 'LocalizedFileNames' $file
                Set-IniValue $lines 'CMEOriginalNames' $file $(if ($null -eq $orig) { '' } else { $orig })
            }
            Set-IniValue $lines 'LocalizedFileNames' $file $name
            Write-DesktopIni $ini $lines $backups
        }
    }
    Send-SendToChanged $backups.Keys
    return @{ Label = "moved $($Row.Entry.Name)"; Undo = @{ Type = 'desktopini'; Backups = $backups; Label = "moving $($Row.Entry.Name)" } }
}

# Puts back the display names Set-SendToOrder replaced, for every item in a Send to folder.
function Reset-SendToOrder([string]$Folder) {
    $backups = @{}
    $targets = @(Join-Path $Folder 'desktop.ini') + @(Get-ChildItem -LiteralPath $Folder -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object { Join-Path $_.FullName 'desktop.ini' })
    foreach ($ini in $targets) {
        $lines = Read-IniLines $ini
        $start = -1
        for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i].Trim() -ieq '[CMEOriginalNames]') { $start = $i; break } }
        if ($start -lt 0) { continue }
        $pairs = [ordered]@{}
        for ($i = $start + 1; $i -lt $lines.Count -and -not $lines[$i].TrimStart().StartsWith('['); $i++) {
            $eq = $lines[$i].IndexOf('=')
            if ($eq -gt 0) { $pairs[$lines[$i].Substring(0, $eq)] = $lines[$i].Substring($eq + 1) }
        }
        foreach ($k in $pairs.Keys) {
            $section = if ($k -eq 'LocalizedResourceName') { '.ShellClassInfo' } else { 'LocalizedFileNames' }
            Set-IniValue $lines $section $k $(if ($pairs[$k]) { $pairs[$k] } else { $null })
        }
        # Lines above may have moved; find the section again before removing it.
        for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i].Trim() -ieq '[CMEOriginalNames]') { $start = $i; break } }
        $end = $start + 1
        while ($end -lt $lines.Count -and -not $lines[$end].TrimStart().StartsWith('[')) { $end++ }
        while ($start -gt 0 -and -not $lines[$start - 1].Trim()) { $start-- }   # and the blank line before it
        $lines.RemoveRange($start, $end - $start)
        Write-DesktopIni $ini $lines $backups
    }
    Send-SendToChanged $backups.Keys
    if (-not $backups.Count) { return $null }
    return @{ Type = 'desktopini'; Backups = $backups; Label = 'resetting the Send to order' }
}
