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
