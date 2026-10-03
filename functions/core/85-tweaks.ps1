# ------------------------------------------------------------------------------
# Tweaks (config\tweaks.json): each tweak has registry entries
# ({ Path, Name, Type, Value, OriginalValue }) and/or InvokeScript / UndoScript lines.
# Applying writes Value, undoing writes OriginalValue; "<RemoveEntry>" deletes the value.
# Also: DetectScript (is it applied?), UnavailableScript (returns a reason
# when it can't apply on this PC) and RestartExplorer (changes show after an Explorer restart).
# ------------------------------------------------------------------------------
function Get-TweakDefinitions {
    $list = [System.Collections.Generic.List[object]]::new()
    if (-not $Config['tweaks']) { return }
    foreach ($p in $Config['tweaks'].PSObject.Properties) {
        $t = $p.Value
        $list.Add([pscustomobject]@{
            Id = $p.Name; Content = [string]$t.Content; Description = [string]$t.Description
            Category = [string]$t.category; IsToggle = [string]$t.Type -eq 'Toggle'; RestartExplorer = [bool]$t.RestartExplorer
            Registry = @($t.registry | Where-Object { $_ }); InvokeScript = @($t.InvokeScript | Where-Object { $_ })
            UndoScript = @($t.UndoScript | Where-Object { $_ }); DetectScript = [string]$t.DetectScript
            UnavailableScript = [string]$t.UnavailableScript
        })
    }
    return $list.ToArray()   # plain array: callers pipe it into Where-Object
}

function Get-TweakPresets {
    $h = [ordered]@{}
    if ($Config['preset']) { foreach ($p in $Config['preset'].PSObject.Properties) { $h[$p.Name] = @($p.Value) } }
    return $h
}

# "HKCU:\Software\..." -> @{ Hive; SubPath }
function Split-TweakPath([string]$Path) {
    $m = [regex]::Match($Path, '^(HKCU|HKLM|HKEY_CURRENT_USER|HKEY_LOCAL_MACHINE):?\\(.+)$')
    if (-not $m.Success) { throw "Unsupported registry path in tweak: $Path" }
    $hive = if ($m.Groups[1].Value -like 'HKLM*' -or $m.Groups[1].Value -like 'HKEY_LOCAL*') { 'HKLM' } else { 'HKCU' }
    return @{ Hive = $hive; SubPath = $m.Groups[2].Value }
}

function Get-TweakValueName([string]$Name) { if ($Name -eq '(default)') { return '' } return $Name }

function Set-TweakRegistryValue($Entry, [string]$Value) {
    $p = Split-TweakPath $Entry.Path
    $name = Get-TweakValueName $Entry.Name
    $root = Get-HiveRoot $p.Hive
    if ($Value -eq '<RemoveEntry>') {
        $k = $root.OpenSubKey($p.SubPath, $true)
        if ($k) { try { $k.DeleteValue($name, $false) } finally { $k.Close() } }
        return
    }
    $k = $root.CreateSubKey($p.SubPath)
    try {
        switch ([string]$Entry.Type) {
            'DWord'        { $k.SetValue($name, [int]$Value, [Microsoft.Win32.RegistryValueKind]::DWord) }
            'QWord'        { $k.SetValue($name, [long]$Value, [Microsoft.Win32.RegistryValueKind]::QWord) }
            'ExpandString' { $k.SetValue($name, $Value, [Microsoft.Win32.RegistryValueKind]::ExpandString) }
            default        { $k.SetValue($name, $Value, [Microsoft.Win32.RegistryValueKind]::String) }
        }
    } finally { $k.Close() }
}

function Test-TweakRegistryValue($Entry) {
    $p = Split-TweakPath $Entry.Path
    $k = (Get-HiveRoot $p.Hive).OpenSubKey($p.SubPath)
    $name = Get-TweakValueName $Entry.Name
    $present = $k -and ($k.GetValueNames() -contains $name)
    try {
        if ([string]$Entry.Value -eq '<RemoveEntry>') { return -not $present }
        if (-not $present) { return $false }
        return [string]$k.GetValue($name, $null, 'DoNotExpandEnvironmentNames') -eq [string]$Entry.Value
    } finally { if ($k) { $k.Close() } }
}

function Invoke-TweakScript([string]$Code) {
    if (-not $Code) { return $null }
    return & ([scriptblock]::Create($Code))
}

# @{ Applied; Available; Note } for one tweak definition.
function Get-TweakState($Tweak) {
    $reason = [string](Invoke-TweakScript $Tweak.UnavailableScript)
    $applied = $false
    try {
        if ($Tweak.DetectScript) { $applied = [bool](Invoke-TweakScript $Tweak.DetectScript) }
        elseif ($Tweak.Registry.Count) { $applied = -not ($Tweak.Registry | Where-Object { -not (Test-TweakRegistryValue $_) }) }
    } catch { $applied = $false }
    return @{ Applied = $applied; Available = -not $reason; Note = $reason }
}

function Test-TweakNeedsAdmin($Tweak) {
    return [bool]($Tweak.Registry | Where-Object { (Split-TweakPath $_.Path).Hive -eq 'HKLM' })
}

# Applies (or with -Undo, reverts) one tweak.
function Invoke-Tweak($Tweak, [switch]$Undo) {
    foreach ($e in $Tweak.Registry) {
        Set-TweakRegistryValue $e $(if ($Undo) { [string]$e.OriginalValue } else { [string]$e.Value })
    }
    foreach ($s in $(if ($Undo) { $Tweak.UndoScript } else { $Tweak.InvokeScript })) { [void](Invoke-TweakScript $s) }
}
