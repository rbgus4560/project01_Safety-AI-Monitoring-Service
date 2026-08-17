param(
    [Parameter(Mandatory = $true)]
    [string]$Root
)

try {
    $resolvedRoot = (Resolve-Path -LiteralPath $Root).Path.TrimEnd('\')
} catch {
    exit 0
}

try {
    $substLines = subst 2>$null
} catch {
    exit 0
}

foreach ($line in $substLines) {
    if ($line -match '^([A-Z]:)\\:\s*=>\s*(.+)$') {
        $drive = $matches[1]
        $target = $matches[2].TrimEnd('\')
        if ($target -ieq $resolvedRoot) {
            cmd /c "subst $drive /D" | Out-Null
        }
    }
}
