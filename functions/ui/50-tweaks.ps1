# ------------------------------------------------------------------------------
# Tweaks page: a checklist. Check tweaks (or pick a preset), then "Run tweaks";
# "Undo selected" writes the original values back. Toggle tweaks apply as soon as they're switched.
# ------------------------------------------------------------------------------
function Update-Tweaks {
    $keep = @{}
    foreach ($i in @($U.TweakList.ItemsSource)) { if ($i -and $i.Kind -eq 'check' -and $i.Checked) { $keep[$i.Id] = $true } }

    $items = [System.Collections.Generic.List[object]]::new()
    $last = $null
    $applied = 0
    $defs = Get-TweakDefinitions
    foreach ($t in $defs) {
        if ($t.Category -ne $last) {
            $items.Add([pscustomobject]@{ Kind = 'header'; Id = ''; Title = $t.Category; Desc = ''; Applied = $false; Available = $true; Note = ''; ShowApplied = $false; Checked = $false })
            $last = $t.Category
        }
        $s = Get-TweakState $t
        if ($s.Applied) { $applied++ }
        $items.Add([pscustomobject]@{
            Kind = $(if ($t.IsToggle) { 'toggle' } else { 'check' }); Id = $t.Id; Title = $t.Content; Desc = $t.Description
            Applied = $s.Applied; Available = $s.Available; Note = $s.Note; ShowApplied = $s.Applied -and -not $t.IsToggle
            Checked = $keep.ContainsKey($t.Id) -and $s.Available
        })
    }
    $U.TweakList.ItemsSource = $items
    $U.TweakPresetList.ItemsSource = @((Get-TweakPresets).Keys)
    $U.TxtSubtitle.Text = "$($NavText.tweaks[1])  /  $applied of $($defs.Count) applied"
}

function Get-CheckedTweakIds { return @($U.TweakList.ItemsSource | Where-Object { $_.Kind -eq 'check' -and $_.Checked } | ForEach-Object Id) }

# Checks exactly the given tweaks (presets, Clear).
function Set-TweakChecks([string[]]$Ids) {
    foreach ($i in @($U.TweakList.ItemsSource)) { if ($i.Kind -eq 'check') { $i.Checked = $i.Available -and ($Ids -contains $i.Id) } }
    $U.TweakList.Items.Refresh()
}

# Runs (or with -Undo, reverts) tweaks. Only ones that would change something are touched, so the
# status line and the Undo button describe exactly what happened.
function Invoke-Tweaks([string[]]$Ids, [switch]$Undo, [switch]$NoUndo) {
    $defs = @(Get-TweakDefinitions | Where-Object { $Ids -contains $_.Id })
    if (-not $defs) { Set-Status 'Check the tweaks you want first, or pick a preset.'; return }
    if (-not $App.IsAdmin -and ($defs | Where-Object { Test-TweakNeedsAdmin $_ })) { [void](Invoke-Write 'HKLM' {}); return }

    $todo = @($defs | Where-Object { $s = Get-TweakState $_; $s.Available -and ($s.Applied -eq [bool]$Undo) })
    $skipped = $defs.Count - $todo.Count
    $done = [System.Collections.Generic.List[string]]::new()
    $errors = [System.Collections.Generic.List[string]]::new()
    $Window.Cursor = [System.Windows.Input.Cursors]::Wait
    try {
        foreach ($t in $todo) {
            try { Invoke-Tweak $t -Undo:$Undo; $done.Add($t.Id) }
            catch { $errors.Add("$($t.Content): $($_.Exception.Message)") }
        }
    } finally { $Window.Cursor = $null }

    $verb = if ($Undo) { 'Undid' } else { 'Applied' }
    $msg = "$verb $($done.Count) tweak$(if ($done.Count -ne 1) { 's' })"
    if ($skipped) { $msg += " ($skipped already $(if ($Undo) { 'not applied' } else { 'applied' }) or unavailable)" }
    Set-Status "$msg."
    if ($done.Count) {
        if ($todo | Where-Object { $done -contains $_.Id -and $_.RestartExplorer }) { Set-PendingRestart }
        if (-not $NoUndo) {
            Set-Undo @{ Type = 'tweaks'; Ids = $done.ToArray(); Revert = -not $Undo; Label = "$($verb.ToLower()) $($done.Count) tweak$(if ($done.Count -ne 1) { 's' })" }
        }
    }
    if ($errors.Count) { [void](Show-Message -Title 'Some tweaks did not apply' -Text ($errors -join "`n")) }
    Update-Tweaks
    Invoke-Scan
    Update-View
}
