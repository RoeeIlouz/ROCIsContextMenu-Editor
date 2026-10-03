# ------------------------------------------------------------------------------
# "Add to Send to": turns an existing right-click entry into a Send To shortcut that runs the same thing.
#   - Commands whose file argument comes last ("app.exe -x "%1"") become a plain shortcut to app.exe -x;
#     Send To appends the selected paths, which is what %1 would have been.
#   - Windows 11 menu items (IExplorerCommand COM handlers, e.g. Blip) have no command line, so the
#     shortcut points at a tiny bridge program that invokes the same handler on the files, as Explorer does.
#     The bridge is compiled from the C# below on first use (Windows PowerShell's Add-Type can emit an
#     .exe; PowerShell 7's cannot) into %LOCALAPPDATA%\ContextMenuEditor, so shortcuts keep working if
#     this editor's folder moves.
# ------------------------------------------------------------------------------

function Get-BridgeDir { return Join-Path $env:LOCALAPPDATA 'ContextMenuEditor' }

# Builds CmeSendTo.exe if it is missing or older than the source above. Returns its path.
function Install-SendToBridge {
    $dir = Get-BridgeDir
    $exe = Join-Path $dir 'CmeSendTo.exe'
    $stamp = Join-Path $dir 'CmeSendTo.version'
    $sha = [Security.Cryptography.SHA256]::Create()
    $hash = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($BridgeSource))).Replace('-', '')
    if ((Test-Path -LiteralPath $exe) -and (Test-Path -LiteralPath $stamp) -and ([IO.File]::ReadAllText($stamp).Trim() -eq $hash)) { return $exe }

    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $src = Join-Path $dir 'CmeSendTo.cs'
    [IO.File]::WriteAllText($src, $BridgeSource, [Text.UTF8Encoding]::new($false))
    $build = "Add-Type -TypeDefinition ([IO.File]::ReadAllText('$($src.Replace("'", "''"))')) -OutputAssembly '$($exe.Replace("'", "''"))' -OutputType WindowsApplication"
    $psi = [Diagnostics.ProcessStartInfo]::new("$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe")
    $psi.Arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand ' + [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($build))
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardError = $true
    # A PowerShell 7 parent leaks its module path into the child, which breaks Windows PowerShell's own modules.
    $psi.EnvironmentVariables['PSModulePath'] = "$env:ProgramFiles\WindowsPowerShell\Modules;$env:SystemRoot\System32\WindowsPowerShell\v1.0\Modules"
    $p = [Diagnostics.Process]::Start($psi)
    $err = $p.StandardError.ReadToEnd()
    $p.WaitForExit()
    if ($p.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $exe)) { throw "Could not build the Send To bridge. $err" }
    [IO.File]::WriteAllText($stamp, $hash)
    return $exe
}

# Lists what a Windows 11 menu handler offers for a file: @{ Title; Index; Flags; State } per top-level subcommand,
# or a single entry for the handler itself when it has no submenu.
function Get-ExplorerCommandItems([string]$Clsid) {
    $exe = Install-SendToBridge
    $sample = Join-Path $env:TEMP 'Document.txt'
    if (-not (Test-Path -LiteralPath $sample)) { [IO.File]::WriteAllText($sample, '') }
    $out = Join-Path $env:TEMP "cme-probe-$([guid]::NewGuid().ToString('N')).txt"
    try {
        $p = Start-Process -FilePath $exe -ArgumentList @('--probe', $Clsid, "`"$out`"", "`"$sample`"") -PassThru -Wait -WindowStyle Hidden
        if (-not (Test-Path -LiteralPath $out)) { throw 'The menu handler could not be loaded.' }
        $lines = [IO.File]::ReadAllLines($out, [Text.Encoding]::UTF8)
    } finally { Remove-Item -LiteralPath $out -Force -ErrorAction SilentlyContinue }

    $top = [regex]::Match($lines[0], '^title=(.*)\|flags=(\d+)\|state=(\d+)$')
    $items = foreach ($l in $lines) {
        $m = [regex]::Match($l, '^  \[(\d+)\] {3}title=(.*)\|flags=(\d+)\|state=(\d+)$')
        if ($m.Success) { @{ Index = [int]$m.Groups[1].Value; Title = $m.Groups[2].Value; Flags = [int]$m.Groups[3].Value; State = [int]$m.Groups[4].Value } }
    }
    return @{ Title = $top.Groups[1].Value; Flags = [int]$top.Groups[2].Value; Subs = @($items) }
}

# "app.exe" -x "%1"  ->  @{ Target = app.exe; Arguments = -x }, or $null when the file argument isn't last.
function ConvertTo-SendToCommand([string]$Command) {
    if (-not $Command) { return $null }
    $m = [regex]::Match($Command.Trim(), '^(?<pre>.*?)\s*"?%[1LlVv*]"?$')
    if (-not $m.Success) { return $null }
    $pre = $m.Groups['pre'].Value.Trim()
    if (-not $pre -or $pre -match '%[1LlVvWw*]') { return $null }
    $exe = Get-ExeFromCommand $pre
    $rest = if ($pre.StartsWith('"')) { $pre.Substring([Math]::Min($pre.Length, $exe.Length + 2)) } else { $pre.Substring($exe.Length) }
    return @{ Target = [Environment]::ExpandEnvironmentVariables($exe); Arguments = $rest.Trim() }
}

function Test-CanSendTo($Item) {
    if ($Item.Kind -eq 'Modern') { return $true }
    if ($Item.Kind -ne 'Command') { return $false }
    if ($Item.Submenu) { return [bool]($App.Items | Where-Object { $_.ParentPath -eq $Item.SubPath -and (ConvertTo-SendToCommand $_.Command) }) }
    return [bool](ConvertTo-SendToCommand $Item.Command)
}

# Windows only reads .ico/.exe/.dll icons for shortcuts; packaged apps ship PNG logos, so wrap the PNG in an
# .ico (Vista+ icons may contain PNG data as-is).
function ConvertTo-IcoFile([string]$Png, [string]$Ico) {
    $bytes = [IO.File]::ReadAllBytes($Png)
    if ($bytes.Length -lt 24 -or $bytes[0] -ne 0x89 -or $bytes[1] -ne 0x50) { return $false }
    $w = ([int]$bytes[16] -shl 24) -bor ([int]$bytes[17] -shl 16) -bor ([int]$bytes[18] -shl 8) -bor [int]$bytes[19]
    $h = ([int]$bytes[20] -shl 24) -bor ([int]$bytes[21] -shl 16) -bor ([int]$bytes[22] -shl 8) -bor [int]$bytes[23]
    $ms = [IO.MemoryStream]::new()
    $bw = [IO.BinaryWriter]::new($ms)
    $bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]1)
    $bw.Write([byte]$(if ($w -ge 256) { 0 } else { $w })); $bw.Write([byte]$(if ($h -ge 256) { 0 } else { $h }))
    $bw.Write([byte]0); $bw.Write([byte]0); $bw.Write([uint16]1); $bw.Write([uint16]32)
    $bw.Write([uint32]$bytes.Length); $bw.Write([uint32]22); $bw.Write($bytes)
    $bw.Flush()
    [IO.File]::WriteAllBytes($Ico, $ms.ToArray())
    return $true
}

# What "Add to Send to" can create for an entry: a list of @{ Name; Target; Arguments; Icon; Description }.
# Throws with a readable reason when the entry can't work from Send To.
function Get-SendToOptions($Item) {
    $opts = [System.Collections.Generic.List[object]]::new()
    if ($Item.Kind -eq 'Command') {
        $sources = if ($Item.Submenu) { @($App.Items | Where-Object { $_.ParentPath -eq $Item.SubPath } | Sort-Object Name) } else { @($Item) }
        foreach ($s in $sources) {
            $c = ConvertTo-SendToCommand $s.Command
            if (-not $c) { continue }
            $name = if ($s.ParentName) { "$($s.ParentName) - $($s.Name)" } else { $s.Name }
            $icon = if ($s.IconValue) { $s.IconValue } elseif ($Item.IconValue) { $Item.IconValue } else { "$($c.Target),0" }
            $opts.Add(@{ Name = $name; Target = $c.Target; Arguments = $c.Arguments; Icon = $icon; Description = "$name (from the right-click menu)"
                         Group = $(if ($Item.Submenu) { $Item.Name } else { '' }); Short = $s.Name
                         GroupIcon = $(if ($Item.IconValue) { $Item.IconValue } else { $icon }) })
        }
        if (-not $opts.Count) {
            throw 'Send To adds the selected files to the end of the command, but this command needs the file somewhere else (or takes no file), so it would not work the same way.'
        }
        return , $opts.ToArray()
    }
    if ($Item.Kind -ne 'Modern') { throw 'Only commands and Windows 11 menu items can be added to Send To.' }

    $exe = Install-SendToBridge
    $probe = Get-ExplorerCommandItems $Item.Clsid
    $icon = ''
    if ($Item.IconSpec -and $Item.IconSpec -match '\.png$' -and (Test-Path -LiteralPath $Item.IconSpec)) {
        $iconDir = Join-Path (Get-BridgeDir) 'icons'
        if (-not (Test-Path -LiteralPath $iconDir)) { New-Item -ItemType Directory -Path $iconDir -Force | Out-Null }
        $ico = Join-Path $iconDir (($Item.Name -replace '[\\/:*?"<>|]', '_') + '.ico')
        if (ConvertTo-IcoFile $Item.IconSpec $ico) { $icon = "$ico,0" }
    }
    $appName = if ($probe.Title) { $probe.Title } else { $Item.Name }
    # Subcommand flags: 0x1 has its own submenu, 0x8 separator; state 0x2 hidden.
    $subs = @($probe.Subs | Where-Object { -not ($_.Flags -band 0x8) -and -not ($_.Flags -band 0x1) -and -not ($_.State -band 0x2) -and $_.Title })
    if ($probe.Flags -band 0x1) {
        if (-not $subs) { throw "$appName shows nothing for files right now, so there is nothing to add." }
        foreach ($s in $subs) {
            $title = $s.Title.TrimEnd('.').Trim()
            $route = "$($s.Index):$($s.Title)".Replace('"', "'")
            $opts.Add(@{ Name = "$appName - $title"; Target = $exe; Arguments = "$($Item.Clsid) --sub `"$route`""; Icon = $icon
                         Description = "$appName > $($s.Title) (Windows 11 menu command)"; Group = $appName; Short = $title; GroupIcon = $icon })
        }
    } else {
        $opts.Add(@{ Name = $appName; Target = $exe; Arguments = $Item.Clsid; Icon = $icon; Description = "$appName (Windows 11 menu command)"; Group = ''; Short = $appName })
    }
    return , $opts.ToArray()
}

# A subfolder of Send To shows as a submenu. Creates it if needed, with the app's icon via desktop.ini
# (Windows only reads desktop.ini in folders marked read-only or system). Returns @{ Path; Created }.
function Initialize-SendToFolder([string]$Name, [string]$Icon) {
    $path = Join-Path (Get-SendToDir) ($Name -replace '[\\/:*?"<>|]', '_')
    if (Test-Path -LiteralPath $path -PathType Container) { return @{ Path = $path; Created = $false } }
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    if ($Icon) {
        $res = [Environment]::ExpandEnvironmentVariables($Icon)
        if ($res -notmatch ',\s*-?\d+$') { $res = "$res,0" }
        $ini = Join-Path $path 'desktop.ini'
        [IO.File]::WriteAllText($ini, "[.ShellClassInfo]`r`nIconResource=$res`r`n", [Text.Encoding]::Unicode)
        (Get-Item -LiteralPath $ini -Force).Attributes = 'Hidden, System'
        $dir = Get-Item -LiteralPath $path -Force
        $dir.Attributes = $dir.Attributes -bor [IO.FileAttributes]::ReadOnly
    }
    return @{ Path = $path; Created = $true }
}

# Puts a Send To shortcut for $Option in place, inside its submenu folder when $Grouped.
# An identical shortcut elsewhere in Send To (say a flat "Blip - Laptop" from before) is moved instead of duplicated.
# Returns @{ Action = 'created' | 'moved' | 'exists'; Path; From }.
function New-SendToShortcut($Option, [switch]$Grouped) {
    $root = Get-SendToDir
    $useGroup = $Grouped -and $Option.Group
    $dir = if ($useGroup) { (Initialize-SendToFolder $Option.Group $Option.GroupIcon).Path } else { $root }
    $name = $(if ($useGroup) { $Option.Short } else { $Option.Name }) -replace '[\\/:*?"<>|]', '_'

    $candidates = @(Get-ChildItem -LiteralPath $root -Filter *.lnk -Force -ErrorAction SilentlyContinue) +
                  @(Get-ChildItem -LiteralPath $root -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object { Get-ChildItem -LiteralPath $_.FullName -Filter *.lnk -Force -ErrorAction SilentlyContinue })
    foreach ($f in $candidates) {
        $sc = $null
        try { $sc = (Get-Wsh).CreateShortcut($f.FullName) } catch {}
        if (-not $sc -or $sc.TargetPath -ne $Option.Target -or $sc.Arguments -ne $Option.Arguments) { continue }
        if ($f.DirectoryName -eq $dir) { return @{ Action = 'exists'; Path = $f.FullName } }
        $to = Join-Path $dir "$name.lnk"
        $i = 2
        while (Test-Path -LiteralPath $to) { $to = Join-Path $dir "$name ($i).lnk"; $i++ }
        Move-Item -LiteralPath $f.FullName -Destination $to
        return @{ Action = 'moved'; Path = $to; From = $f.FullName }
    }

    $path = Join-Path $dir "$name.lnk"
    $i = 2
    while (Test-Path -LiteralPath $path) { $path = Join-Path $dir "$name ($i).lnk"; $i++ }
    $sc = (Get-Wsh).CreateShortcut($path)
    $sc.TargetPath = $Option.Target
    $sc.Arguments = $Option.Arguments
    $sc.Description = $Option.Description
    if ($Option.Icon) { $sc.IconLocation = [Environment]::ExpandEnvironmentVariables($Option.Icon) }
    $sc.Save()
    return @{ Action = 'created'; Path = $path }
}

function Invoke-Scan {
    $App.Classic = Test-ClassicMenu
    $items = [System.Collections.Generic.List[object]]::new()
    $blocked = Get-BlockedClsids

    $bases = [ordered]@{}
    foreach ($b in $BaseKeys.Keys) { $bases[$b] = $BaseKeys[$b] }
    $ft = Get-FileTypeBases $App.Ext
    foreach ($b in $ft.Keys) { if (-not $bases.Contains($b)) { $bases[$b] = @{ Label = $ft[$b]; Locs = @('filetypes') } } }

    $handlers = [ordered]@{}
    foreach ($b in $bases.Keys) {
        foreach ($hive in 'HKCU', 'HKLM') {
            Read-Verbs $hive $b $bases[$b] $items
            Read-Handlers $hive $b $bases[$b] $handlers
        }
    }

    foreach ($h in $handlers.Values) {
        $bl = if ($blocked.ContainsKey($h.Clsid)) { $blocked[$h.Clsid] } else { @{} }
        $h.LocIds = $h.LocIdList.ToArray()
        $h.LocLabel = $h.LabelList -join ', '
        $h.Paths = $h.PathList.ToArray()
        $h.SubPath = $h.PathList[0]
        $h.DashPaths = $h.DashList.ToArray()
        $h.BlockedNames = $bl
        $h.Enabled = ($bl.Count -eq 0) -and ($h.DashList.Count -eq 0)
        foreach ($k in 'LocIdList', 'LabelList', 'PathList', 'DashList') { $h.Remove($k) }
        $items.Add((Complete-Entry $h))
    }

    $ext = '.' + $App.Ext.Trim().TrimStart('.').ToLowerInvariant()
    foreach ($r in (Get-PackagedRecords)) {
        $locs = [System.Collections.Generic.List[string]]::new()
        $labels = [System.Collections.Generic.List[string]]::new()
        $exts = [System.Collections.Generic.List[string]]::new()
        foreach ($t in $r.Types) {
            switch ($t) {
                '*'                    { $locs.Add('files'); $labels.Add('Files') }
                'Directory'            { $locs.Add('folders'); $labels.Add('Folders') }
                'Directory\Background' { $locs.Add('background'); $locs.Add('desktop'); $labels.Add('Background') }
                'Drive'                { $locs.Add('drives'); $labels.Add('Drives') }
                default                { if ($t.StartsWith('.')) { $exts.Add($t.ToLowerInvariant()) } }
            }
        }
        if ($exts.Count -gt 0) {
            $labels.Add($(if ($exts.Count -le 3) { $exts -join ', ' } else { "$($exts.Count) file types" }))
            if ($exts.Contains($ext)) { $locs.Add('filetypes') }
        }
        $bl = if ($blocked.ContainsKey($r.Clsid)) { $blocked[$r.Clsid] } else { @{} }
        $verb = Format-Identifier $r.VerbId
        $items.Add((Complete-Entry @{
            Id = "pkg|$($r.Clsid)"; Kind = 'Modern'; Name = $r.App; Sub = $verb; KeyName = $r.VerbId; Hive = 'Package'
            Clsid = $r.Clsid; Package = $r.Package; IconSpec = $r.Logo; LocIds = $locs.ToArray()
            LocLabel = (($labels | Select-Object -Unique) -join ', '); BlockedNames = $bl; Enabled = $bl.Count -eq 0
        }))
    }

    Read-ShellNew $items
    Read-SendTo $items
    $App.Items = $items
}
