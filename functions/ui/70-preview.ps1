# ==============================================================================
# MENU PREVIEW PAGE
# ==============================================================================
# Columns cascade like the real menu: the root menu, then the submenu of the selected row, and so on.
# $App.PvPath remembers which row is open in each column so a re-read (after a move) reopens them.
$Pv = @{ Columns = [System.Collections.Generic.List[object]]::new(); Path = @(); Selected = $null; Drag = $null; DragRow = $null; Hint = ''; Pending = $null }

function Initialize-PreviewPage {
    $U.PreviewTargets.ItemsSource = @(foreach ($k in $PreviewTargets.Keys) {
        $label = if ($k -eq 'file') { "File ($($App.Ext))" } else { $PreviewTargets[$k].Label }
        [pscustomobject]@{ Id = $k; Label = $label; Checked = $k -eq $App.PreviewTarget }
    })
}

# Identifies a row across re-reads. Not by entry Id: moving a command renames its key, which changes its Id.
function Get-RowKey($Row) { return "$(if ($Row.Entry) { $Row.Entry.Kind })|$($Row.Text)" }

function Update-Preview {
    $Window.Cursor = [System.Windows.Input.Cursors]::Wait
    try {
        $App.Preview = Get-MenuPreview $App.PreviewTarget $App.PreviewShift
        $U.PreviewError.Visibility = 'Collapsed'
        $U.PreviewScroll.Visibility = 'Visible'
    } catch {
        $App.Preview = $null
        $U.PreviewError.Visibility = 'Visible'
        $U.PreviewScroll.Visibility = 'Collapsed'
        $U.TxtPreviewError.Text = $_.Exception.Message
        return
    } finally { $Window.Cursor = $null }

    $s = $App.Preview.Subject
    $U.TxtPreviewSubject.Text = "Right-click on: $($s.Label)" + $(if ($App.PreviewShift) { '   (with Shift)' } else { '' })
    $U.TxtSubtitle.Text = "$($NavText.preview[1])  /  $($PreviewTargets[$App.PreviewTarget].Label)"

    # Rebuild the cascade, reopening the same submenus and selection as before.
    $selKey = if ($Pv.Selected) { Get-RowKey $Pv.Selected } else { $null }
    $path = $Pv.Path
    $U.PreviewColumns.Children.Clear()
    $Pv.Columns.Clear()
    $Pv.Selected = $null
    [void](Add-PreviewColumn $App.Preview.Rows 0)
    # Selecting a row with a submenu opens the next column (Select-PreviewRow), so walk down the old path.
    for ($level = 0; $level -lt $Pv.Columns.Count; $level++) {
        $col = $Pv.Columns[$level]
        $key = if ($level -lt $path.Count) { $path[$level] } else { $selKey }
        $hit = if ($key) { $col.Rows | Where-Object { -not $_.Separator -and (Get-RowKey $_) -eq $key } | Select-Object -First 1 } else { $null }
        if (-not $hit) { break }
        $col.List.SelectedItem = $hit
    }
    if (-not $Pv.Selected) { Update-PreviewDetail }
    Update-PreviewOff
}

function Add-PreviewColumn([object[]]$Rows, [int]$Level) {
    $grid = [System.Windows.Controls.Grid]::new()
    $grid.VerticalAlignment = 'Top'
    $grid.Margin = [System.Windows.Thickness]::new($(if ($Level) { 4 } else { 0 }), 0, 0, 0)

    $border = [System.Windows.Controls.Border]::new()
    $border.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#2B2C30')
    $border.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#45474D')
    $border.BorderThickness = [System.Windows.Thickness]::new(1)
    $border.CornerRadius = [System.Windows.CornerRadius]::new(8)
    $border.Padding = [System.Windows.Thickness]::new(4)
    $border.Width = 300
    $shadow = [System.Windows.Media.Effects.DropShadowEffect]::new()
    $shadow.BlurRadius = 18; $shadow.ShadowDepth = 4; $shadow.Opacity = 0.45; $shadow.Direction = 270
    $border.Effect = $shadow

    $lb = [System.Windows.Controls.ListBox]::new()
    $lb.Background = [System.Windows.Media.Brushes]::Transparent
    $lb.BorderThickness = [System.Windows.Thickness]::new(0)
    $lb.ItemContainerStyle = $Window.FindResource('MenuRowItem')
    $lb.ItemTemplate = $Window.FindResource('MenuRowTemplate')
    [System.Windows.Controls.ScrollViewer]::SetHorizontalScrollBarVisibility($lb, 'Disabled')
    [System.Windows.Controls.ScrollViewer]::SetVerticalScrollBarVisibility($lb, 'Disabled')
    $lb.AllowDrop = $true
    $lb.Tag = $Level
    $lb.ItemsSource = $Rows
    $border.Child = $lb

    # Drop indicator, drawn over the list without taking clicks.
    $canvas = [System.Windows.Controls.Canvas]::new()
    $canvas.IsHitTestVisible = $false
    $line = [System.Windows.Controls.Border]::new()
    $line.Height = 2; $line.Width = 284
    $line.CornerRadius = [System.Windows.CornerRadius]::new(1)
    $line.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#4CA3FF')
    $line.Visibility = 'Collapsed'
    [System.Windows.Controls.Canvas]::SetLeft($line, 8)
    [void]$canvas.Children.Add($line)

    [void]$grid.Children.Add($border)
    [void]$grid.Children.Add($canvas)

    $lb.Add_SelectionChanged({ param($s, $e) Select-PreviewRow ([int]$s.Tag) $s.SelectedItem })
    $lb.Add_PreviewMouseLeftButtonDown({ param($s, $e) Start-PreviewDrag $s $e })
    $lb.Add_PreviewMouseMove({ param($s, $e) Move-PreviewDrag $s $e })
    $lb.Add_DragOver({ param($s, $e) Test-PreviewDrop $s $e })
    $lb.Add_DragLeave({ param($s, $e) Hide-PreviewDropLine $s })
    $lb.Add_Drop({ param($s, $e) Complete-PreviewDrop $s $e })

    $col = @{ Level = $Level; Rows = $Rows; List = $lb; Grid = $grid; Line = $line }
    $Pv.Columns.Add($col)
    [void]$U.PreviewColumns.Children.Add($grid)
    return $col
}

function Select-PreviewRow([int]$Level, $Row) {
    # Close deeper columns; a row with a submenu opens the next one, lined up with the row like a real menu.
    while ($Pv.Columns.Count -gt $Level + 1) {
        $Pv.Columns.RemoveAt($Pv.Columns.Count - 1)
        $U.PreviewColumns.Children.RemoveAt($U.PreviewColumns.Children.Count - 1)
    }
    if (-not $Row) { return }
    $Pv.Selected = $Row
    $Pv.Path = @(for ($i = 0; $i -le $Level; $i++) { $sel = $Pv.Columns[$i].List.SelectedItem; if ($sel) { Get-RowKey $sel } })
    if ($Row.HasChildren) {
        $parentCol = $Pv.Columns[$Level]
        $child = Add-PreviewColumn $Row.Children ($Level + 1)
        $parentCol.List.UpdateLayout()
        $c = $parentCol.List.ItemContainerGenerator.ContainerFromItem($Row)
        if ($c) {
            $y = $c.TranslatePoint([System.Windows.Point]::new(0, 0), $parentCol.Grid).Y + $parentCol.Grid.Margin.Top - 5
            $child.Grid.Margin = [System.Windows.Thickness]::new(4, [Math]::Max(0, $y), 0, 0)
        }
    }
    Update-PreviewDetail
}

function Update-PreviewDetail {
    $row = $Pv.Selected
    if (-not $row -or $row.Separator) {
        $U.PvHelp.Visibility = 'Visible'; $U.PvDetail.Visibility = 'Collapsed'
        return
    }
    $U.PvHelp.Visibility = 'Collapsed'; $U.PvDetail.Visibility = 'Visible'
    $e = $row.Entry
    $U.PvName.Text = $row.Text
    $U.PvIcon.Source = $row.IconImage
    $U.PvKind.Text = if ($e) { $e.KindLabel + $(if ($e.LocLabel) { "  /  $($e.LocLabel)" } else { '' }) } elseif ($row.Synthetic) { 'Folder window' } else { 'Windows' }
    if ($row.Movable) {
        $U.PvMoveTitle.Text = 'Drag it to move it'
        $U.PvMoveText.Text = $row.Source
        $U.PvMoveBox.Background = $Window.FindResource('Bg')
    } else {
        $U.PvMoveTitle.Text = 'Placed by Windows'
        $U.PvMoveText.Text = $row.Lock
        $U.PvMoveBox.Background = $Window.FindResource('Bg')
    }
    $canToggle = [bool]$e
    $U.PvToggleRow.Visibility = if ($canToggle) { 'Visible' } else { 'Collapsed' }
    if ($canToggle) { $U.PvSwitch.IsChecked = $e.Enabled }

    $isTopCmd = $e -and $e.Kind -eq 'Command' -and -not $e.ParentName -and $e.CanEdit -and -not $SystemVerbs.Contains($e.KeyName)
    $U.BtnPvEdit.Visibility = if ($e -and $e.CanEdit) { 'Visible' } else { 'Collapsed' }
    $U.BtnPvTop.Visibility = if ($isTopCmd -and $e.Position -ne 'Top') { 'Visible' } else { 'Collapsed' }
    $U.BtnPvBottom.Visibility = if ($isTopCmd -and $e.Position -ne 'Bottom') { 'Visible' } else { 'Collapsed' }
    $U.BtnPvUnpin.Visibility = if ($isTopCmd -and $e.Position) { 'Visible' } else { 'Collapsed' }
    $U.BtnPvReset.Visibility = if ($e -and $e.OrigKey -and $e.Kind -in 'Command', 'Extension') { 'Visible' } else { 'Collapsed' }
    $U.BtnPvResetSendTo.Visibility = if ($row.Group -like 'sendto|*') { 'Visible' } else { 'Collapsed' }
}

function Update-PreviewOff {
    $off = if ($App.Preview) { @($App.Preview.Off) } else { @() }
    $U.PvOffList.ItemsSource = $off
    $U.TxtPvOff.Text = if ($off.Count) { "Turned off here ($($off.Count))" } else { 'Turned off here' }
    $U.TxtPvOffEmpty.Visibility = if ($off.Count) { 'Collapsed' } else { 'Visible' }
}

# ------------------------------------------------------------------------------
# Drag and drop
# ------------------------------------------------------------------------------
function Get-PreviewRowAt($List, $Source) {
    if (-not ($Source -is [System.Windows.DependencyObject])) { return $null }
    $c = [System.Windows.Controls.ItemsControl]::ContainerFromElement($List, $Source)
    if ($c) { return @{ Row = $c.DataContext; Container = $c } }
    return $null
}

function Start-PreviewDrag($List, $E) {
    $hit = Get-PreviewRowAt $List $E.OriginalSource
    $Pv.Drag = if ($hit -and $hit.Row.Movable) { @{ Row = $hit.Row; Start = $E.GetPosition($List); List = $List } } else { $null }
}

function Move-PreviewDrag($List, $E) {
    $d = $Pv.Drag
    if (-not $d -or $E.LeftButton -ne 'Pressed' -or $d.List -ne $List) { return }
    $p = $E.GetPosition($List)
    if ([Math]::Abs($p.Y - $d.Start.Y) -lt 6 -and [Math]::Abs($p.X - $d.Start.X) -lt 6) { return }
    $Pv.Drag = $null
    $Pv.DragRow = $d.Row
    $Pv.Hint = ''
    try { [void][System.Windows.DragDrop]::DoDragDrop($List, 'cme-preview-row', [System.Windows.DragDropEffects]::Move) }
    finally {
        $Pv.DragRow = $null
        foreach ($c in $Pv.Columns) { $c.Line.Visibility = 'Collapsed' }
    }
}

function Hide-PreviewDropLine($List) {
    foreach ($c in $Pv.Columns) { if ($c.List -eq $List) { $c.Line.Visibility = 'Collapsed' } }
}

# Works out where a drop would land: @{ Target; After; Container } or $null, with the reason in $Pv.Hint.
function Get-PreviewDropSpot($List, $E) {
    $row = $Pv.DragRow
    $hit = Get-PreviewRowAt $List $E.OriginalSource
    if (-not $row -or -not $hit -or $hit.Row.Separator) { return $null }
    $target = $hit.Row
    if ($target -eq $row) { $Pv.Hint = ''; return $null }
    if ($target.Group -ne $row.Group -or -not ($List.ItemsSource -contains $row)) {
        $Pv.Hint = if (-not $target.Movable) { "Can't go there: $($target.Text) is placed by Windows. $($row.Source)" } else { "Can't go there. $($row.Source)" }
        return $null
    }
    $after = $E.GetPosition($hit.Container).Y -gt ($hit.Container.ActualHeight / 2)
    return @{ Target = $target; After = $after; Container = $hit.Container }
}

function Test-PreviewDrop($List, $E) {
    $E.Handled = $true
    $spot = Get-PreviewDropSpot $List $E
    $col = $Pv.Columns | Where-Object { $_.List -eq $List } | Select-Object -First 1
    if (-not $spot) {
        $E.Effects = [System.Windows.DragDropEffects]::None
        if ($col) { $col.Line.Visibility = 'Collapsed' }
        if ($Pv.Hint) { Set-Status $Pv.Hint }
        return
    }
    $E.Effects = [System.Windows.DragDropEffects]::Move
    Set-Status "Drop to move $($Pv.DragRow.Text) $(if ($spot.After) { 'below' } else { 'above' }) $($spot.Target.Text)."
    if ($col) {
        $y = $spot.Container.TranslatePoint([System.Windows.Point]::new(0, 0), $col.Grid).Y
        if ($spot.After) { $y += $spot.Container.ActualHeight }
        [System.Windows.Controls.Canvas]::SetTop($col.Line, $y)
        $col.Line.Visibility = 'Visible'
    }
}

function Complete-PreviewDrop($List, $E) {
    $E.Handled = $true
    $spot = Get-PreviewDropSpot $List $E
    Hide-PreviewDropLine $List
    $row = $Pv.DragRow
    if (-not $spot -or -not $row) { return }

    $siblings = @($List.ItemsSource)
    $group = @($siblings | Where-Object { $_.Group -eq $row.Group })
    $order = [System.Collections.Generic.List[object]]::new()
    foreach ($r in $group) { if ($r -ne $row) { $order.Add($r) } }
    $at = $order.IndexOf($spot.Target)
    if ($spot.After) { $at++ }
    $order.Insert($at, $row)
    if ((@($group | ForEach-Object { Get-RowKey $_ }) -join "`n") -eq (@($order | ForEach-Object { Get-RowKey $_ }) -join "`n")) { return }   # same place
    # Write once the drag operation has fully ended.
    $Pv.Pending = @{ Row = $row; Order = $order.ToArray() }
    [void]$Window.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, [Action]{
        $p = $Pv.Pending; $Pv.Pending = $null
        if ($p) { Invoke-PreviewMove $p.Row $p.Order }
    })
}

function Invoke-PreviewMove($Row, [object[]]$Order) {
    $hive = if ($Row.Group -like 'sendto|*') { 'HKCU' } else { $Row.Entry.Hive }
    $res = @{}
    $ok = Invoke-Write $hive { $res.R = Move-MenuRow $Row $Order }
    if (-not $ok -or -not $res.R) { return }
    Set-Undo $res.R.Undo
    $Pv.Selected = $Row
    Invoke-Scan
    Update-Preview

    # Check the result against what Windows now builds.
    $col = $Pv.Columns | Where-Object { $_.Rows | Where-Object { (Get-RowKey $_) -eq (Get-RowKey $Row) } } | Select-Object -First 1
    $want = @($Order | ForEach-Object { Get-RowKey $_ })
    $got = if ($col) { @($col.Rows | Where-Object { $want -contains (Get-RowKey $_) } | ForEach-Object { Get-RowKey $_ }) } else { @() }
    if ($Row.Group -like 'sendto|*') {
        Set-Status "Moved $($Row.Text). If Explorer still shows the old Send to order, restart Explorer."
        Set-PendingRestart
    } elseif (($want -join "`n") -eq ($got -join "`n")) {
        Set-Status "Moved $($Row.Text). Right-click to see it; no restart needed."
    } else {
        Set-Status "Saved, but Windows kept its own order for $($Row.Text). Undo puts the key name back."
    }
}

# ------------------------------------------------------------------------------
# Detail panel actions
# ------------------------------------------------------------------------------
function Invoke-PreviewPin([string]$Position) {
    $e = $Pv.Selected.Entry
    if (-not $e) { return }
    $res = @{}
    $ok = Invoke-Write $e.Hive {
        $backup = Backup-RegKey $e.Hive $e.SubPath "position_$($e.KeyName)"
        $k = (Get-HiveRoot $e.Hive).OpenSubKey($e.SubPath, $true)
        if (-not $k) { throw "Registry key no longer exists: $($e.SubPath)" }
        try { if ($Position) { $k.SetValue('Position', $Position) } else { $k.DeleteValue('Position', $false) } } finally { $k.Close() }
        $res.Files = @($backup | Where-Object { $_ })
    }
    if (-not $ok) { return }
    $what = if ($Position) { "pinned $($e.Name) to the $($Position.ToLower())" } else { "unpinned $($e.Name)" }
    Set-Undo @{ Type = 'restore'; Files = $res.Files; DeletePaths = @(); NeedsAdmin = $e.Hive -eq 'HKLM'; Label = $what }
    Set-Status "$($what.Substring(0,1).ToUpper())$($what.Substring(1))."
    Invoke-Refresh -Rescan
}

function Invoke-PreviewReset {
    $row = $Pv.Selected
    $e = $row.Entry
    if (-not $e) { return }
    $path = if ($e.Kind -eq 'Extension') { $row.HandlerPath } else { $e.SubPath }
    if (-not $path) { return }
    $res = @{}
    $ok = Invoke-Write $e.Hive { $res.R = Reset-MenuOrder $e $path }
    if ($ok -and $res.R) {
        Set-Undo $res.R
        Set-Status "$($e.Name) is back in its original place."
        Invoke-Refresh -Rescan
    }
}

function Invoke-PreviewResetSendTo {
    $u = $null
    try { $u = Reset-SendToOrder (Get-SendToDir) } catch { [void](Show-Message -Title 'Could not reset the order' -Text $_.Exception.Message); return }
    if ($u) {
        Set-Undo $u
        Set-Status 'Send to is back in alphabetical order. Restart Explorer if it still shows the old one.'
        Set-PendingRestart
    } else {
        Set-Status 'Send to is already in its own order.'
    }
    Invoke-Refresh -Rescan
}

# ------------------------------------------------------------------------------
# "Other places" chips
# ------------------------------------------------------------------------------
function Initialize-MorePlaces {
    $U.MoreBar.ItemsSource = @(foreach ($k in $MorePlaces.Keys) { [pscustomobject]@{ Id = $k; Label = $MorePlaces[$k]; Checked = $k -eq $App.MorePlace } })
}

function Test-InMorePlaces($Item) { return @($Item.LocIds | Where-Object { $MorePlaces.Contains($_) }).Count -gt 0 }
