# ------------------------------------------------------------------------------
# Presets. Every key we write carries CMEPreset=<id> so removal never touches keys we didn't create.
# ------------------------------------------------------------------------------
function Find-VSCode {
    $candidates = @("$env:LOCALAPPDATA\Programs\Microsoft VS Code\Code.exe", "$env:ProgramFiles\Microsoft VS Code\Code.exe")
    $cmd = Get-Command code.cmd -CommandType Application -ErrorAction Ignore | Select-Object -First 1
    if ($cmd) { $candidates += Join-Path (Split-Path (Split-Path $cmd.Source)) 'Code.exe' }
    foreach ($c in $candidates) { if ($c -and [IO.File]::Exists($c)) { return $c } }
    return $null
}

function Find-Pwsh {
    foreach ($c in @("$env:ProgramFiles\PowerShell\7\pwsh.exe", "$env:ProgramFiles\PowerShell\7-preview\pwsh.exe")) {
        if ([IO.File]::Exists($c)) { return $c }
    }
    # Store installs live in a versioned WindowsApps folder that changes on every update; the alias does not.
    $alias = "$env:LOCALAPPDATA\Microsoft\WindowsApps\pwsh.exe"
    if (Test-Path -LiteralPath $alias) { return $alias }
    $cmd = Get-Command pwsh.exe -CommandType Application -ErrorAction Ignore | Select-Object -First 1
    if ($cmd) { return $cmd.Source }
    return $null
}

function Get-PresetSpec([string]$Id) {
    switch ($Id) {
        'vscode' {
            $exe = Find-VSCode
            if (-not $exe) { return $null }
            return @(
                @{ Base = '*';                    Key = 'OpenWithCode'; Name = 'Open with Code'; Icon = $exe; Cmd = "`"$exe`" `"%1`"" }
                @{ Base = 'Directory';            Key = 'OpenWithCode'; Name = 'Open with Code'; Icon = $exe; Cmd = "`"$exe`" `"%V`"" }
                @{ Base = 'Directory\Background'; Key = 'OpenWithCode'; Name = 'Open with Code'; Icon = $exe; Cmd = "`"$exe`" `"%V`"" }
            )
        }
        'pwsh' {
            $exe = Find-Pwsh
            if (-not $exe) { return $null }
            # "%V\." avoids the trailing-backslash-escapes-the-quote problem on drive roots (C:\)
            return @(
                @{ Base = 'Directory';            Key = 'OpenPwshHere'; Name = 'Open PowerShell 7 here'; Icon = $exe; Cmd = "`"$exe`" -NoExit -WorkingDirectory `"%V\.`"" }
                @{ Base = 'Directory\Background'; Key = 'OpenPwshHere'; Name = 'Open PowerShell 7 here'; Icon = $exe; Cmd = "`"$exe`" -NoExit -WorkingDirectory `"%V\.`"" }
            )
        }
        'takeown' {
            # A verb named "runas" is what makes Explorer elevate it.
            return @(
                @{ Base = '*'; Key = 'runas'; Name = 'Take ownership'; Icon = 'imageres.dll,-78'; Isolated = $true
                   Extra = @{ HasLUAShield = ''; NoWorkingDirectory = '' }
                   Cmd = 'cmd.exe /c takeown /f "%1" && icacls "%1" /grant *S-1-3-4:F /c /l' }
                @{ Base = 'Directory'; Key = 'runas'; Name = 'Take ownership'; Icon = 'imageres.dll,-78'; Isolated = $true
                   Extra = @{ HasLUAShield = ''; NoWorkingDirectory = '' }
                   Cmd = 'cmd.exe /c takeown /f "%1" /r /d y && icacls "%1" /grant *S-1-3-4:F /t /c /l /q' }
            )
        }
        'copypath' {
            return @(
                @{ Base = '*';         Key = 'CopyFullPath'; Name = 'Copy full path'; Icon = 'imageres.dll,-5302'; Cmd = 'cmd.exe /c <nul set /p ="%1"| clip' }
                @{ Base = 'Directory'; Key = 'CopyFullPath'; Name = 'Copy full path'; Icon = 'imageres.dll,-5302'; Cmd = 'cmd.exe /c <nul set /p ="%1"| clip' }
            )
        }
        'sha256' {
            $cmd = 'powershell.exe -NoProfile -NoExit -Command "$p=\"%1\"; $s=[IO.File]::OpenRead($p); $h=[BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($s)).Replace(\"-\",\"\"); $s.Close(); Write-Host \"`n  $p`n\"; Write-Host \"  SHA256  $h`n\" -ForegroundColor Green"'
            return @(@{ Base = '*'; Key = 'Sha256Hash'; Name = 'Show SHA-256 hash'; Icon = 'powershell.exe'; Cmd = $cmd })
        }
        'godmode' {
            return @(@{ Base = 'DesktopBackground'; Key = 'GodMode'; Name = 'God Mode'; Icon = 'control.exe'; Cmd = 'explorer.exe shell:::{ED7BA470-8E54-465E-825C-99712043E01C}' })
        }
    }
    return $null
}

function Test-PresetInstalled([string]$Id, $Spec) {
    if (-not $Spec) { return $false }
    foreach ($s in $Spec) {
        $k = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey("Software\Classes\$($s.Base)\shell\$($s.Key)")
        if (-not $k) { return $false }
        $mark = [string]$k.GetValue('CMEPreset')
        $k.Close()
        if ($mark -ne $Id) { return $false }
    }
    return $true
}

function Install-Preset([string]$Id) {
    $spec = Get-PresetSpec $Id
    if (-not $spec) { throw 'The program this shortcut needs was not found.' }
    foreach ($s in $spec) {
        $path = "Software\Classes\$($s.Base)\shell\$($s.Key)"
        $existing = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($path)
        if ($existing) {
            $mark = [string]$existing.GetValue('CMEPreset')
            $existing.Close()
            if ($mark -ne $Id) { throw "A different '$($s.Key)' entry already exists for $($s.Base). Remove it first." }
        }
        $k = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($path)
        try {
            $k.SetValue('', $s.Name)
            $k.SetValue('MUIVerb', $s.Name)
            $k.SetValue('Icon', $s.Icon)
            $k.SetValue('CMEPreset', $Id)
            if ($s.Extra) { foreach ($e in $s.Extra.Keys) { $k.SetValue($e, $s.Extra[$e]) } }
            $ck = $k.CreateSubKey('command')
            try {
                $ck.SetValue('', $s.Cmd)
                if ($s.Isolated) { $ck.SetValue('IsolatedCommand', $s.Cmd) }
            } finally { $ck.Close() }
        } finally { $k.Close() }
    }
}

function Uninstall-Preset([string]$Id) {
    foreach ($base in $BaseKeys.Keys) {
        $shell = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey("Software\Classes\$base\shell", $true)
        if (-not $shell) { continue }
        try {
            foreach ($n in $shell.GetSubKeyNames()) {
                $k = $shell.OpenSubKey($n)
                $mark = if ($k) { [string]$k.GetValue('CMEPreset') } else { '' }
                if ($k) { $k.Close() }
                if ($mark -eq $Id) { $shell.DeleteSubKeyTree($n, $false) }
            }
        } finally { $shell.Close() }
    }
}

