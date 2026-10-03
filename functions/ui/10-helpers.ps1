# ==============================================================================
# UI HELPERS
# ==============================================================================
# Embedded brand image (see Compile.ps1 / tools\Build-Assets.ps1) as a frozen WPF image, or $null.
function Get-AssetImage([string]$Name) {
    if (-not $Assets -or -not $Assets[$Name]) { return $null }
    try {
        $ms = [IO.MemoryStream]::new([Convert]::FromBase64String($Assets[$Name]))
        $img = if ($Name -like '*.ico') {
            [System.Windows.Media.Imaging.BitmapFrame]::Create($ms, [System.Windows.Media.Imaging.BitmapCreateOptions]::None, [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad)
        } else {
            $bi = [System.Windows.Media.Imaging.BitmapImage]::new()
            $bi.BeginInit(); $bi.StreamSource = $ms; $bi.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad; $bi.EndInit()
            $bi
        }
        $img.Freeze()
        return $img
    } catch { return $null }
}

function New-Window([string]$Xaml) {
    $x = [xml]($Xaml.Replace('<!--RES-->', $ResXaml))
    $w = [Windows.Markup.XamlReader]::Load([System.Xml.XmlNodeReader]::new($x))
    if (-not $App.Icon) { $App.Icon = Get-AssetImage 'app-icon.ico' }
    if ($App.Icon) { $w.Icon = $App.Icon }
    $w.Add_SourceInitialized({
        param($sender)
        try { [CME.Native]::DarkTitleBar([System.Windows.Interop.WindowInteropHelper]::new($sender).Handle, 0x1F1C1B) } catch {}
    })
    return $w
}

function Show-Message {
    param([string]$Title, [string]$Text, [string[]]$Buttons = @('OK'), [string]$Primary = '', [switch]$Danger)
    $w = New-Window $MessageXaml
    if ($Window -and $Window.IsLoaded) { $w.Owner = $Window }
    $w.Title = $Title
    $w.FindName('MsgTitle').Text = $Title
    $w.FindName('MsgText').Text = $Text
    $panel = $w.FindName('MsgButtons')
    $res = @{ Value = $null }
    foreach ($label in $Buttons) {
        $b = [System.Windows.Controls.Button]::new()
        $b.Content = $label
        $b.Tag = $label
        $b.MinWidth = 86
        $b.Margin = [System.Windows.Thickness]::new(8, 0, 0, 0)
        $styleKey = if ($label -eq $Primary) { if ($Danger) { 'BtnDanger' } else { 'BtnPrimary' } } else { 'Btn' }
        $b.Style = $w.FindResource($styleKey)
        if ($label -eq $Primary) { $b.IsDefault = $true }
        $b.Add_Click({ param($s) $res.Value = $s.Tag; $w.Close() })
        [void]$panel.Children.Add($b)
    }
    [void]$w.ShowDialog()
    return $res.Value
}

# A dialog with a switch per choice (all on by default), plus an optional extra switch shown above them.
# Returns @{ Selected = labels; Extra = bool }, or $null if cancelled.
function Show-Choices([string]$Title, [string]$Text, [string[]]$Choices, [string]$Action, [string]$ExtraLabel) {
    $w = New-Window $MessageXaml
    if ($Window -and $Window.IsLoaded) { $w.Owner = $Window }
    $w.Title = $Title
    $w.FindName('MsgTitle').Text = $Title
    $msg = $w.FindName('MsgText')
    $msg.Text = $Text
    $host_ = $msg.Parent
    $extra = $null
    if ($ExtraLabel) {
        $box = [System.Windows.Controls.Border]::new()
        $box.Background = $w.FindResource('Surface')
        $box.CornerRadius = [System.Windows.CornerRadius]::new(8)
        $box.Padding = [System.Windows.Thickness]::new(12, 10, 12, 10)
        $box.Margin = [System.Windows.Thickness]::new(0, 14, 0, 0)
        $extra = [System.Windows.Controls.CheckBox]::new()
        $extra.Style = $w.FindResource('Switch')
        $extra.Content = $ExtraLabel
        $extra.IsChecked = $true
        $box.Child = $extra
        [void]$host_.Children.Add($box)
    }
    $list = [System.Windows.Controls.StackPanel]::new()
    $list.Margin = [System.Windows.Thickness]::new(0, 14, 0, 0)
    $boxes = foreach ($ch in $Choices) {
        $cb = [System.Windows.Controls.CheckBox]::new()
        $cb.Style = $w.FindResource('Switch')
        $cb.Content = $ch
        $cb.IsChecked = $true
        $cb.Margin = [System.Windows.Thickness]::new(0, 0, 0, 10)
        [void]$list.Children.Add($cb)
        $cb
    }
    [void]$host_.Children.Add($list)
    $res = @{ Value = $null }
    $panel = $w.FindName('MsgButtons')
    foreach ($label in 'Cancel', $Action) {
        $b = [System.Windows.Controls.Button]::new()
        $b.Content = $label
        $b.MinWidth = 86
        $b.Margin = [System.Windows.Thickness]::new(8, 0, 0, 0)
        $b.Style = $w.FindResource($(if ($label -eq $Action) { 'BtnPrimary' } else { 'Btn' }))
        if ($label -eq $Action) {
            $b.IsDefault = $true
            $b.Add_Click({
                $res.Value = @{ Selected = @($boxes | Where-Object IsChecked | ForEach-Object { [string]$_.Content }); Extra = [bool]($extra -and $extra.IsChecked) }
                $w.Close()
            })
        } else {
            $b.IsCancel = $true
            $b.Add_Click({ $w.Close() })
        }
        [void]$panel.Children.Add($b)
    }
    [void]$w.ShowDialog()
    return $res.Value
}

function Invoke-AddToSendTo($Item) {
    if (-not $Item) { return }
    $Window.Cursor = [System.Windows.Input.Cursors]::Wait
    try {
        $opts = Get-SendToOptions $Item   # returns its array as one object; @() would nest it
    } catch {
        $Window.Cursor = $null
        [void](Show-Message -Title "Can't add `"$($Item.Name)`" to Send to" -Text $_.Exception.Message)
        return
    }
    $Window.Cursor = $null

    $group = @($opts | ForEach-Object { $_.Group } | Where-Object { $_ } | Select-Object -Unique)
    $grouped = [bool]$group
    $chosen = $opts
    if ($opts.Count -gt 1 -or $group) {
        $answer = Show-Choices -Title "Add `"$($Item.Name)`" to Send to" -Action 'Add' -Choices @($opts | ForEach-Object { $_.Short }) `
            -Text 'Each one becomes its own Send to item that runs the same thing as the right-click menu. Turn off the ones you don''t want.' `
            -ExtraLabel $(if ($group) { "Put them in a `"$($group[0])`" submenu" } else { '' })
        if ($null -eq $answer) { return }
        $chosen = @($opts | Where-Object { $answer.Selected -contains $_.Short })
        $grouped = $answer.Extra
        if (-not $chosen) { return }
    }

    $created = [System.Collections.Generic.List[string]]::new()
    $moves = [System.Collections.Generic.List[object]]::new()
    $existing = 0
    $folder = $null
    try {
        if ($grouped -and $group) {
            $folder = Initialize-SendToFolder $group[0] $chosen[0].GroupIcon
        }
        foreach ($o in $chosen) {
            $r = New-SendToShortcut $o -Grouped:$grouped
            switch ($r.Action) {
                'created' { $created.Add($r.Path) }
                'moved'   { $moves.Add(@{ From = $r.From; To = $r.Path }) }
                default   { $existing++ }
            }
        }
    } catch {
        [void](Show-Message -Title 'Could not add it' -Text $_.Exception.Message)
    }
    if ($created.Count -or $moves.Count) {
        $parts = @()
        if ($created.Count) { $parts += "added $($created.Count)" }
        if ($moves.Count) { $parts += "moved $($moves.Count) existing" }
        $where = if ($folder) { " in Send to > $($group[0])" } else { ' to Send to' }
        $msg = (($parts -join ', ') + $where)
        if ($existing) { $msg += " ($existing already there)" }
        Set-Status "$($msg.Substring(0,1).ToUpper())$($msg.Substring(1)). Right-click a file > Send to to use it."
        # Undo moves things back; a submenu folder created here goes away with what was created in it.
        $deleteFiles = if ($folder -and $folder.Created) { @($folder.Path) } else { $created.ToArray() }
        Set-Undo @{ Type = 'restore'; Files = @(); DeletePaths = @(); Moves = $moves.ToArray(); DeleteFiles = $deleteFiles; Label = 'adding to Send to' }
        Invoke-Refresh -Rescan
    } elseif ($existing) {
        Set-Status 'Already in Send to; nothing to add.'
    }
}

function Set-Status([string]$Text) { $U.TxtStatus.Text = $Text }

function Set-PendingRestart { $U.PendingBar.Visibility = 'Visible' }

function Restart-Elevated {
    $exe = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    $sta = if ($PSVersionTable.PSEdition -eq 'Desktop') { ' -STA' } else { '' }
    if ($App.ScriptPath) {
        $run = "-File `"$($App.ScriptPath)`""
    } elseif ($AppLaunchUrl) {
        # Started with "irm <url> | iex": there's no file to relaunch, so the elevated copy downloads it again.
        $run = '-Command "irm ''' + $AppLaunchUrl.Replace("'", "''''") + ''' | iex"'
    } else {
        [void](Show-Message -Title 'Run it as administrator yourself' -Text 'This copy was started without a file or launch URL, so it can''t restart itself. Open PowerShell as administrator and start it again from there.')
        return
    }
    # conhost --headless keeps the elevated instance from opening a console or terminal window.
    $argLine = "--headless `"$exe`" -NoProfile -ExecutionPolicy Bypass$sta $run"
    try {
        Start-Process -FilePath 'conhost.exe' -ArgumentList $argLine -Verb RunAs -ErrorAction Stop
        $Window.Close()
    } catch {
        Set-Status 'Elevation was cancelled.'
    }
}

# Runs a registry write; turns access-denied into a friendly prompt to restart elevated.
function Invoke-Write([string]$Hive, [scriptblock]$Action) {
    if ($Hive -eq 'HKLM' -and -not $App.IsAdmin) {
        $r = Show-Message -Title 'Administrator rights needed' `
            -Text 'This entry is installed for all users, so changing it needs administrator rights. Restart the editor as administrator?' `
            -Buttons @('Cancel', 'Restart as admin') -Primary 'Restart as admin'
        if ($r -eq 'Restart as admin') { Restart-Elevated }
        return $false
    }
    try {
        & $Action
        return $true
    } catch {
        $msg = $_.Exception.Message
        if ($_.Exception -is [System.Security.SecurityException] -or $_.Exception -is [UnauthorizedAccessException] -or
            $_.Exception.InnerException -is [System.Security.SecurityException] -or $_.Exception.InnerException -is [UnauthorizedAccessException]) {
            $msg = "Windows denied access to that registry key. $msg"
        }
        [void](Show-Message -Title 'Could not apply the change' -Text $msg)
        return $false
    }
}

function Find-VisualChild($Element, [type]$Type) {
    if ($Element -is $Type) { return $Element }
    for ($i = 0; $i -lt [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($Element); $i++) {
        $r = Find-VisualChild ([System.Windows.Media.VisualTreeHelper]::GetChild($Element, $i)) $Type
        if ($r) { return $r }
    }
    return $null
}

function Test-InNav($Item, [string]$Nav) {
    if ($Nav -eq 'all') { return $Item.Kind -eq 'Modern' -or @($Item.LocIds | Where-Object { $_ -notin 'filetypes', 'newmenu', 'sendto' }).Count -gt 0 }
    if ($Nav -eq 'broken') { return $Item.Broken }
    return $Item.LocIds -contains $Nav
}

# The New menu and Send To lists are their own kinds; the Commands/Extensions filter doesn't apply there.
$KindlessNavs = @('newmenu', 'sendto')

function Test-Kind($Item) {
    if ($Item.Kind -eq 'New' -or $Item.Kind -eq 'SendTo') { return $App.Kind -eq 'all' }
    switch ($App.Kind) {
        'cmd' { return $Item.Kind -eq 'Command' }
        'ext' { return $Item.Kind -ne 'Command' }
        default { return $true }
    }
}

$NavText = @{
    all        = @('Everything', 'Every right-click entry Windows knows about')
    files      = @('Files', 'Shown when you right-click any file')
    folders    = @('Folders', 'Shown when you right-click a folder')
    background = @('Folder background', 'Shown when you right-click empty space inside a folder (and on the desktop)')
    desktop    = @('Desktop', 'Shown when you right-click the desktop')
    drives     = @('Drives', 'Shown when you right-click a drive in This PC')
    filetypes  = @('File types', 'Entries that only appear for one extension')
    newmenu    = @('New menu', 'The file types offered under New when you right-click a folder background')
    sendto     = @('Send to', 'Shortcuts in your Send To folder')
    broken     = @('Broken entries', 'Entries that point to a program or DLL that no longer exists')
    backups    = @('Backups', 'Every edit and delete saves the old version here first')
    tweaks     = @('Tweaks', 'Check what you want or pick a preset, then Run tweaks. Undo selected puts the original values back')
}

function Update-View {
    # Broken entries are listed even when they are Windows built-ins: a dead entry is worth seeing either way.
    $everything = @($App.Items)
    $all = @($everything | Where-Object { Test-Kind $_ })
    $base = @($all | Where-Object { $App.ShowBuiltIn -or -not $_.IsBuiltIn })
    $plain = @($everything | Where-Object { $App.ShowBuiltIn -or -not $_.IsBuiltIn })

    foreach ($n in $NavEntries) {
        if ($n.Id -eq 'tweaks' -or $n.Id -eq 'backups') { continue }
        $src = if ($n.Id -eq 'broken') { $all } elseif ($KindlessNavs -contains $n.Id) { $plain } else { $base }
        $n.Count = [string]@($src | Where-Object { Test-InNav $_ $n.Id }).Count
    }

    if ($App.Nav -eq 'tweaks' -or $App.Nav -eq 'backups') { return }

    $src = if ($App.Nav -eq 'broken') { $all } elseif ($KindlessNavs -contains $App.Nav) { $plain } else { $base }
    $inNav = @($src | Where-Object { Test-InNav $_ $App.Nav })
    $q = $App.Search.Trim().ToLowerInvariant()
    $shown = if ($q) { @($inNav | Where-Object { $_.SearchText.Contains($q) }) } else { $inNav }

    $App.View.Clear()
    foreach ($it in ($shown | Sort-Object GroupKey, ChildOrder, Name)) { $App.View.Add($it) }

    $off = @($inNav | Where-Object { -not $_.Enabled }).Count
    $sub = "$($inNav.Count) entries"
    if ($off) { $sub += ", $off turned off" }
    if ($App.Nav -eq 'filetypes') { $sub = "$($NavText.filetypes[1]): $($App.Ext)  /  $sub" } else { $sub = "$($NavText[$App.Nav][1])  /  $sub" }
    $U.TxtSubtitle.Text = $sub

    if ($App.Nav -eq 'broken') {
        $removable = @($inNav | Where-Object CanDelete).Count
        $U.BtnCleanup.Content = "Remove all ($removable)"
        $U.BtnCleanup.IsEnabled = $removable -gt 0
    }

    if ($App.View.Count -eq 0) {
        $U.EmptyState.Visibility = 'Visible'
        if ($q) {
            $U.TxtEmpty.Text = "No matches for `"$($App.Search.Trim())`""
            $U.TxtEmptySub.Text = 'Try a different word, or switch on Windows built-ins.'
        } elseif ($App.Nav -eq 'broken') {
            $U.TxtEmpty.Text = 'No broken entries'
            $U.TxtEmptySub.Text = 'Every entry points to a program or DLL that exists.'
        } else {
            $U.TxtEmpty.Text = 'Nothing here yet'
            $U.TxtEmptySub.Text = 'Add a command with "New command", or switch on Windows built-ins to see the defaults.'
        }
    } else {
        $U.EmptyState.Visibility = 'Collapsed'
    }
}

function Update-Detail {
    $it = $U.ItemList.SelectedItem
    $selected = @($U.ItemList.SelectedItems)
    $U.DetailMulti.Visibility = 'Collapsed'
    if (-not $it) {
        $U.DetailEmpty.Visibility = 'Visible'
        $U.DetailBody.Visibility = 'Collapsed'
        return
    }
    $U.DetailEmpty.Visibility = 'Collapsed'
    if ($selected.Count -gt 1) {
        $U.DetailBody.Visibility = 'Collapsed'
        $U.DetailMulti.Visibility = 'Visible'
        $on = @($selected | Where-Object Enabled).Count
        $U.TxtMultiTitle.Text = "$($selected.Count) entries selected"
        $U.TxtMultiSub.Text = "$on on, $($selected.Count - $on) off. Ctrl+click or Shift+click to change the selection."
        $deletable = @($selected | Where-Object CanDelete).Count
        $U.BtnMultiDelete.Content = if ($deletable -eq $selected.Count) { 'Delete all' } else { "Delete $deletable of $($selected.Count)" }
        $U.BtnMultiDelete.IsEnabled = $deletable -gt 0
        return
    }
    $U.DetailBody.Visibility = 'Visible'

    $U.DetailName.Text = $it.Name
    $U.DetailKind.Text = $it.KindLabel + $(if ($it.IsBuiltIn) { '  /  Windows built-in' } else { '' })
    $U.DetailIcon.Source = $it.IconImage
    $U.DetailGlyph.Data = [System.Windows.Media.Geometry]::Parse($it.Glyph)
    $U.DetailGlyph.Visibility = if ($it.IconImage) { 'Collapsed' } else { 'Visible' }
    $U.DetailSwitch.IsChecked = $it.Enabled
    $U.DetailState.Text = if ($it.Enabled) { 'Shown in the menu' } else { 'Hidden from the menu' }
    $U.DetailState.Foreground = if ($it.Enabled) { $Window.FindResource('Text') } else { $Window.FindResource('Warn') }
    $U.DetailStateSub.Text = switch ($it.Kind) {
        'Command' { if ($it.Submenu) { 'Turning it off hides the whole submenu; nothing is deleted.' } else { 'Turning it off sets LegacyDisable; nothing is deleted.' } }
        'Extension' { 'Turning it off adds the handler to the Blocked list. Applies after Explorer restarts.' }
        'New' { 'Turning it off renames its ShellNew key to _ShellNew; nothing is deleted.' }
        'SendTo' { if ($it.Submenu) { 'Turning it off hides the whole submenu folder; nothing is deleted.' } else { 'Turning it off hides the shortcut file; nothing is deleted.' } }
        default { 'Turning it off adds it to the Blocked list. Applies after Explorer restarts.' }
    }
    $U.DetailFields.ItemsSource = Get-EntryDetails $it
    $U.BtnEdit.Visibility = if ($it.CanEdit) { 'Visible' } else { 'Collapsed' }
    $U.BtnDelete.Visibility = if ($it.CanDelete) { 'Visible' } else { 'Collapsed' }
    $U.BtnDelete.Content = if ($it.Broken) { 'Remove' } else { 'Delete' }
    # Without an Edit button, let Delete take the whole row instead of sitting in the right half.
    [System.Windows.Controls.Grid]::SetColumn($U.BtnDelete, $(if ($it.CanEdit) { 2 } else { 0 }))
    [System.Windows.Controls.Grid]::SetColumnSpan($U.BtnDelete, $(if ($it.CanEdit) { 1 } else { 3 }))
    $U.BtnRegedit.Visibility = if ($it.CanRegedit) { 'Visible' } else { 'Collapsed' }
    $U.BtnRegedit.Content = if ($it.Kind -eq 'SendTo') { 'Show in folder' } else { 'Open in Regedit' }
    $U.BtnAddSendTo.Visibility = if (Test-CanSendTo $it) { 'Visible' } else { 'Collapsed' }
    $U.BtnCopy.Visibility = if ($it.Command) { 'Visible' } else { 'Collapsed' }
}

function Invoke-Refresh([switch]$Rescan, [string]$SelectId) {
    $selId = if ($SelectId) { $SelectId } elseif ($U.ItemList.SelectedItem) { $U.ItemList.SelectedItem.Id } else { $null }
    $sv = Find-VisualChild $U.ItemList ([System.Windows.Controls.ScrollViewer])
    $offset = if ($sv) { $sv.VerticalOffset } else { 0 }

    if ($Rescan) {
        $Window.Cursor = [System.Windows.Input.Cursors]::Wait
        try { Invoke-Scan } finally { $Window.Cursor = $null }
    }
    Update-View

    if ($selId) {
        $match = $App.View | Where-Object { $_.Id -eq $selId } | Select-Object -First 1
        if ($match) { $U.ItemList.SelectedItem = $match }
    }
    if ($sv) {
        $U.ItemList.UpdateLayout()
        $sv.ScrollToVerticalOffset($offset)
    }
    if ($SelectId -and $U.ItemList.SelectedItem) { $U.ItemList.ScrollIntoView($U.ItemList.SelectedItem) }
    Update-Detail
}
