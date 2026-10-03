# ------------------------------------------------------------------------------
# Undo: one level, shown as a button in the status bar after each change.
# 'toggle' records flip a switch back; 'restore' records delete what the change created
# and re-import the backups taken before it.
# ------------------------------------------------------------------------------
function Set-Undo([hashtable]$Record) {
    $App.Undo = $Record
    $U.BtnUndo.Visibility = if ($Record) { 'Visible' } else { 'Collapsed' }
    $U.BtnUndo.ToolTip = if ($Record) { "Undo: $($Record.Label)" } else { $null }
}

function Get-IdPath([string]$Id) {
    # "cmd|HKCU|Software\Classes\...\shell\Key" -> @{ Hive; SubPath }
    $parts = $Id.Split('|', 3)
    return @{ Hive = $parts[1]; SubPath = $parts[2] }
}

function Invoke-Undo {
    $r = $App.Undo
    if (-not $r) { return }
    Set-Undo $null
    if ($r.Type -eq 'tweaks') {
        Invoke-Tweaks $r.Ids -Undo:$r.Revert -NoUndo
        Set-Status "Undone: $($r.Label)."
        return
    }
    if ($r.Type -eq 'toggle') {
        Invoke-Scan
        $items = foreach ($t in $r.Items) { $App.Items | Where-Object { $_.Id -eq $t.Id } | Select-Object -First 1 }
        $states = @{}
        foreach ($t in $r.Items) { $states[$t.Id] = $t.Enable }
        Invoke-SetEnabled @($items | Where-Object { $_ }) $states -NoUndo
        Set-Status "Undone: $($r.Label)."
        return
    }
    $needsAdmin = [bool]($r.DeletePaths | Where-Object { $_.Hive -eq 'HKLM' }) -or $r.NeedsAdmin
    $ok = Invoke-Write $(if ($needsAdmin) { 'HKLM' } else { 'HKCU' }) {
        foreach ($d in $r.DeletePaths) { Remove-RegTree $d.Hive $d.SubPath }
        foreach ($m in $r.Moves) { if (Test-Path -LiteralPath $m.To) { Move-Item -LiteralPath $m.To -Destination $m.From -Force } }
        foreach ($f in $r.DeleteFiles) { Remove-Item -LiteralPath $f -Recurse -Force -ErrorAction SilentlyContinue }
        foreach ($f in $r.Files) { [void](Restore-BackupFile $f) }
    }
    if ($ok) {
        Set-Status "Undone: $($r.Label)."
        if ($r.Pending) { Set-PendingRestart }
    }
    Invoke-Refresh -Rescan
    if ($App.Nav -eq 'backups') { Update-Backups }
}

# Turns entries on or off. $Enable is a bool for all of them, or a hashtable Id -> bool (used by Undo).
# All-users entries are skipped (with an offer to restart as admin) when not elevated; the rest still apply.
function Invoke-SetEnabled([object[]]$Items, $Enable, [switch]$NoUndo) {
    $Items = @($Items | Where-Object { $_ })
    if (-not $Items) { return }
    $want = { param($it) if ($Enable -is [hashtable]) { [bool]$Enable[$it.Id] } else { [bool]$Enable } }
    $todo = @($Items | Where-Object { $App.IsAdmin -or (Get-RequiredHive $_ (& $want $_)) -ne 'HKLM' })
    $skipped = $Items.Count - $todo.Count
    $done = [System.Collections.Generic.List[object]]::new()
    $ok = Invoke-Write 'HKCU' {
        foreach ($it in $todo) {
            $on = & $want $it
            Set-EntryEnabled $it $on
            $done.Add(@{ Id = $it.Id; Enable = -not $on })
        }
    }
    if ($done.Count) {
        $first = $todo[0]
        $verb = if (& $want $first) { 'turned on' } else { 'turned off' }
        $label = if ($done.Count -eq 1) { "$($first.Name) $verb" } else { "$($done.Count) entries changed" }
        Set-Status "$label."
        if ($todo | Where-Object { $_.Kind -notin 'Command', 'SendTo' }) { Set-PendingRestart }
        if (-not $NoUndo) { Set-Undo @{ Type = 'toggle'; Items = $done.ToArray(); Label = $label } }
    }
    Invoke-Refresh -Rescan
    if ($skipped) { [void](Invoke-Write 'HKLM' {}) }
}

function Invoke-Toggle($Item, [bool]$Enable, [switch]$NoUndo) {
    if (-not $Item) { return }
    Invoke-SetEnabled @($Item) $Enable -NoUndo:$NoUndo
}

function Invoke-Delete([object[]]$Items) {
    $Items = @($Items | Where-Object { $_ -and $_.CanDelete })
    if (-not $Items) { return }
    $one = $Items[0]
    if ($Items.Count -eq 1) {
        $text = if ($one.Kind -eq 'Extension') {
            'This shell extension is broken, so only its leftover registration is removed. A .reg backup is saved first.'
        } elseif ($one.Kind -eq 'SendTo') {
            'The shortcut is moved to the Backups folder, so you can undo or restore it.'
        } elseif ($one.Submenu -and $one.Children) {
            "The submenu and the $($one.Children) command$(if ($one.Children -ne 1) { 's' }) inside it are removed. A .reg backup is saved first, and you can undo or restore it from Backups."
        } else {
            'The registry key is removed. A .reg backup is saved first, and you can undo or restore it from Backups.'
        }
        $verb = if ($one.Broken) { 'Remove' } else { 'Delete' }
        $title = "$verb `"$($one.Name)`"?"
    } else {
        $list = ($Items | Select-Object -First 8 | ForEach-Object { "  $($_.Name)" }) -join "`n"
        if ($Items.Count -gt 8) { $list += "`n  ...and $($Items.Count - 8) more" }
        $text = "$list`n`nEach one is backed up first, so this can be undone."
        $verb = 'Delete'
        $title = "Delete $($Items.Count) entries?"
    }
    $r = Show-Message -Title $title -Text $text -Buttons @('Cancel', $verb) -Primary $verb -Danger
    if ($r -ne $verb) { return }

    $todo = @($Items | Where-Object { $App.IsAdmin -or $_.Hive -ne 'HKLM' })
    $skipped = $Items.Count - $todo.Count
    $files = [System.Collections.Generic.List[string]]::new()
    $ok = Invoke-Write 'HKCU' { foreach ($it in $todo) { $files.AddRange([string[]](Remove-MenuEntry $it)) } }
    if ($files.Count) {
        $label = if ($todo.Count -eq 1) { "deleted $($todo[0].Name)" } else { "deleted $($todo.Count) entries" }
        Set-Status "$($label.Substring(0,1).ToUpper())$($label.Substring(1)). Backup saved."
        $pending = [bool]($todo | Where-Object { $_.Kind -notin 'Command', 'SendTo' })
        Set-Undo @{ Type = 'restore'; Files = $files.ToArray(); DeletePaths = @(); NeedsAdmin = [bool]($todo | Where-Object Hive -eq 'HKLM')
                    Pending = $pending; Label = $label }
        if ($pending) { Set-PendingRestart }
    }
    Invoke-Refresh -Rescan
    if ($skipped) { [void](Invoke-Write 'HKLM' {}) }
}

function Invoke-CleanupBroken {
    $items = @($App.Items | Where-Object { $_.Broken -and $_.CanDelete })
    if (-not $items) { return }
    $list = ($items | Select-Object -First 8 | ForEach-Object { "  $($_.Name)" }) -join "`n"
    if ($items.Count -gt 8) { $list += "`n  ...and $($items.Count - 8) more" }
    $r = Show-Message -Title "Remove $($items.Count) broken entr$(if ($items.Count -eq 1) { 'y' } else { 'ies' })?" `
        -Text "These point to programs that are no longer installed:`n$list`n`nEach one is backed up first, so this can be undone." `
        -Buttons @('Cancel', 'Remove all') -Primary 'Remove all' -Danger
    if ($r -ne 'Remove all') { return }

    # Per-user ones never need admin; all-users ones only when we have it.
    $doable = @($items | Where-Object { $App.IsAdmin -or $_.Hive -ne 'HKLM' })
    $skipped = $items.Count - $doable.Count
    $files = [System.Collections.Generic.List[string]]::new()
    $ok = Invoke-Write 'HKCU' { foreach ($it in $doable) { $files.AddRange([string[]](Remove-MenuEntry $it)) } }
    if ($ok -and $doable.Count) {
        Set-Status "Removed $($doable.Count) broken entr$(if ($doable.Count -eq 1) { 'y' } else { 'ies' }). Backups saved."
        Set-Undo @{ Type = 'restore'; Files = $files.ToArray(); DeletePaths = @(); NeedsAdmin = [bool]($doable | Where-Object Hive -eq 'HKLM')
                    Pending = [bool]($doable | Where-Object Kind -ne 'Command'); Label = 'broken entry cleanup' }
        if ($doable | Where-Object Kind -ne 'Command') { Set-PendingRestart }
    }
    Invoke-Refresh -Rescan
    if ($skipped) { [void](Invoke-Write 'HKLM' {}) }
}
