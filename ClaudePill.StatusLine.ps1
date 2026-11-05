#requires -Version 5.1
# Receives official Claude Code statusLine JSON via stdin. It stores only the
# explicitly selected metrics below, never the full JSON, prompts or secrets.
[CmdletBinding()]
param([string]$CacheDirectory)
$ErrorActionPreference = 'Stop'

function Read-StatusProperty {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -ne $property) { return $property.Value }
    return $null
}
function Read-StatusNumber {
    param($Value)
    if ($null -eq $Value -or $Value -is [bool]) { return $null }
    $number = 0.0
    if ([double]::TryParse([string]$Value, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$number) -and -not [double]::IsNaN($number) -and -not [double]::IsInfinity($number)) { return $number }
    return $null
}
function Read-StatusText {
    param($Value, [int]$Maximum = 512)
    if ($Value -isnot [string]) { return '' }
    $clean = [regex]::Replace($Value, '[\x00-\x1F\x7F]', '')
    return $clean.Substring(0, [Math]::Min($clean.Length, $Maximum))
}
function Read-StatusWindow {
    param($Value)
    $used = Read-StatusNumber (Read-StatusProperty $Value 'used_percentage')
    if ($null -eq $used -or $used -lt 0) { return $null }
    $reset = Read-StatusNumber (Read-StatusProperty $Value 'resets_at')
    if ($null -ne $reset -and ($reset -le 0 -or $reset -gt 253402300799)) { $reset = $null }
    return [ordered]@{ used_percentage = [Math]::Min(100.0, $used); resets_at = $reset }
}

$cacheLock = $null
try {
    if ([string]::IsNullOrWhiteSpace($CacheDirectory)) { $CacheDirectory = Join-Path $PSScriptRoot 'cache' }
    $stdinReader = [IO.StreamReader]::new([Console]::OpenStandardInput(), [Text.UTF8Encoding]::new($false), $true)
    try {
        $inputBuilder = [Text.StringBuilder]::new()
        $inputBuffer = New-Object char[] 4096
        while (($inputCount = $stdinReader.Read($inputBuffer, 0, $inputBuffer.Length)) -gt 0) {
            [void]$inputBuilder.Append($inputBuffer, 0, $inputCount)
            if ($inputBuilder.Length -gt 2097152) { throw 'Status input too large.' }
        }
        $rawInput = $inputBuilder.ToString()
    } finally { $stdinReader.Dispose() }
    if ([string]::IsNullOrWhiteSpace($rawInput)) { throw 'Invalid status input.' }
    $statusInput = $rawInput | ConvertFrom-Json -ErrorAction Stop
    $sessionId = Read-StatusText (Read-StatusProperty $statusInput 'session_id') 256
    if (-not $sessionId) { $sessionId = 'current-session' }
    $workspace = Read-StatusProperty $statusInput 'workspace'
    $cwd = Read-StatusText (Read-StatusProperty $workspace 'current_dir') 4096
    if (-not $cwd) { $cwd = Read-StatusText (Read-StatusProperty $statusInput 'cwd') 4096 }
    $rateLimits = Read-StatusProperty $statusInput 'rate_limits'
    $context = Read-StatusProperty $statusInput 'context_window'
    $inputCount = Read-StatusNumber (Read-StatusProperty $context 'total_input_tokens')
    $outputCount = Read-StatusNumber (Read-StatusProperty $context 'total_output_tokens')
    $contextTokens = $null
    if ($null -ne $inputCount -and $null -ne $outputCount -and $inputCount -ge 0 -and $outputCount -ge 0) { $contextTokens = $inputCount + $outputCount }
    $record = [ordered]@{
        schema_version = 1; provider = 'claude'; captured_at = [DateTimeOffset]::UtcNow.ToString('o'); observed_at = [DateTimeOffset]::UtcNow.ToString('o')
        session_id = $sessionId; cwd = $cwd
        model = Read-StatusText (Read-StatusProperty (Read-StatusProperty $statusInput 'model') 'display_name') 120
        five_hour = Read-StatusWindow (Read-StatusProperty $rateLimits 'five_hour')
        seven_day = Read-StatusWindow (Read-StatusProperty $rateLimits 'seven_day')
        context_tokens = $contextTokens
        api_duration_ms = Read-StatusNumber (Read-StatusProperty (Read-StatusProperty $statusInput 'cost') 'total_api_duration_ms')
    }
    $hashProvider = [Security.Cryptography.SHA256]::Create()
    try { $sessionHash = [BitConverter]::ToString($hashProvider.ComputeHash([Text.Encoding]::UTF8.GetBytes($sessionId))).Replace('-', '').Substring(0, 32) }
    finally { $hashProvider.Dispose() }
    [void][IO.Directory]::CreateDirectory($CacheDirectory)
    $cachePath = Join-Path $CacheDirectory ('session-' + $sessionHash + '.json')
    for ($lockAttempt = 0; $lockAttempt -lt 20; $lockAttempt++) {
        try {
            $cacheLock = [IO.FileStream]::new(($cachePath + '.lock'), [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
            break
        } catch [IO.IOException] { Start-Sleep -Milliseconds 20 }
    }
    if ($null -ne $cacheLock) {
        if ([IO.File]::Exists($cachePath)) {
            try {
                $previous = [IO.File]::ReadAllText($cachePath, [Text.Encoding]::UTF8) | ConvertFrom-Json -ErrorAction Stop
                $oldSignature = @((Read-StatusProperty $previous 'five_hour'), (Read-StatusProperty $previous 'seven_day'), (Read-StatusProperty $previous 'context_tokens'), (Read-StatusProperty $previous 'api_duration_ms')) | ConvertTo-Json -Depth 5 -Compress
                $newSignature = @($record.five_hour, $record.seven_day, $record.context_tokens, $record.api_duration_ms) | ConvertTo-Json -Depth 5 -Compress
                if ($oldSignature -ceq $newSignature -and (Read-StatusProperty $previous 'observed_at')) { $record.observed_at = $previous.observed_at }
            } catch { }
        }
        $temporaryPath = $cachePath + '.' + $PID + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
        try {
            [IO.File]::WriteAllText($temporaryPath, ($record | ConvertTo-Json -Depth 6 -Compress), [Text.UTF8Encoding]::new($false))
            if ([IO.File]::Exists($cachePath)) { [IO.File]::Replace($temporaryPath, $cachePath, [System.Management.Automation.Language.NullString]::Value) }
            else { [IO.File]::Move($temporaryPath, $cachePath) }
        } finally { if ([IO.File]::Exists($temporaryPath)) { [IO.File]::Delete($temporaryPath) } }
    }
    $parts = @('Claude')
    if ($null -ne $record.five_hour) { $parts += '5 h : ' + ('{0:0} %' -f $record.five_hour.used_percentage) }
    if ($null -ne $record.seven_day) { $parts += '7 j : ' + ('{0:0} %' -f $record.seven_day.used_percentage) }
    if ($parts.Count -eq 1) { $parts += 'quotas en attente' }
    [Console]::WriteLine(($parts -join ' | '))
} catch {
    # A metrics collector must never disrupt the Claude Code session.
    [Console]::WriteLine('Claude | mesures indisponibles')
} finally {
    if ($null -ne $cacheLock) { $cacheLock.Dispose() }
}
