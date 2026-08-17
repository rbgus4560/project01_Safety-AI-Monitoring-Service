param(
    [Parameter(Mandatory = $true)]
    [string]$Link
)

if (-not (Test-Path -LiteralPath $Link)) {
    exit 0
}

try {
    $item = Get-Item -LiteralPath $Link -Force
} catch {
    exit 0
}

if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
    cmd /c "rmdir `"$Link`"" | Out-Null
    exit $LASTEXITCODE
}

Write-Error "Build link path exists but is not a junction/reparse point: $Link"
exit 1
