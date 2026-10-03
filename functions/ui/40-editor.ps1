# ------------------------------------------------------------------------------
# Add / edit dialog (commands and submenus)
# ------------------------------------------------------------------------------
function Show-Editor($Existing, $Parent) {
    $w = New-Window $EditorXaml
    $w.Owner = $Window
    $w.MaxHeight = [System.Windows.SystemParameters]::WorkArea.Height - 40
    $c = @{}
    foreach ($n in 'EdTitle', 'EdSubtitle', 'EdModeRow', 'EdModeCmd', 'EdModeSub', 'EdName', 'EdCommandSection', 'EdCommand', 'EdBrowseExe',
                   'EdTok1', 'EdTokV', 'EdIcon', 'EdIconPreview', 'EdBrowseIcon', 'EdLocFiles', 'EdLocFolders', 'EdLocBackground',
                   'EdLocDesktop', 'EdLocDrives', 'EdLocAll', 'EdLocType', 'EdLocOther', 'EdExt', 'EdScopeUser', 'EdScopeAll',
                   'EdGroupSection', 'EdGroups', 'EdGroupHint', 'EdShift', 'EdShield', 'EdPosDefault', 'EdPosTop', 'EdPosBottom',
                   'EdError', 'EdCancel', 'EdSave', 'EdTest') {
        $c[$n] = $w.FindName($n)
    }
    $locMap = [ordered]@{ EdLocFiles = '*'; EdLocFolders = 'Directory'; EdLocBackground = 'Directory\Background'; EdLocDesktop = 'DesktopBackground'; EdLocDrives = 'Drive'; EdLocAll = 'AllFilesystemObjects' }
    $result = @{ Id = $null }
    $state = @{ Group = if ($Existing) { $Existing.ParentPath } elseif ($Parent) { $Parent.SubPath } else { '' } }

    $updatePreview = {
        $spec = if ($c.EdIcon.Text.Trim()) { $c.EdIcon.Text.Trim() } else { Get-ExeFromCommand $c.EdCommand.Text }
        $c.EdIconPreview.Source = Get-IconImage $spec
    }
    $c.EdIcon.Add_TextChanged($updatePreview)
    $c.EdCommand.Add_TextChanged($updatePreview)

    # '' when no valid location is chosen
    $getBase = {
        foreach ($k in $locMap.Keys) { if ($c[$k].IsChecked) { return $locMap[$k] } }
        if ($c.EdLocType.IsChecked) {
            $ext = $c.EdExt.Text.Trim().TrimStart('.').ToLowerInvariant()
            if ($ext -and $ext -notmatch '[^a-z0-9_+-]') { return "SystemFileAssociations\.$ext" }
            return ''
        }
        if ($c.EdLocOther.IsChecked -and $Existing) { return $Existing.BaseKey }
        return ''
    }

    $isSubmenuMode = { if ($Existing) { [bool]$Existing.Submenu } else { [bool]$c.EdModeSub.IsChecked } }

    # Submenus the command can go into: same location and scope, editable, top level.
    $refreshGroups = {
        $checked = $c.EdGroups.Children | Where-Object { $_.IsChecked } | Select-Object -First 1
        if ($checked) { $state.Group = [string]$checked.Tag }
        $c.EdGroups.Children.Clear()
        $base = & $getBase
        $hive = if ($c.EdScopeAll.IsChecked) { 'HKLM' } else { 'HKCU' }
        $groups = @($App.Items | Where-Object {
            $_.Kind -eq 'Command' -and $_.Submenu -and $_.CanEdit -and -not $_.ParentName -and $_.BaseKey -eq $base -and
            $_.Hive -eq $hive -and (-not $Existing -or $_.Id -ne $Existing.Id)
        } | Sort-Object Name)
        $choices = @(@{ Label = 'Not in a submenu'; Tag = '' }) + @($groups | ForEach-Object { @{ Label = $_.Name; Tag = $_.SubPath } })
        $matched = $false
        foreach ($ch in $choices) {
            $rb = [System.Windows.Controls.RadioButton]::new()
            $rb.Style = $w.FindResource('Chip')
            $rb.GroupName = 'grp'
            $rb.Content = $ch.Label
            $rb.Tag = $ch.Tag
            if ($ch.Tag -eq $state.Group) { $rb.IsChecked = $true; $matched = $true }
            [void]$c.EdGroups.Children.Add($rb)
        }
        if (-not $matched) { $c.EdGroups.Children[0].IsChecked = $true }
        $c.EdGroupHint.Visibility = if ($groups.Count) { 'Collapsed' } else { 'Visible' }
    }

    $applyMode = {
        $sub = & $isSubmenuMode
        $c.EdCommandSection.Visibility = if ($sub) { 'Collapsed' } else { 'Visible' }
        $c.EdGroupSection.Visibility = if ($sub) { 'Collapsed' } else { 'Visible' }
        if (-not $Existing) {
            $c.EdTitle.Text = if ($sub) { 'New submenu' } else { 'New command' }
            $w.Title = $c.EdTitle.Text
            $c.EdSubtitle.Text = if ($sub) { 'Groups several commands under one entry. Add commands to it with "New command".' }
                                 else { 'Runs a program when you pick it from the right-click menu.' }
            $c.EdSave.Content = if ($sub) { 'Add submenu' } else { 'Add command' }
            $c.EdName.Tag = if ($sub) { 'Text shown in the menu, e.g. Dev tools' } else { 'Text shown in the menu, e.g. Open with Notepad++' }
        }
    }
    $c.EdModeCmd.Add_Checked($applyMode)
    $c.EdModeSub.Add_Checked($applyMode)

    $selectBase = {
        param([string]$Base)
        foreach ($k in $locMap.Keys) { if ($locMap[$k] -eq $Base) { $c[$k].IsChecked = $true; return } }
        if ($Base -like 'SystemFileAssociations\.*') {
            $c.EdLocType.IsChecked = $true
            $c.EdExt.Text = $Base.Substring(23)
            return
        }
        $c.EdLocOther.Content = "Current: $Base"
        $c.EdLocOther.Visibility = 'Visible'
        $c.EdLocOther.IsChecked = $true
    }

    if ($Existing) {
        $kindWord = if ($Existing.Submenu) { 'submenu' } else { 'command' }
        $w.Title = "Edit $kindWord"
        $c.EdTitle.Text = "Edit $kindWord"
        $c.EdSubtitle.Text = "Changes are written to $($Existing.Hive)\$($Existing.SubPath). A backup is saved first."
        $c.EdModeRow.Visibility = 'Collapsed'
        $c.EdName.Text = $Existing.Name
        $c.EdCommand.Text = $Existing.Command
        $c.EdIcon.Text = $Existing.IconValue
        $c.EdShift.IsChecked = [bool]$Existing.Extended
        $c.EdShield.IsChecked = [bool]$Existing.Shield
        switch ($Existing.Position) { 'Top' { $c.EdPosTop.IsChecked = $true } 'Bottom' { $c.EdPosBottom.IsChecked = $true } }
        if ($Existing.Hive -eq 'HKLM') { $c.EdScopeAll.IsChecked = $true }
        & $selectBase $Existing.BaseKey
        $c.EdSave.Content = 'Save changes'
    } else {
        $navBase = @{ files = '*'; folders = 'Directory'; background = 'Directory\Background'; desktop = 'DesktopBackground'; drives = 'Drive' }
        if ($Parent) {
            if ($Parent.Hive -eq 'HKLM') { $c.EdScopeAll.IsChecked = $true }
            & $selectBase $Parent.BaseKey
        }
        elseif ($App.Nav -eq 'filetypes') { $c.EdLocType.IsChecked = $true; $c.EdExt.Text = $App.Ext }
        elseif ($navBase.ContainsKey($App.Nav)) { & $selectBase $navBase[$App.Nav] }
        else { $c.EdLocFiles.IsChecked = $true }
    }
    & $applyMode
    & $refreshGroups
    foreach ($k in @($locMap.Keys) + 'EdLocType', 'EdLocOther', 'EdScopeUser', 'EdScopeAll') { $c[$k].Add_Checked($refreshGroups) }
    $c.EdExt.Add_TextChanged($refreshGroups)
    $c.EdLocType.Add_Checked({ $c.EdExt.Visibility = 'Visible'; $c.EdExt.Focus() })
    $c.EdLocType.Add_Unchecked({ $c.EdExt.Visibility = 'Collapsed' })
    if ($c.EdLocType.IsChecked) { $c.EdExt.Visibility = 'Visible' }
    if (-not $App.IsAdmin -and -not $c.EdScopeAll.IsChecked) { $c.EdScopeAll.ToolTip = 'Restart the editor as administrator to install for all users' }

    $insertToken = {
        param([string]$Token)
        $tb = $c.EdCommand
        $text = "`"$Token`""
        $pos = $tb.CaretIndex
        if ($pos -gt 0 -and $tb.Text[$pos - 1] -ne ' ') { $text = " $text" }
        $tb.Text = $tb.Text.Insert($pos, $text)
        $tb.CaretIndex = $pos + $text.Length
        $tb.Focus()
    }
    $c.EdTok1.Add_Click({ & $insertToken '%1' })
    $c.EdTokV.Add_Click({ & $insertToken '%V' })

    $c.EdBrowseExe.Add_Click({
        $dlg = [System.Windows.Forms.OpenFileDialog]::new()
        $dlg.Filter = 'Programs (*.exe;*.bat;*.cmd)|*.exe;*.bat;*.cmd|All files (*.*)|*.*'
        $dlg.Title = 'Choose the program to run'
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $token = if ($c.EdLocBackground.IsChecked -or $c.EdLocDesktop.IsChecked) { '%V' } else { '%1' }
            $c.EdCommand.Text = "`"$($dlg.FileName)`" `"$token`""
            if (-not $c.EdName.Text.Trim()) {
                $desc = try { [Diagnostics.FileVersionInfo]::GetVersionInfo($dlg.FileName).FileDescription } catch { '' }
                if (-not $desc) { $desc = [IO.Path]::GetFileNameWithoutExtension($dlg.FileName) }
                $c.EdName.Text = "Open with $desc"
            }
        }
    })
    $c.EdTest.Add_Click({
        $c.EdError.Foreground = $w.FindResource('Danger')
        $c.EdError.Text = ''
        $command = $c.EdCommand.Text.Trim()
        if (-not $command) { $c.EdError.Text = 'Enter a command to test.'; $c.EdCommand.Focus(); return }
        # Pick a sample like the one Explorer would pass for this location.
        $base = & $getBase
        $sample = $null
        if ($base -eq 'DesktopBackground') {
            $sample = [Environment]::GetFolderPath('Desktop')
        } elseif ($base -in 'Directory', 'Directory\Background', 'Drive', 'Folder') {
            $dlg = [System.Windows.Forms.FolderBrowserDialog]::new()
            $dlg.Description = 'Pick a folder to test the command on'
            if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $sample = $dlg.SelectedPath }
        } else {
            $dlg = [System.Windows.Forms.OpenFileDialog]::new()
            $dlg.Title = 'Pick a file to test the command on'
            if ($base -like 'SystemFileAssociations\.*') { $e = $base.Substring(23); $dlg.Filter = "$e files (*$e)|*$e|All files (*.*)|*.*" }
            if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $sample = $dlg.FileName }
        }
        if (-not $sample) { return }
        try {
            $ran = Invoke-TestCommand $command $sample
            $c.EdError.Foreground = $w.FindResource('Success')
            $c.EdError.Text = "Started: $ran"
        } catch {
            $c.EdError.Text = "Could not run it: $($_.Exception.InnerException.Message)$(if (-not $_.Exception.InnerException) { $_.Exception.Message })"
        }
    })
    $c.EdBrowseIcon.Add_Click({
        $dlg = [System.Windows.Forms.OpenFileDialog]::new()
        $dlg.Filter = 'Icons (*.ico;*.exe;*.dll)|*.ico;*.exe;*.dll|All files (*.*)|*.*'
        $dlg.Title = 'Choose an icon'
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $c.EdIcon.Text = $dlg.FileName }
    })

    $c.EdSave.Add_Click({
        $c.EdError.Foreground = $w.FindResource('Danger')
        $c.EdError.Text = ''
        $isSub = & $isSubmenuMode
        $name = $c.EdName.Text.Trim()
        $command = $c.EdCommand.Text.Trim()
        if (-not $name) { $c.EdError.Text = 'Give it a name.'; $c.EdName.Focus(); return }
        if (-not $isSub -and -not $command -and -not ($Existing -and $Existing.Delegate)) { $c.EdError.Text = 'Enter the command to run.'; $c.EdCommand.Focus(); return }

        $base = & $getBase
        if (-not $base) {
            if ($c.EdLocType.IsChecked) { $c.EdError.Text = 'Enter a file extension such as .pdf'; $c.EdExt.Focus() }
            else { $c.EdError.Text = 'Choose where it appears.' }
            return
        }
        $hive = if ($c.EdScopeAll.IsChecked) { 'HKLM' } else { 'HKCU' }
        if ($hive -eq 'HKLM' -and -not $App.IsAdmin) { $c.EdError.Text = 'Installing for all users needs administrator rights. Use the card at the bottom of the sidebar to restart as admin.'; return }
        $position = if ($c.EdPosTop.IsChecked) { 'Top' } elseif ($c.EdPosBottom.IsChecked) { 'Bottom' } else { '' }
        $group = if ($isSub) { '' } else { [string]($c.EdGroups.Children | Where-Object { $_.IsChecked } | Select-Object -First 1).Tag }
        $shellPath = if ($group) { "$group\shell" } else { "Software\Classes\$base\shell" }

        try {
            $result.Id = Save-MenuCommand -Existing $Existing -Name $name -Command $command -Icon $c.EdIcon.Text.Trim() `
                -Hive $hive -ShellPath $shellPath -Extended ([bool]$c.EdShift.IsChecked) -Shield ([bool]$c.EdShield.IsChecked) `
                -Position $position -IsSubmenu $isSub
            $w.DialogResult = $true
        } catch {
            $c.EdError.Text = "Could not save: $($_.Exception.Message)"
        }
    })

    $w.Add_ContentRendered({ $c.EdName.Focus(); $c.EdName.SelectAll() })
    & $updatePreview
    [void]$w.ShowDialog()
    return $result.Id
}

function Invoke-Edit($Item) {
    if ($Item -and -not $Item.CanEdit) { return }
    if ($Item -and $Item.Hive -eq 'HKLM' -and -not $App.IsAdmin) {
        [void](Invoke-Write 'HKLM' {})
        return
    }
    # "New command" while a submenu is selected starts inside that submenu.
    $sel = $U.ItemList.SelectedItem
    $parent = if (-not $Item -and $sel -and $sel.Submenu -and $sel.CanEdit -and -not $sel.ParentName) { $sel } else { $null }
    $id = Show-Editor $Item $parent
    if (-not $id) { return }

    $newPath = Get-IdPath $id
    if ($Item) {
        Set-Status "Saved changes to `"$($Item.Name)`"."
        Set-Undo @{ Type = 'restore'; Files = @($App.LastBackup); DeletePaths = @($newPath); NeedsAdmin = $Item.Hive -eq 'HKLM'
                    Pending = $false; Label = "edit of $($Item.Name)" }
    } else {
        Set-Status 'Added. Right-click something to try it.'
        Set-Undo @{ Type = 'restore'; Files = @(); DeletePaths = @($newPath); NeedsAdmin = $false; Pending = $false; Label = 'adding the entry' }
    }
    Invoke-Refresh -Rescan -SelectId $id
}

function Invoke-AddNewType {
    $ext = $U.TxtNewExt.Text.Trim()
    if (-not $ext) { $U.TxtNewExt.Focus(); return }
    $result = @{}
    try {
        # Decide the hive up front so non-admins get the restart offer instead of an access error.
        $e = '.' + $ext.TrimStart('.').ToLowerInvariant()
        $userKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey("Software\Classes\$e")
        $hive = if ($userKey) { $userKey.Close(); 'HKCU' } else { 'HKLM' }
        $ok = Invoke-Write $hive { $r = Add-ShellNewType $ext; $result.Hive = $r.Hive; $result.SubPath = $r.SubPath }
    } catch { $ok = $false; [void](Show-Message -Title 'Could not add it' -Text $_.Exception.Message) }
    if ($ok -and $result.SubPath) {
        $U.TxtNewExt.Text = ''
        Set-Status "Added $e to the New menu."
        Set-Undo @{ Type = 'restore'; Files = @(); DeletePaths = @(@{ Hive = $result.Hive; SubPath = $result.SubPath }); NeedsAdmin = $result.Hive -eq 'HKLM'; Pending = $true; Label = "adding $e" }
        Set-PendingRestart
        Invoke-Refresh -Rescan -SelectId "new|$($result.Hive)|$e"
    }
}

function Invoke-AddSendTo([switch]$Folder) {
    $target = $null
    if ($Folder) {
        $dlg = [System.Windows.Forms.FolderBrowserDialog]::new()
        $dlg.Description = 'Choose the folder to send files to'
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $target = $dlg.SelectedPath }
    } else {
        $dlg = [System.Windows.Forms.OpenFileDialog]::new()
        $dlg.Filter = 'Programs (*.exe;*.bat;*.cmd)|*.exe;*.bat;*.cmd|All files (*.*)|*.*'
        $dlg.Title = 'Choose the program to send files to'
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $target = $dlg.FileName }
    }
    if (-not $target) { return }
    try {
        $path = Add-SendToShortcut $target
        Set-Status "Added `"$([IO.Path]::GetFileNameWithoutExtension($path))`" to Send to."
        Set-Undo @{ Type = 'restore'; Files = @(); DeletePaths = @(); DeleteFiles = @($path); Label = 'adding the Send to shortcut' }
        Invoke-Refresh -Rescan -SelectId "sendto|$([IO.Path]::GetFileName($path))"
    } catch {
        [void](Show-Message -Title 'Could not add it' -Text $_.Exception.Message)
    }
}

function Invoke-ExportSetup {
    $dlg = [System.Windows.Forms.SaveFileDialog]::new()
    $dlg.Filter = 'Registry file (*.reg)|*.reg'
    $dlg.FileName = "context-menu-setup-$(Get-Date -Format 'yyyy-MM-dd').reg"
    $dlg.Title = 'Export your context menu setup'
    if ($dlg.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }
    try {
        $n = Export-Setup $dlg.FileName
        Set-Status "Exported $n registry keys to $(Split-Path -Leaf $dlg.FileName)."
    } catch {
        [void](Show-Message -Title 'Export failed' -Text $_.Exception.Message)
    }
}

function Invoke-ImportSetup {
    $dlg = [System.Windows.Forms.OpenFileDialog]::new()
    $dlg.Filter = 'Registry file (*.reg)|*.reg'
    $dlg.Title = 'Import a context menu setup'
    if ($dlg.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }
    $info = Get-BackupInfo ([IO.FileInfo]::new($dlg.FileName))
    $outside = @($info.Roots | Where-Object { $_ -notmatch '\\Software\\Classes\\|Shell Extensions\\Blocked' })
    $text = "Adds the $($info.Roots.Count) registry key$(if ($info.Roots.Count -ne 1) { 's' }) in this file to your registry. Nothing is deleted, and a full backup of your current menus is saved first."
    if ($outside) { $text += "`n`nWarning: this file also touches keys outside the context menu, for example:`n  $($outside[0])" }
    $r = Show-Message -Title "Import $(Split-Path -Leaf $dlg.FileName)?" -Text $text -Buttons @('Cancel', 'Import') -Primary 'Import'
    if ($r -ne 'Import') { return }
    $ok = Invoke-Write $(if ($info.NeedsAdmin) { 'HKLM' } else { 'HKCU' }) {
        [void](Export-FullBackup)
        [void](Restore-BackupFile $dlg.FileName -Merge)
    }
    if ($ok) {
        Set-Status 'Setup imported. A full backup of the previous state is in Backups.'
        Set-PendingRestart
    }
    Invoke-Scan
    Update-View
    if ($App.Nav -eq 'backups') { Update-Backups }
}

# Runs a command line the way Explorer would, with %1/%V/%L/%W replaced by a sample path.
function Invoke-TestCommand([string]$Command, [string]$SamplePath) {
    $line = [Environment]::ExpandEnvironmentVariables($Command.Trim())
    $line = [regex]::Replace($line, '%[1LVWlvw*]', [System.Text.RegularExpressions.MatchEvaluator] { param($m) $SamplePath })
    $exe = Get-ExeFromCommand $line
    $rest = if ($line.StartsWith('"')) { $line.Substring($exe.Length + 2) } else { $line.Substring($exe.Length) }
    $psi = [Diagnostics.ProcessStartInfo]::new($exe, $rest.Trim())
    $psi.UseShellExecute = $true
    $psi.WorkingDirectory = if (Test-Path -LiteralPath $SamplePath -PathType Container) { $SamplePath } else { Split-Path -Parent $SamplePath }
    [void][Diagnostics.Process]::Start($psi)
    return "$exe $($rest.Trim())"
}

function Open-InRegedit($Item) {
    if ($Item -and $Item.Kind -eq 'SendTo') {
        Start-Process explorer.exe -ArgumentList "/select,`"$($Item.FilePath)`""
        return
    }
    if (-not $Item -or -not $Item.SubPath) { return }
    $hive = if ($Item.Hive -eq 'HKLM') { 'HKEY_LOCAL_MACHINE' } else { 'HKEY_CURRENT_USER' }
    $k = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey('Software\Microsoft\Windows\CurrentVersion\Applets\Regedit')
    try { $k.SetValue('LastKey', "Computer\$hive\$($Item.SubPath)") } finally { $k.Close() }
    if (Get-Process regedit -ErrorAction SilentlyContinue) {
        Set-Status 'Registry Editor is already open; close it and try again so it jumps to this key.'
        return
    }
    try { Start-Process regedit.exe -ErrorAction Stop } catch { Set-Status 'Registry Editor was not opened.' }
}

function Restart-Explorer {
    Set-Status 'Restarting Explorer...'
    $U.PendingBar.Visibility = 'Collapsed'
    Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    # Windows normally restarts the shell by itself; start it only if it didn't come back.
    $timer = [System.Windows.Threading.DispatcherTimer]::new()
    $timer.Interval = [TimeSpan]::FromMilliseconds(2500)
    $timer.Add_Tick({
        param($sender)
        $sender.Stop()
        if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe }
        Set-Status 'Explorer restarted. Menus are reloaded.'
    })
    $timer.Start()
}

