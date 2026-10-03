# ==============================================================================
# SCANNER
# ==============================================================================
function Complete-Entry([hashtable]$d) {
    $defaults = @{
        Id = ''; Kind = 'Command'; Name = ''; Sub = ''; KeyName = ''; Command = ''; IconValue = ''; IconSpec = ''
        Hive = 'HKCU'; BaseKey = ''; SubPath = ''; Paths = @(); LocIds = @(); LocLabel = ''; Enabled = $true
        IsBuiltIn = $false; Extended = $false; Shield = $false; Position = ''; Clsid = ''; Dll = ''; Package = ''
        BlockedNames = @{}; DashPaths = @(); Delegate = $false; Submenu = $false; ShellPath = ''
        ParentName = ''; ParentPath = ''; Children = 0; Broken = $false; BrokenReason = ''; Editable = $true
        FilePath = ''; Target = ''; Added = $false
    }
    foreach ($k in $defaults.Keys) { if (-not $d.ContainsKey($k)) { $d[$k] = $defaults[$k] } }

    $d.IsCommand  = $d.Kind -eq 'Command'
    $d.IsChild    = [bool]$d.ParentName
    $d.KindLabel  = switch ($d.Kind) {
        'Command'   { if ($d.Submenu) { 'Submenu' } else { 'Command' } }
        'Extension' { 'Shell extension' }
        'New'       { 'New menu item' }
        'SendTo'    { if ($d.Submenu) { 'Send to submenu' } else { 'Send to item' } }
        default     { 'Windows 11 menu' }
    }
    $d.KindTag    = switch ($d.Kind) {
        'Extension' { 'Extension' }
        'Modern'    { 'Win 11' }
        'New'       { '' }
        default     { if ($d.Submenu) { 'Submenu' } elseif ($d.ParentName) { "in $($d.ParentName)" } else { '' } }
    }
    $d.ScopeShort = switch ($d.Hive) { 'HKCU' { 'You' } 'HKLM' { 'All users' } default { 'App' } }
    $d.ScopeLabel = switch ($d.Hive) { 'HKCU' { 'Current user (HKCU)' } 'HKLM' { 'All users (HKLM)' } default { 'App package' } }
    if ($d.Kind -eq 'SendTo') { $d.ScopeLabel = 'Current user (Send To folder)' }
    $d.Glyph      = switch ($d.Kind) { 'Command' { $G.App } 'New' { $G.NewFile } 'SendTo' { $G.Send } default { $G.Puzzle } }
    $d.IconImage  = Get-IconImage $d.IconSpec
    # Submenus driven by ExtendedSubCommandsKey point elsewhere in the registry; only nested "shell" ones are editable here.
    $d.CanEdit    = $d.Kind -eq 'Command' -and $d.Editable
    $d.CanDelete  = $d.Kind -eq 'Command' -or $d.Kind -eq 'SendTo' -or ($d.Kind -eq 'Extension' -and $d.Broken) -or ($d.Kind -eq 'New' -and $d.Added)
    $d.CanRegedit = $d.Kind -ne 'Modern'

    $d.SearchText = (@($d.Name, $d.Sub, $d.KeyName, $d.Command, $d.Clsid, $d.Dll, $d.Package, $d.LocLabel, $d.ParentName) -join ' ').ToLowerInvariant()
    # Children sort directly under their submenu: group by parent name, parent first
    $d.GroupKey = if ($d.ParentName) { $d.ParentName } else { $d.Name }
    $d.ChildOrder = if ($d.ParentName) { 1 } else { 0 }
    return [pscustomobject]$d
}

# Label/value rows for the detail pane. Built on demand: doing it for every entry during a scan
# roughly doubled the scan time.
function Get-EntryDetails($d) {
    $flags = @()
    if ($d.Extended) { $flags += 'Only with Shift + right-click' }
    if ($d.Shield) { $flags += 'Shows UAC shield' }
    if ($d.Position) { $flags += "Pinned to $($d.Position.ToLower())" }
    if ($d.Submenu) { $flags += $(if ($d.Children) { "Submenu with $($d.Children) command$(if ($d.Children -ne 1) { 's' })" } else { 'Opens a submenu' }) }
    if ($d.ParentName) { $flags += "Inside the `"$($d.ParentName)`" submenu" }

    $menu = if (-not $App.IsWin11) { '' }
            elseif ($d.Kind -eq 'Modern' -or $d.Kind -eq 'New') { 'Main menu' }
            elseif ($App.Classic) { 'Main menu (classic menu is on)' }
            else { 'Under "Show more options"' }
    $hiveLong = if ($d.Hive -eq 'HKLM') { 'HKLM' } else { 'HKCU' }
    $regText = if ($d.Kind -eq 'SendTo') { '' } else { (@($d.Paths) | ForEach-Object { "$hiveLong\$_" }) -join "`n" }

    $det = [System.Collections.Generic.List[object]]::new()
    foreach ($f in @(
        @('Problem', $d.BrokenReason, $false),
        @('Appears on', $d.LocLabel, $false),
        @('Installed for', $d.ScopeLabel, $false),
        @('Windows 11', $menu, $false),
        @('Command', $d.Command, $true),
        @('Target', $d.Target, $true),
        @('File', $d.FilePath, $true),
        @('Icon', $d.IconValue, $true),
        @('Options', ($flags -join "`n"), $false),
        @('Package', $d.Package, $true),
        @('CLSID', $d.Clsid, $true),
        @('Handler DLL', $d.Dll, $true),
        @('Registry', $regText, $true)
    )) {
        if ($f[1]) { $det.Add([pscustomobject]@{ Label = $f[0]; Value = [string]$f[1]; Mono = $f[2]; Warn = $f[0] -eq 'Problem' }) }
    }
    return , $det
}

# True only for an absolute local path that is gone. Bare names (wt.exe), placeholders (%1),
# UNC paths and Store app folders are never reported, to avoid false alarms.
function Test-MissingFile([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    $p = [Environment]::ExpandEnvironmentVariables($Path.Trim().Trim('"'))
    if ($p.Contains('%') -or $p.StartsWith('\') -or $p -like '*\WindowsApps\*') { return $false }
    if (-not [IO.Path]::IsPathRooted($p)) { return $false }
    if ($App.MissingCache.ContainsKey($p)) { return $App.MissingCache[$p] }
    $missing = try { -not ([IO.File]::Exists($p) -or [IO.Directory]::Exists($p)) } catch { $false }
    $App.MissingCache[$p] = $missing
    return $missing
}

function Read-Verbs([string]$Hive, [string]$Base, $Info, $Out, [string]$ShellPath = '', [string]$ParentName = '', [string]$ParentPath = '') {
    if (-not $ShellPath) { $ShellPath = "Software\Classes\$Base\shell" }
    $pk = $null
    try { $pk = (Get-HiveRoot $Hive).OpenSubKey($ShellPath) } catch {}
    if (-not $pk) { return }
    try {
        foreach ($keyName in $pk.GetSubKeyNames()) {
            $vk = $null
            try { $vk = $pk.OpenSubKey($keyName) } catch {}
            if (-not $vk) { continue }
            try {
                $cmd = ''; $delegate = $false
                $ck = $vk.OpenSubKey('command')
                if ($ck) {
                    $cmd = [string]$ck.GetValue('', '', 'DoNotExpandEnvironmentNames')
                    $delegate = $null -ne $ck.GetValue('DelegateExecute')
                    $ck.Close()
                }
                $valueNames = $vk.GetValueNames()
                $raw = [string]$vk.GetValue('MUIVerb')
                if (-not $raw) { $raw = [string]$vk.GetValue('') }
                $name = Resolve-MenuText $raw
                if (-not $name) { $name = if ($KnownVerbNames.ContainsKey($keyName)) { $KnownVerbNames[$keyName] } else { Format-Identifier $keyName } }
                if (-not $name) { $name = $keyName }

                $iconValue = [string]$vk.GetValue('Icon', '', 'DoNotExpandEnvironmentNames')
                $nestedShell = $vk.GetSubKeyNames() -contains 'shell'
                $externalSub = ($valueNames -contains 'ExtendedSubCommandsKey') -or ([string]$vk.GetValue('SubCommands'))
                $submenu = $nestedShell -or $externalSub -or ($valueNames -contains 'SubCommands')
                $exe = Get-ExeFromCommand $cmd
                $iconSpec = if ($iconValue) { $iconValue } else { $exe }

                # Standard verbs (open/edit/print...) count as built-in even per-user: they are the
                # default app's own actions, not something added to the menu.
                $builtIn = $SystemVerbs.Contains($keyName)
                if ($Hive -eq 'HKLM' -and -not $builtIn) {
                    $exePath = Resolve-ExecutablePath $exe
                    $builtIn = $keyName -like 'Windows.*' -or (-not $cmd -and -not $submenu) -or
                               ($exePath -and $exePath.StartsWith($env:SystemRoot, [StringComparison]::OrdinalIgnoreCase) -and -not $iconValue)
                }

                $brokenReason = ''
                if ($cmd -and (Test-MissingFile $exe)) { $brokenReason = "Program not found: $([Environment]::ExpandEnvironmentVariables($exe))" }

                $subPath = "$ShellPath\$keyName"
                $childCount = 0
                if ($nestedShell -and -not $ParentName) {
                    $before = $Out.Count
                    Read-Verbs $Hive $Base $Info $Out "$subPath\shell" $name $subPath
                    $childCount = $Out.Count - $before
                }

                $sub = if ($cmd) { $cmd }
                       elseif ($submenu) { if ($childCount) { "Submenu with $childCount command$(if ($childCount -ne 1) { 's' })" } else { 'Submenu' } }
                       elseif ($delegate) { 'Built-in shell handler' } else { 'No command' }

                $Out.Add((Complete-Entry @{
                    Id = "cmd|$Hive|$subPath"; Kind = 'Command'; Name = $name; Sub = $sub; KeyName = $keyName
                    Command = $cmd; IconValue = $iconValue; IconSpec = $iconSpec; Hive = $Hive; BaseKey = $Base
                    ShellPath = $ShellPath; SubPath = $subPath; Paths = @($subPath); LocIds = $Info.Locs; LocLabel = $Info.Label
                    Enabled = -not (($valueNames -contains 'LegacyDisable') -or ($valueNames -contains 'ProgrammaticAccessOnly'))
                    IsBuiltIn = $builtIn; Extended = $valueNames -contains 'Extended'; Shield = $valueNames -contains 'HasLUAShield'
                    Position = [string]$vk.GetValue('Position'); Delegate = $delegate; Submenu = $submenu
                    Editable = -not ($submenu -and -not $nestedShell -and $externalSub)
                    ParentName = $ParentName; ParentPath = $ParentPath; Children = $childCount
                    Broken = [bool]$brokenReason; BrokenReason = $brokenReason
                }))
            } catch {
            } finally { $vk.Close() }
        }
    } finally { $pk.Close() }
}

function Read-Handlers([string]$Hive, [string]$Base, $Info, $Map) {
    $hPath = "Software\Classes\$Base\shellex\ContextMenuHandlers"
    $pk = $null
    try { $pk = (Get-HiveRoot $Hive).OpenSubKey($hPath) } catch {}
    if (-not $pk) { return }
    try {
        foreach ($keyName in $pk.GetSubKeyNames()) {
            $value = ''
            try {
                $hk = $pk.OpenSubKey($keyName)
                if ($hk) { $value = [string]$hk.GetValue(''); $hk.Close() }
            } catch {}
            $clsid = ConvertTo-Clsid $value
            if (-not $clsid) { $clsid = ConvertTo-Clsid $keyName }
            if (-not $clsid) { continue }

            $mapKey = "$Hive|$clsid"
            if (-not $Map.Contains($mapKey)) {
                $ci = Get-ClsidInfo $clsid
                $keyIsGuid = [bool](ConvertTo-Clsid $keyName)
                $name = if (-not $keyIsGuid) { $keyName } elseif ($ci.Name) { $ci.Name } else { 'Unknown extension' }
                $sub = if ($ci.Name -and $ci.Name -ne $name) { $ci.Name } elseif ($ci.Dll) { [IO.Path]::GetFileName($ci.Dll) } else { $clsid }
                $brokenReason = if (-not $ci.Registered) { "Handler $clsid is not registered (its program was probably uninstalled)" }
                                elseif (Test-MissingFile $ci.Dll) { "Handler DLL not found: $($ci.Dll)" } else { '' }
                $Map[$mapKey] = @{
                    Broken = [bool]$brokenReason; BrokenReason = $brokenReason
                    Id = "ext|$mapKey"; Kind = 'Extension'; Name = $name; Sub = $sub; KeyName = $keyName; Hive = $Hive
                    Clsid = $clsid; Dll = $ci.Dll; IconSpec = $ci.Dll; BaseKey = $Base
                    IsBuiltIn = ($Hive -eq 'HKLM') -and $ci.Dll -and $ci.Dll.StartsWith($env:SystemRoot, [StringComparison]::OrdinalIgnoreCase)
                    LocIdList = [System.Collections.Generic.List[string]]::new()
                    LabelList = [System.Collections.Generic.List[string]]::new()
                    PathList  = [System.Collections.Generic.List[string]]::new()
                    DashList  = [System.Collections.Generic.List[string]]::new()
                }
            }
            $e = $Map[$mapKey]
            foreach ($l in $Info.Locs) { if (-not $e.LocIdList.Contains($l)) { $e.LocIdList.Add($l) } }
            if (-not $e.LabelList.Contains($Info.Label)) { $e.LabelList.Add($Info.Label) }
            $e.PathList.Add("$hPath\$keyName")
            if ($value.StartsWith('-')) { $e.DashList.Add("$hPath\$keyName") }
        }
    } finally { $pk.Close() }
}

function Find-PackageAsset([string]$Root, [string]$Relative) {
    if (-not $Relative) { return $null }
    $full = Join-Path $Root $Relative
    if ([IO.File]::Exists($full)) { return $full }
    $dir = [IO.Path]::GetDirectoryName($full)
    if (-not [IO.Directory]::Exists($dir)) { return $null }
    $stem = [IO.Path]::GetFileNameWithoutExtension($full)
    $ext = [IO.Path]::GetExtension($full)
    $best = $null; $bestScore = -1
    foreach ($f in [IO.Directory]::GetFiles($dir, "$stem.*$ext")) {
        $n = [IO.Path]::GetFileName($f).ToLowerInvariant()
        if ($n.Contains('contrast-')) { continue }
        $score = 0
        if ($n.Contains('targetsize-32')) { $score += 6 } elseif ($n.Contains('targetsize-48')) { $score += 5 } elseif ($n.Contains('targetsize-24')) { $score += 4 }
        if ($n.Contains('unplated')) { $score += 2 }
        if ($n.Contains('scale-200')) { $score += 1 }
        if ($score -gt $bestScore) { $best = $f; $bestScore = $score }
    }
    return $best
}

function Resolve-PackageString([string]$FullName, [string]$Text) {
    if (-not $Text) { return '' }
    if ($Text.StartsWith('@')) { return [string][CME.Native]::LoadIndirect($Text) }
    if ($Text.StartsWith('ms-resource:')) {
        $pkg = $FullName.Split('_')[0]
        $res = $Text.Substring(12)
        $uri = if ($res.StartsWith('//')) { "ms-resource:$res" }
               elseif ($res.StartsWith('/')) { "ms-resource://$pkg$res" }
               elseif ($res.Contains('/')) { "ms-resource://$pkg/$res" }
               else { "ms-resource://$pkg/Resources/$res" }
        return [string][CME.Native]::LoadIndirect("@{$FullName?$uri}")
    }
    return $Text
}

# Packaged (MSIX) context menu entries. Manifests are parsed once per session; Refresh re-reads them.
function Get-PackagedRecords {
    if ($null -ne $App.Packaged) { return $App.Packaged }
    $list = [System.Collections.Generic.List[object]]::new()
    $seen = @{}
    $repo = 'Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\Repository\Packages'
    $rk = $null
    try { $rk = [Microsoft.Win32.Registry]::ClassesRoot.OpenSubKey($repo) } catch {}
    if ($rk) {
        foreach ($full in $rk.GetSubKeyNames()) {
            try {
                $pk = $rk.OpenSubKey($full)
                $root = [string]$pk.GetValue('PackageRootFolder')
                $regName = [string]$pk.GetValue('DisplayName')
                $pk.Close()
                if (-not $root) { continue }
                $manifest = Join-Path $root 'AppxManifest.xml'
                if (-not [IO.File]::Exists($manifest)) { continue }
                $txt = [IO.File]::ReadAllText($manifest)
                if ($txt.IndexOf('fileExplorerContextMenus', [StringComparison]::OrdinalIgnoreCase) -lt 0) { continue }
                $x = [xml]$txt

                $appName = Resolve-PackageString $full $regName
                if (-not $appName) {
                    $node = $x.SelectSingleNode("//*[local-name()='Properties']/*[local-name()='DisplayName']")
                    if ($node) { $appName = Resolve-PackageString $full $node.InnerText }
                }
                if (-not $appName) { $appName = Format-Identifier (($full.Split('_')[0]) -replace '^.*\.', '') }

                $logo = $null
                $ve = $x.SelectSingleNode("//*[local-name()='VisualElements']")
                if ($ve -and $ve.GetAttribute('Square44x44Logo')) { $logo = Find-PackageAsset $root $ve.GetAttribute('Square44x44Logo') }
                if (-not $logo) {
                    $ln = $x.SelectSingleNode("//*[local-name()='Properties']/*[local-name()='Logo']")
                    if ($ln) { $logo = Find-PackageAsset $root $ln.InnerText }
                }

                $byClsid = [ordered]@{}
                foreach ($ext in $x.SelectNodes("//*[local-name()='Extension'][@Category='windows.fileExplorerContextMenus']")) {
                    foreach ($it in $ext.SelectNodes(".//*[local-name()='ItemType']")) {
                        foreach ($v in $it.SelectNodes("./*[local-name()='Verb']")) {
                            $clsid = ConvertTo-Clsid $v.GetAttribute('Clsid')
                            if (-not $clsid -or $seen.ContainsKey($clsid)) { continue }
                            if (-not $byClsid.Contains($clsid)) {
                                $byClsid[$clsid] = @{ Clsid = $clsid; VerbId = $v.GetAttribute('Id'); Types = [System.Collections.Generic.List[string]]::new() }
                            }
                            $t = $it.GetAttribute('Type')
                            if (-not $byClsid[$clsid].Types.Contains($t)) { $byClsid[$clsid].Types.Add($t) }
                        }
                    }
                }
                foreach ($r in $byClsid.Values) {
                    $seen[$r.Clsid] = $true
                    $r.App = $appName; $r.Logo = $logo; $r.Package = $full
                    $list.Add($r)
                }
            } catch {}
        }
        $rk.Close()
    }
    $App.Packaged = $list
    return $list
}
