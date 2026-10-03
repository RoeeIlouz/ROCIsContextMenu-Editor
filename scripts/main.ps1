# ==============================================================================
# BUILD WINDOW
# ==============================================================================
try { [void][CME.Native]::SetCurrentProcessExplicitAppUserModelID('ROCIsApps.ContextMenuEditor') } catch {}
$Window = New-Window $MainXaml
$U = @{}
foreach ($n in 'NavList', 'AdminCard', 'AdminDot', 'TxtAdmin', 'TxtAdminSub', 'BtnRestartExplorer', 'BtnOpenBackups', 'TxtTitle', 'TxtSubtitle',
               'BtnAdd', 'Toolbar', 'TxtSearch', 'KindAll', 'KindCmd', 'KindExt', 'ChkBuiltIn', 'BtnRefresh', 'BtnBackupAll', 'FileTypeBar',
               'TxtExt', 'BtnExtGo', 'ExtChips', 'ListArea', 'ItemList', 'EmptyState', 'TxtEmpty', 'TxtEmptySub', 'DetailPane',
               'DetailEmpty', 'DetailBody', 'DetailIcon', 'DetailGlyph', 'DetailName', 'DetailKind', 'DetailState', 'DetailStateSub',
               'DetailSwitch', 'DetailFields', 'BtnEdit', 'BtnDelete', 'BtnRegedit', 'BtnCopy', 'TweaksPanel', 'TweakList', 'TweakPresetList', 'BtnTweakClear', 'BtnTweakRun', 'BtnTweakUndo',
               'TxtStatus', 'PendingBar', 'BtnPendingRestart', 'BtnUndo', 'BrokenBar', 'BtnCleanup',
               'BackupsPanel', 'BackupList', 'BackupsEmpty', 'BtnBackupNow', 'BtnBackupFolder', 'KindSeg', 'NewBar', 'TxtNewExt',
               'BtnAddNewType', 'SendToBar', 'BtnSendToProgram', 'BtnSendToFolder', 'BtnSendToOpen', 'DetailMulti', 'TxtMultiTitle',
               'TxtMultiSub', 'BtnMultiOn', 'BtnMultiOff', 'BtnMultiDelete', 'BtnExportSetup', 'BtnImportSetup', 'BtnAddSendTo',
               'BrandIcon', 'BrandWordmark', 'BtnAbout') {
    $U[$n] = $Window.FindName($n)
}
$U.BrandIcon.Source = Get-AssetImage 'app-icon-64.png'
$U.BrandWordmark.Source = Get-AssetImage 'wordmark.png'

$G.Broken  = 'M13,14H11V10H13M13,18H11V16H13M1,21H23L12,2L1,21Z'
$G.History = 'M13.5,8H12V13L16.28,15.54L17,14.33L13.5,12.25V8M13,3A9,9 0 0,0 4,12H1L4.96,16.03L9,12H6A7,7 0 0,1 13,5A7,7 0 0,1 20,12A7,7 0 0,1 13,19C11.07,19 9.32,18.21 8.06,16.94L6.64,18.36C8.27,20 10.5,21 13,21A9,9 0 0,0 22,12A9,9 0 0,0 13,3'

$NavEntries = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
foreach ($d in @(
    @('all', $G.List), @('files', $G.File), @('folders', $G.Folder), @('background', $G.FolderBg),
    @('desktop', $G.Desktop), @('drives', $G.Drive), @('filetypes', $G.FileType), @('newmenu', $G.NewFile), @('sendto', $G.Send),
    @('broken', $G.Broken), @('backups', $G.History), @('tweaks', $G.Tweak)
)) {
    $e = [CME.NavEntry]::new()
    $e.Id = $d[0]; $e.Label = $NavText[$d[0]][0]; $e.Glyph = $d[1]
    $e.Margin = if ($d[0] -eq 'broken') { '0,14,0,0' } else { '0' }
    $NavEntries.Add($e)
}
$U.NavList.ItemsSource = $NavEntries
$U.ItemList.ItemsSource = $App.View
$U.ExtChips.ItemsSource = @('.txt', '.pdf', '.png', '.jpg', '.mp4', '.zip', '.ps1', '.py')
$U.TxtExt.Text = $App.Ext

if ($App.IsAdmin) {
    $U.AdminDot.Fill = $Window.FindResource('Success')
    $U.TxtAdmin.Text = 'Administrator'
    $U.TxtAdminSub.Text = 'Can change entries for all users'
} else {
    $U.AdminCard.Cursor = [System.Windows.Input.Cursors]::Hand
    $U.AdminCard.ToolTip = 'All-users (HKLM) entries are read-only until you restart as administrator'
    $U.AdminCard.Add_MouseLeftButtonUp({ Restart-Elevated })
}

# ------------------------------------------------------------------------------
# EVENTS
# ------------------------------------------------------------------------------
$U.NavList.Add_SelectionChanged({
    $nav = $U.NavList.SelectedItem
    if (-not $nav) { return }
    $App.Nav = $nav.Id
    $U.TxtTitle.Text = $NavText[$nav.Id][0]
    $page = switch ($nav.Id) { 'tweaks' { 'tweaks' } 'backups' { 'backups' } default { 'list' } }
    $U.TweaksPanel.Visibility = if ($page -eq 'tweaks') { 'Visible' } else { 'Collapsed' }
    $U.BackupsPanel.Visibility = if ($page -eq 'backups') { 'Visible' } else { 'Collapsed' }
    foreach ($el in $U.ListArea, $U.DetailPane, $U.Toolbar) { $el.Visibility = if ($page -eq 'list') { 'Visible' } else { 'Collapsed' } }
    $U.BtnAdd.Visibility = if ($page -eq 'list' -and $nav.Id -notin 'broken', 'newmenu', 'sendto') { 'Visible' } else { 'Collapsed' }
    $U.NewBar.Visibility = if ($nav.Id -eq 'newmenu') { 'Visible' } else { 'Collapsed' }
    $U.SendToBar.Visibility = if ($nav.Id -eq 'sendto') { 'Visible' } else { 'Collapsed' }
    $U.KindSeg.Visibility = if ($KindlessNavs -contains $nav.Id) { 'Collapsed' } else { 'Visible' }
    $U.FileTypeBar.Visibility = if ($nav.Id -eq 'filetypes') { 'Visible' } else { 'Collapsed' }
    $U.BrokenBar.Visibility = if ($nav.Id -eq 'broken') { 'Visible' } else { 'Collapsed' }
    switch ($page) {
        'tweaks'  { $U.TxtSubtitle.Text = $NavText.tweaks[1]; Update-Tweaks }
        'backups' { Update-Backups }
        default   { $U.ItemList.SelectedItem = $null; Update-View; Update-Detail }
    }
})

$U.BtnUndo.Add_Click({ Invoke-Undo })
$U.BtnAddSendTo.Add_Click({ Invoke-AddToSendTo $U.ItemList.SelectedItem })
$U.BtnAddNewType.Add_Click({ Invoke-AddNewType })
$U.TxtNewExt.Add_KeyDown({ param($s, $e) if ($e.Key -eq 'Return') { Invoke-AddNewType; $e.Handled = $true } })
$U.BtnSendToProgram.Add_Click({ Invoke-AddSendTo })
$U.BtnSendToFolder.Add_Click({ Invoke-AddSendTo -Folder })
$U.BtnSendToOpen.Add_Click({ Start-Process explorer.exe -ArgumentList "`"$(Get-SendToDir)`"" })
$U.BtnMultiOn.Add_Click({ Invoke-SetEnabled @($U.ItemList.SelectedItems) $true })
$U.BtnMultiOff.Add_Click({ Invoke-SetEnabled @($U.ItemList.SelectedItems) $false })
$U.BtnMultiDelete.Add_Click({ Invoke-Delete @($U.ItemList.SelectedItems) })
$U.BtnExportSetup.Add_Click({ Invoke-ExportSetup })
$U.BtnImportSetup.Add_Click({ Invoke-ImportSetup })
$U.BtnCleanup.Add_Click({ Invoke-CleanupBroken })
$U.BackupList.AddHandler([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent, [System.Windows.RoutedEventHandler]{
    param($s, $e)
    $btn = $e.OriginalSource
    if (-not ($btn -is [System.Windows.Controls.Button])) { return }
    switch ([string]$btn.Tag) {
        'restore' { Invoke-RestoreBackup $btn.DataContext }
        'delete'  { Invoke-DeleteBackupFile $btn.DataContext }
    }
})
$U.BtnBackupNow.Add_Click({
    try {
        $f = Export-FullBackup
        Set-Status "Backup saved: $(Split-Path -Leaf $f)"
        Update-Backups
    } catch {
        [void](Show-Message -Title 'Backup failed' -Text $_.Exception.Message)
    }
})
$U.BtnBackupFolder.Add_Click({
    if (-not (Test-Path -LiteralPath $App.BackupDir)) { New-Item -ItemType Directory -Path $App.BackupDir -Force | Out-Null }
    Start-Process explorer.exe -ArgumentList "`"$($App.BackupDir)`""
})

$U.TxtSearch.Add_TextChanged({ $App.Search = $U.TxtSearch.Text; Update-View })
$U.KindAll.Add_Checked({ $App.Kind = 'all'; Update-View })
$U.KindCmd.Add_Checked({ $App.Kind = 'cmd'; Update-View })
$U.KindExt.Add_Checked({ $App.Kind = 'ext'; Update-View })
$U.ChkBuiltIn.Add_Click({ $App.ShowBuiltIn = [bool]$U.ChkBuiltIn.IsChecked; Update-View; Update-Detail })

$applyExt = {
    $t = $U.TxtExt.Text.Trim().TrimStart('.')
    if (-not $t) { return }
    $App.Ext = ".$($t.ToLowerInvariant())"
    $U.TxtExt.Text = $App.Ext
    Invoke-Refresh -Rescan
}
$U.BtnExtGo.Add_Click($applyExt)
$U.TxtExt.Add_KeyDown({ param($s, $e) if ($e.Key -eq 'Return') { & $applyExt; $e.Handled = $true } })
$U.ExtChips.AddHandler([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent, [System.Windows.RoutedEventHandler]{
    param($s, $e)
    $U.TxtExt.Text = [string]$e.OriginalSource.Tag
    & $applyExt
})

$U.ItemList.Add_SelectionChanged({ Update-Detail })
$U.ItemList.AddHandler([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent, [System.Windows.RoutedEventHandler]{
    param($s, $e)
    $tb = $e.OriginalSource
    if ($tb -is [System.Windows.Controls.Primitives.ToggleButton]) {
        $U.ItemList.SelectedItem = $tb.DataContext
        Invoke-Toggle $tb.DataContext ([bool]$tb.IsChecked)
    }
})
$U.ItemList.Add_MouseDoubleClick({
    param($s, $e)
    $src = $e.OriginalSource
    while ($src -and -not ($src -is [System.Windows.Controls.ListBoxItem])) {
        if ($src -is [System.Windows.Controls.Primitives.ToggleButton]) { return }
        $src = [System.Windows.Media.VisualTreeHelper]::GetParent($src)
    }
    if ($src -and $U.ItemList.SelectedItem) { Invoke-Edit $U.ItemList.SelectedItem }
})

$U.DetailSwitch.Add_Click({ Invoke-Toggle $U.ItemList.SelectedItem ([bool]$U.DetailSwitch.IsChecked) })
$U.BtnEdit.Add_Click({ Invoke-Edit $U.ItemList.SelectedItem })
$U.BtnDelete.Add_Click({ Invoke-Delete $U.ItemList.SelectedItem })
$U.BtnRegedit.Add_Click({ Open-InRegedit $U.ItemList.SelectedItem })
$U.BtnCopy.Add_Click({
    $it = $U.ItemList.SelectedItem
    if ($it -and $it.Command) { [System.Windows.Clipboard]::SetText($it.Command); Set-Status 'Command copied to the clipboard.' }
})

$U.BtnAdd.Add_Click({ Invoke-Edit $null })
$U.BtnRefresh.Add_Click({
    $App.IconCache.Clear(); $App.ClsidCache.Clear(); $App.PathCache.Clear(); $App.MissingCache.Clear(); $App.Packaged = $null; $App.ShellNewParents = $null
    Invoke-Refresh -Rescan
    Set-Status "Rescanned. $($App.Items.Count) entries found."
})
$U.BtnBackupAll.Add_Click({
    try {
        $f = Export-FullBackup
        Set-Status "Backup saved: $(Split-Path -Leaf $f)"
    } catch {
        [void](Show-Message -Title 'Backup failed' -Text $_.Exception.Message)
    }
})
$U.BtnOpenBackups.Add_Click({
    if (-not (Test-Path -LiteralPath $App.BackupDir)) { New-Item -ItemType Directory -Path $App.BackupDir -Force | Out-Null }
    Start-Process explorer.exe -ArgumentList "`"$($App.BackupDir)`""
})
$U.BtnRestartExplorer.Add_Click({ Restart-Explorer })
$U.BtnAbout.Add_Click({ Show-About })
$U.BtnPendingRestart.Add_Click({ Restart-Explorer })

# Tweaks page: checking a box only marks it; a toggle applies immediately.
$U.TweakList.AddHandler([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent, [System.Windows.RoutedEventHandler]{
    param($s, $e)
    $src = $e.OriginalSource
    $item = $src.DataContext
    if (-not $item) { return }
    switch ([string]$src.Tag) {
        'check'  { $item.Checked = [bool]$src.IsChecked }
        'toggle' { Invoke-Tweaks @($item.Id) -Undo:(-not [bool]$src.IsChecked) }
    }
})
$U.TweakPresetList.AddHandler([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent, [System.Windows.RoutedEventHandler]{
    param($s, $e)
    $name = [string]$e.OriginalSource.Tag
    $presets = Get-TweakPresets
    if ($presets.Contains($name)) {
        Set-TweakChecks $presets[$name]
        Set-Status "Checked the `"$name`" preset ($(@($presets[$name]).Count) tweaks). Press Run tweaks to apply."
    }
})
$U.BtnTweakClear.Add_Click({ Set-TweakChecks @() })
$U.BtnTweakRun.Add_Click({ Invoke-Tweaks (Get-CheckedTweakIds) })
$U.BtnTweakUndo.Add_Click({ Invoke-Tweaks (Get-CheckedTweakIds) -Undo })
$Window.Add_PreviewKeyDown({
    param($s, $e)
    $ctrl = [System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Control
    $inText = [System.Windows.Input.Keyboard]::FocusedElement -is [System.Windows.Controls.TextBox]
    if ($ctrl -and $e.Key -eq 'F') { $U.TxtSearch.Focus(); $U.TxtSearch.SelectAll(); $e.Handled = $true }
    elseif ($e.Key -eq 'F5') { $U.BtnRefresh.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)); $e.Handled = $true }
    elseif ($e.Key -eq 'Escape' -and $inText -and $U.TxtSearch.Text) { $U.TxtSearch.Text = ''; $e.Handled = $true }
    elseif (-not $inText -and $e.Key -eq 'Delete' -and $U.ItemList.SelectedItem) { Invoke-Delete @($U.ItemList.SelectedItems); $e.Handled = $true }
    elseif (-not $inText -and $e.Key -eq 'Return' -and $U.ItemList.SelectedItem) { Invoke-Edit $U.ItemList.SelectedItem; $e.Handled = $true }
})

# ------------------------------------------------------------------------------
# START
# ------------------------------------------------------------------------------
# The window opens first and the registry is read once it's on screen, so the first scan
# (the slowest part of starting) happens behind a visible "reading" state instead of before any window.
$U.EmptyState.Visibility = 'Visible'
$U.DetailPane.Visibility = 'Collapsed'
$U.TxtEmpty.Text = 'Reading your context menus'
$U.TxtEmptySub.Text = 'Looking through the registry, Send to and New.'
$Window.Add_ContentRendered({
    $Window.Activate()
    # Background priority lets the first frame paint before the scan takes over the UI thread.
    [void]$Window.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, [Action]{
        $Window.Cursor = [System.Windows.Input.Cursors]::AppStarting
        try {
            Invoke-Scan
            $U.NavList.SelectedIndex = 0
            ($NavEntries | Where-Object Id -eq 'backups').Count = [string]@(Get-Backups).Count
            $brokenCount = @($App.Items | Where-Object Broken).Count
            $startMsg = "$($App.Items.Count) entries found"
            if ($brokenCount) { $startMsg += ", $brokenCount broken (see Broken entries)" }
            if (-not $App.IsAdmin) { $startMsg += '. All-users entries are read-only until you run as administrator' }
            Set-Status "$startMsg."
        } finally { $Window.Cursor = $null }
    })
})

# Smoke test for the launchers: with CME_SMOKETEST_OUT set, report what started and close after a moment.
if ($env:CME_SMOKETEST_OUT) {
    $Window.Add_ContentRendered({
        $t = [System.Windows.Threading.DispatcherTimer]::new()
        $t.Interval = [TimeSpan]::FromMilliseconds(2500)
        $t.Add_Tick({
            param($sender)
            $sender.Stop()
            "ok items=$($App.Items.Count) version=$AppVersion scriptPath=[$($App.ScriptPath)] backupDir=[$($App.BackupDir)] launchUrl=[$AppLaunchUrl] tweaks=$(@(Get-TweakDefinitions).Count)" |
                Set-Content -LiteralPath $env:CME_SMOKETEST_OUT
            $Window.Close()
        })
        $t.Start()
    })
}
[void]$Window.ShowDialog()
