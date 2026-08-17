param(
  [Parameter(Mandatory = $true)]
  [string]$SettingsPath,

  [Parameter(Mandatory = $true)]
  [string]$RemoteServerUrl
)

$ErrorActionPreference = 'Stop'

function Normalize-Token([string]$Value) {
  $next = $Value.Trim().ToLowerInvariant() -replace '[^a-z0-9]+', '_'
  $next = $next -replace '_+', '_'
  $next = $next.Trim('_')
  if ([string]::IsNullOrWhiteSpace($next)) {
    return 'local'
  }
  return $next
}

function Get-PrimaryMacSuffix {
  try {
    $adapter = Get-NetAdapter -Physical -ErrorAction Stop |
      Where-Object { $_.MacAddress -and $_.Status -ne 'Disabled' } |
      Sort-Object @{ Expression = { if ($_.Status -eq 'Up') { 0 } else { 1 } } }, InterfaceIndex |
      Select-Object -First 1
    if ($adapter -and $adapter.MacAddress) {
      $mac = ($adapter.MacAddress -replace '[^A-Fa-f0-9]', '').ToLowerInvariant()
      if ($mac.Length -ge 6) {
        return $mac.Substring($mac.Length - 6)
      }
    }
  } catch {}

  try {
    $adapter = Get-CimInstance Win32_NetworkAdapterConfiguration -ErrorAction Stop |
      Where-Object { $_.MACAddress } |
      Select-Object -First 1
    if ($adapter -and $adapter.MACAddress) {
      $mac = ($adapter.MACAddress -replace '[^A-Fa-f0-9]', '').ToLowerInvariant()
      if ($mac.Length -ge 6) {
        return $mac.Substring($mac.Length - 6)
      }
    }
  } catch {}

  return ''
}

$settings = @{}
if (Test-Path -LiteralPath $SettingsPath) {
  try {
    $json = Get-Content -LiteralPath $SettingsPath -Raw | ConvertFrom-Json
    foreach ($prop in $json.PSObject.Properties) {
      $settings[$prop.Name] = $prop.Value
    }
  } catch {
    $settings = @{}
  }
}

$hostToken = Normalize-Token ([System.Net.Dns]::GetHostName())
$machineId = "host_$hostToken"
$generatedClientId = "client_$hostToken"

$configuredMachineId = ''
if ($settings.ContainsKey('machine_id') -and $null -ne $settings['machine_id']) {
  $configuredMachineId = [string]$settings['machine_id']
}

$configuredClientId = ''
if ($settings.ContainsKey('client_id') -and $null -ne $settings['client_id']) {
  $configuredClientId = [string]$settings['client_id']
}
$normalizedConfiguredClientId = Normalize-Token $configuredClientId

$forcedClientId = ''
if ($env:SAFETY_MONITOR_CLIENT_ID) {
  $forcedClientId = [string]$env:SAFETY_MONITOR_CLIENT_ID
}

$isRegisteredClientId = $configuredClientId -match '^(?i)EDGE-'

if (-not [string]::IsNullOrWhiteSpace($forcedClientId)) {
  $settings['client_id'] = $forcedClientId.Trim()
} elseif ($isRegisteredClientId) {
  # 최초 등록으로 발급받은 EDGE-* ID는 run_client.bat 실행 시 덮어쓰지 않습니다.
  $settings['client_id'] = $configuredClientId.Trim()
} elseif (
  [string]::IsNullOrWhiteSpace($configuredClientId) -or
  [string]::IsNullOrWhiteSpace($configuredMachineId) -or
  $configuredMachineId.Trim() -ne $machineId -or
  $normalizedConfiguredClientId -ne $generatedClientId
) {
  $settings['client_id'] = $generatedClientId
}

$settings['machine_id'] = $machineId
$settings['remote_server_base_url'] = $RemoteServerUrl.Trim().TrimEnd('/')

$settingsDir = Split-Path -Parent $SettingsPath
if (-not [string]::IsNullOrWhiteSpace($settingsDir)) {
  New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null
}

$settings | ConvertTo-Json | Set-Content -LiteralPath $SettingsPath -Encoding UTF8

Write-Host "Client ID: $($settings['client_id'])"
Write-Host "Remote server: $($settings['remote_server_base_url'])"
