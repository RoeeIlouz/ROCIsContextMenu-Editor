# ==============================================================================
# REGISTRY HELPERS
# ==============================================================================
function Get-HiveRoot([string]$Hive) {
    if ($Hive -eq 'HKLM') { return [Microsoft.Win32.Registry]::LocalMachine }
    return [Microsoft.Win32.Registry]::CurrentUser
}

function Copy-RegTree($Source, $Target) {
    foreach ($n in $Source.GetValueNames()) {
        $Target.SetValue($n, $Source.GetValue($n, $null, 'DoNotExpandEnvironmentNames'), $Source.GetValueKind($n))
    }
    foreach ($sub in $Source.GetSubKeyNames()) {
        $src = $Source.OpenSubKey($sub)
        $dst = $Target.CreateSubKey($sub)
        try { Copy-RegTree $src $dst } finally { $src.Close(); $dst.Close() }
    }
}

function Set-RegString($Key, [string]$Name, [string]$Value) {
    $kind = if ($Value -match '%[A-Za-z_][A-Za-z0-9_]*%') { 'ExpandString' } else { 'String' }
    $Key.SetValue($Name, $Value, [Microsoft.Win32.RegistryValueKind]$kind)
}

function Get-ClsidInfo([string]$Clsid) {
    if ($App.ClsidCache.ContainsKey($Clsid)) { return $App.ClsidCache[$Clsid] }
    $info = @{ Name = ''; Dll = ''; Registered = $true }
    try {
        $hkcr = [Microsoft.Win32.Registry]::ClassesRoot
        $k = $hkcr.OpenSubKey("CLSID\$Clsid")
        if (-not $k) {
            # Packaged COM and 32-bit-only registrations live elsewhere; only a CLSID found nowhere counts as unregistered.
            $alt = $hkcr.OpenSubKey("PackagedCom\ClassIndex\$Clsid")
            if (-not $alt) { $alt = $hkcr.OpenSubKey("WOW6432Node\CLSID\$Clsid") }
            if ($alt) { $alt.Close() } else { $info.Registered = $false }
        }
        if ($k) {
            $info.Name = Resolve-MenuText ([string]$k.GetValue(''))
            $ik = $k.OpenSubKey('InprocServer32')
            if ($ik) {
                $info.Dll = [Environment]::ExpandEnvironmentVariables([string]$ik.GetValue('')).Trim('"')
                $ik.Close()
            }
            $k.Close()
        }
    } catch {}
    $App.ClsidCache[$Clsid] = $info
    return $info
}

function Get-BlockedClsids {
    $res = @{}
    foreach ($hive in 'HKCU', 'HKLM') {
        $k = (Get-HiveRoot $hive).OpenSubKey($BlockedPath)
        if (-not $k) { continue }
        foreach ($n in $k.GetValueNames()) {
            $c = ConvertTo-Clsid $n
            if (-not $c) { continue }
            if (-not $res.ContainsKey($c)) { $res[$c] = @{} }
            $res[$c][$hive] = $n
        }
        $k.Close()
    }
    return $res
}

function Get-FileTypeBases([string]$Ext) {
    $ext = '.' + $Ext.Trim().TrimStart('.').ToLowerInvariant()
    $bases = [ordered]@{}
    $bases["SystemFileAssociations\$ext"] = "$ext files"
    $k = [Microsoft.Win32.Registry]::ClassesRoot.OpenSubKey($ext)
    if ($k) {
        $prog = [string]$k.GetValue('')
        $perceived = [string]$k.GetValue('PerceivedType')
        $k.Close()
        if ($prog) { $bases[$prog] = "$ext ($prog)" }
        if ($perceived) { $bases["SystemFileAssociations\$perceived"] = "All $perceived files" }
    }
    $uc = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey("Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\$ext\UserChoice")
    if ($uc) {
        $p = [string]$uc.GetValue('ProgId')
        $uc.Close()
        if ($p -and -not $bases.Contains($p)) { $bases[$p] = "$ext (default app)" }
    }
    return $bases
}
