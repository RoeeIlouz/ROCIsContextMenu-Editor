# ==============================================================================
# ICONS
# ==============================================================================
function Resolve-ExecutablePath([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    $p = [Environment]::ExpandEnvironmentVariables($Path.Trim().Trim('"'))
    if ($App.PathCache.ContainsKey($p)) { return $App.PathCache[$p] }

    $found = $null
    try {
        if ([IO.Path]::IsPathRooted($p)) {
            if ([IO.File]::Exists($p)) { $found = $p }
        } else {
            $names = @($p)
            if (-not [IO.Path]::HasExtension($p)) { $names += "$p.exe" }
            $dirs = @("$env:SystemRoot\System32", $env:SystemRoot) + ($env:PATH -split ';' | Where-Object { $_ })
            :outer foreach ($n in $names) {
                foreach ($d in $dirs) {
                    $c = Join-Path $d $n
                    if ([IO.File]::Exists($c)) { $found = $c; break outer }
                }
                foreach ($root in [Microsoft.Win32.Registry]::CurrentUser, [Microsoft.Win32.Registry]::LocalMachine) {
                    $k = $root.OpenSubKey("Software\Microsoft\Windows\CurrentVersion\App Paths\$n")
                    if ($k) {
                        $v = [string]$k.GetValue('')
                        $k.Close()
                        if ($v) {
                            $v = [Environment]::ExpandEnvironmentVariables($v.Trim('"'))
                            if ([IO.File]::Exists($v)) { $found = $v; break outer }
                        }
                    }
                }
            }
        }
    } catch {}
    $App.PathCache[$p] = $found
    return $found
}

function Get-ExeFromCommand([string]$Command) {
    if ([string]::IsNullOrWhiteSpace($Command)) { return '' }
    $c = $Command.Trim()
    if ($c.StartsWith('"')) {
        $end = $c.IndexOf('"', 1)
        if ($end -gt 1) { return $c.Substring(1, $end - 1) }
    }
    $m = [regex]::Match($c, '^(.+?\.(?:exe|com|bat|cmd))(?:\s|$)', 'IgnoreCase')
    if ($m.Success) { return $m.Groups[1].Value }
    return ($c -split '\s+')[0]
}

function Get-IconImage([string]$Spec) {
    if ([string]::IsNullOrWhiteSpace($Spec)) { return $null }
    if ($App.IconCache.ContainsKey($Spec)) { return $App.IconCache[$Spec] }

    $img = $null
    # "shell:<file>" and "ext:<.ext>" ask the shell for the icon Explorer itself shows
    if ($Spec -match '^(shell|ext):(.+)$') {
        $hIcon = [IntPtr]::Zero
        try {
            $hIcon = if ($Matches[1] -eq 'ext') { [CME.Native]::FileIcon("x$($Matches[2])", $true) } else { [CME.Native]::FileIcon($Matches[2], $false) }
            if ($hIcon -ne [IntPtr]::Zero) {
                $img = [System.Windows.Interop.Imaging]::CreateBitmapSourceFromHIcon(
                    $hIcon, [System.Windows.Int32Rect]::Empty, [System.Windows.Media.Imaging.BitmapSizeOptions]::FromEmptyOptions())
                $img.Freeze()
            }
        } catch { $img = $null }
        finally { if ($hIcon -ne [IntPtr]::Zero) { [void][CME.Native]::DestroyIcon($hIcon) } }
        $App.IconCache[$Spec] = $img
        return $img
    }
    try {
        $s = [Environment]::ExpandEnvironmentVariables($Spec.Trim()).TrimStart('@').Trim()
        $index = 0
        $m = [regex]::Match($s, '^(.*?),\s*(-?\d+)$')
        if ($m.Success) { $s = $m.Groups[1].Value; $index = [int]$m.Groups[2].Value }
        $path = Resolve-ExecutablePath $s
        if ($path) {
            if ($path -match '\.(png|jpe?g|bmp)$') {
                $bi = [System.Windows.Media.Imaging.BitmapImage]::new()
                $bi.BeginInit()
                $bi.UriSource = [Uri]::new($path)
                $bi.DecodePixelWidth = 40
                $bi.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
                $bi.EndInit()
                $bi.Freeze()
                $img = $bi
            } else {
                $large = [IntPtr[]]::new(1)
                $n = [CME.Native]::ExtractIconEx($path, $index, $large, $null, 1)
                if ($n -gt 0 -and $n -ne [uint32]::MaxValue -and $large[0] -ne [IntPtr]::Zero) {
                    try {
                        $img = [System.Windows.Interop.Imaging]::CreateBitmapSourceFromHIcon(
                            $large[0], [System.Windows.Int32Rect]::Empty,
                            [System.Windows.Media.Imaging.BitmapSizeOptions]::FromEmptyOptions())
                        $img.Freeze()
                    } finally { [void][CME.Native]::DestroyIcon($large[0]) }
                }
            }
        }
    } catch { $img = $null }
    $App.IconCache[$Spec] = $img
    return $img
}
