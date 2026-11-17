# ==============================================================================
# TEXT HELPERS
# ==============================================================================
function Resolve-MenuText([string]$Raw) {
    if ([string]::IsNullOrWhiteSpace($Raw)) { return '' }
    $t = $Raw.Trim()
    if ($t.StartsWith('@')) {
        $t = [CME.Native]::LoadIndirect($t)
        if (-not $t) { return '' }
    }
    # Strip keyboard accelerators: "Open w&ith" -> "Open with", "A && B" -> "A & B"
    $t = $t.Replace('&&', [string][char]1).Replace('&', '').Replace([string][char]1, '&')
    return $t.Trim()
}

function Format-Identifier([string]$Id) {
    $t = $Id -replace '^[\d_]+', '' -replace '[_\.]+', ' '
    $t = [regex]::Replace($t, '(?<=[a-z0-9])(?=[A-Z])', ' ')
    $t = [regex]::Replace($t, '(?<=[A-Z])(?=[A-Z][a-z])', ' ')
    return $t.Trim()
}

function ConvertTo-Clsid([string]$Text) {
    if (-not $Text) { return $null }
    $m = [regex]::Match($Text, '[0-9A-Fa-f]{8}-(?:[0-9A-Fa-f]{4}-){3}[0-9A-Fa-f]{12}')
    if ($m.Success) { return '{' + $m.Value.ToUpperInvariant() + '}' }
    return $null
}

function ConvertTo-KeyName([string]$Name) {
    $k = $Name -replace '[^A-Za-z0-9]', ''
    if (-not $k) { $k = 'CustomCommand' }
    return $k
}

# Send to sorts its items by display name. Leading zero-width spaces sort before any letter and
# don't show, so they are how a custom order is kept (see Set-SendToOrder).
$SortMark = [string][char]0x200B
function Remove-SortPrefix([string]$Text) { if ($Text) { return $Text.TrimStart([char]0x200B) } return $Text }

# A short uppercase key that sorts strictly between $Low and $High (either may be empty for "no bound"),
# comparing case-insensitively the way Explorer orders verb and handler keys. The result is never a
# prefix of $High, so anything appended to it still sorts before $High. $null when there is no room.
function Get-KeyBetween([string]$Low, [string]$High) {
    $alpha = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ'.ToCharArray()
    $L = ([string]$Low).ToUpperInvariant()
    $H = if ($High) { $High.ToUpperInvariant() } else { $null }
    $sb = [Text.StringBuilder]::new()
    for ($i = 0; $i -lt 64; $i++) {
        $lo = if ($i -lt $L.Length) { [int]$L[$i] } else { -1 }
        if ($null -ne $H -and $i -ge $H.Length) { return $null }
        $hi = if ($null -ne $H) { [int]$H[$i] } else { 0x10000 }
        $room = @($alpha | Where-Object { [int]$_ -gt $lo -and [int]$_ -lt $hi })
        if ($room.Count) { return $sb.Append($room[[int][Math]::Floor($room.Count / 2)]).ToString() }
        if ($lo -eq -1) { [void]$sb.Append([char]$hi); continue }    # $Low is used up: follow $High
        [void]$sb.Append([char]$lo)
        if ($lo -lt $hi) { $H = $null }                               # already below $High from here on
    }
    return $null
}
