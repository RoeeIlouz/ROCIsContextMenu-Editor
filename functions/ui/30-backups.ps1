# ------------------------------------------------------------------------------
# Backups view
# ------------------------------------------------------------------------------
function Update-Backups {
    $list = @(Get-Backups)
    $U.BackupList.ItemsSource = $list
    $U.BackupsEmpty.Visibility = if ($list.Count) { 'Collapsed' } else { 'Visible' }
    $U.TxtSubtitle.Text = "$($NavText.backups[1])  /  $($list.Count) file$(if ($list.Count -ne 1) { 's' })"
    ($NavEntries | Where-Object Id -eq 'backups').Count = [string]$list.Count
}

function Invoke-RestoreBackup($Rec) {
    if (-not $Rec) { return }
    if ($Rec.IsFull) {
        $text = 'Adds back every entry in this file. Entries created since are kept and nothing is deleted. A full backup of the current state is saved first.'
    } else {
        $text = "Puts `"$($Rec.Name)`" back exactly as it was ($($Rec.WhenText)). If it exists now, the current version is backed up and then replaced."
    }
    $r = Show-Message -Title "Restore `"$($Rec.Name)`"?" -Text $text -Buttons @('Cancel', 'Restore') -Primary 'Restore'
    if ($r -ne 'Restore') { return }

    # Keys that don't exist yet are what Undo has to delete again.
    $created = @()
    foreach ($root in $Rec.Roots) {
        $p = Split-RegPath $root
        if (-not $p) { continue }
        $k = (Get-HiveRoot $p.Hive).OpenSubKey($p.SubPath)
        if ($k) { $k.Close() } else { $created += $p }
    }
    $pre = [System.Collections.Generic.List[string]]::new()
    $ok = Invoke-Write $(if ($Rec.NeedsAdmin) { 'HKLM' } else { 'HKCU' }) {
        if ($Rec.IsFull) {
            [void](Export-FullBackup)
            [void](Restore-BackupFile $Rec.File -Merge)
        } else {
            $pre.AddRange([string[]](Restore-BackupFile $Rec.File))
        }
    }
    if ($ok) {
        Set-Status "Restored `"$($Rec.Name)`"."
        $touchesExt = [bool]($Rec.Roots | Where-Object { $_ -match '\\shellex\\|Shell Extensions' })
        if ($touchesExt) { Set-PendingRestart }
        if (-not $Rec.IsFull -and $Rec.Roots.Count) {
            Set-Undo @{ Type = 'restore'; Files = $pre.ToArray(); DeletePaths = $created; NeedsAdmin = $Rec.NeedsAdmin
                        Pending = $touchesExt; Label = "restore of $($Rec.Name)" }
        }
    }
    Invoke-Scan
    Update-View
    Update-Backups
}

function Invoke-DeleteBackupFile($Rec) {
    if (-not $Rec) { return }
    $r = Show-Message -Title 'Delete this backup file?' -Text "$($Rec.FileName)`n`nThe registry is not changed; only the .reg file is removed." `
        -Buttons @('Cancel', 'Delete file') -Primary 'Delete file' -Danger
    if ($r -ne 'Delete file') { return }
    Remove-Item -LiteralPath $Rec.File -Recurse -Force -ErrorAction SilentlyContinue
    Update-Backups
}
