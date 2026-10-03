# ------------------------------------------------------------------------------
# About dialog: version, the launch command, where things live, and links.
# ------------------------------------------------------------------------------
function Show-About {
    $w = New-Window $AboutXaml
    if ($Window -and $Window.IsLoaded) { $w.Owner = $Window }
    $w.FindName('AboutIcon').Source = Get-AssetImage 'app-icon-64.png'
    $w.FindName('AboutWordmark').Source = Get-AssetImage 'wordmark.png'
    $w.FindName('AboutVersion').Text = "Version $AppVersion"
    $w.FindName('AboutLaunch').Text = $AppLaunchCommand

    $copy = $w.FindName('AboutCopy')
    $copy.Add_Click({
        try { [System.Windows.Clipboard]::SetText($AppLaunchCommand); $copy.Content = 'Copied' } catch {}
    })

    $ps = "$($PSVersionTable.PSVersion.Major).$($PSVersionTable.PSVersion.Minor)" + $(if ($PSVersionTable.PSEdition -eq 'Core') { '' } else { ' (Windows PowerShell)' })
    $facts = [ordered]@{
        'Running from' = $(if ($App.ScriptPath) { $App.ScriptPath } else { 'Downloaded with the launch command' })
        'Backups'      = $App.BackupDir
        'Running as'   = $(if ($App.IsAdmin) { 'Administrator' } else { 'Standard user' })
        'PowerShell'   = $ps
        'Windows'      = "Build $([Environment]::OSVersion.Version.Build)"
    }
    $grid = $w.FindName('AboutFacts')
    $row = 0
    foreach ($k in $facts.Keys) {
        $grid.RowDefinitions.Add([System.Windows.Controls.RowDefinition]::new())
        $label = [System.Windows.Controls.TextBlock]::new()
        $label.Text = $k; $label.Foreground = $w.FindResource('Faint'); $label.Margin = '0,3,12,3'
        $value = [System.Windows.Controls.TextBox]::new()
        $value.Style = $w.FindResource('ReadOnlyText'); $value.Text = $facts[$k]; $value.Margin = '0,3,0,3'
        [System.Windows.Controls.Grid]::SetRow($label, $row); [System.Windows.Controls.Grid]::SetRow($value, $row)
        [System.Windows.Controls.Grid]::SetColumn($value, 1)
        [void]$grid.Children.Add($label); [void]$grid.Children.Add($value)
        $row++
    }

    $w.FindName('AboutSource').Add_Click({ Start-Process $AppRepoUrl })
    $w.FindName('AboutSite').Add_Click({ Start-Process $AppSiteUrl })
    $w.FindName('AboutClose').Add_Click({ $w.Close() })
    [void]$w.ShowDialog()
}
