#requires -Version 5.1
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$packageRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $packageRoot 'ClaudePill.Core.ps1')
. (Join-Path $packageRoot 'ClaudePill.Integration.ps1')
$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('claude-pill-test-' + [Guid]::NewGuid().ToString('N'))
$testCount = 0
function Assert-CLPTest {
    param([bool]$Condition, [string]$Name)
    if (-not $Condition) { throw ('FAIL: ' + $Name) }
    $script:testCount++
    Write-Output ('PASS: ' + $Name)
}
function Invoke-TestCollector {
    param($Payload, [string]$CachePath, [string]$EncodedCommand)
    $engineProcess = [Diagnostics.Process]::GetCurrentProcess()
    try { $engine = $engineProcess.MainModule.FileName } finally { $engineProcess.Dispose() }
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $engine
    $info.Arguments = '-NoLogo -NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $packageRoot 'ClaudePill.StatusLine.ps1') + '" -CacheDirectory "' + $CachePath + '"'
    if ($EncodedCommand) { $info.Arguments = '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand ' + $EncodedCommand }
    $info.UseShellExecute = $false; $info.CreateNoWindow = $true
    $info.RedirectStandardInput = $true; $info.RedirectStandardOutput = $true; $info.RedirectStandardError = $true
    $process = [Diagnostics.Process]::Start($info)
    try {
        $writer = [IO.StreamWriter]::new($process.StandardInput.BaseStream, [Text.UTF8Encoding]::new($false))
        $writer.Write(($Payload | ConvertTo-Json -Depth 12 -Compress)); $writer.Dispose()
        $output = $process.StandardOutput.ReadToEnd()
        $errorOutput = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) { throw ('Collector failed: ' + $errorOutput) }
        return $output
    } finally { $process.Dispose() }
}
try {
    [void][IO.Directory]::CreateDirectory($fixtureRoot)
    $claudeHome = Join-Path $fixtureRoot 'Claude User''s Config'
    $cachePath = Join-Path (Join-Path $claudeHome 'codex-pill') 'cache'
    $reader = New-ClaudePillReader -ClaudeHome $claudeHome
    Update-ClaudePillReader $reader
    $snapshot = Get-ClaudePillSnapshot $reader
    Assert-CLPTest ($snapshot.Status -eq 'Missing' -and $null -eq $snapshot.Primary) 'Missing integration never fabricates a quota.'
    $enabled = Enable-ClaudePillIntegration -ClaudeHome $claudeHome
    Assert-CLPTest ($enabled.Status -eq 'Enabled' -and (Get-ClaudePillIntegrationState $claudeHome).Status -eq 'Enabled') 'Official statusLine configuration installs explicitly.'
    $settingsPath = Join-Path $claudeHome 'settings.json'
    $installed = [IO.File]::ReadAllText($settingsPath) | ConvertFrom-Json
    $encoded = $installed.statusLine.command.Split(' ')[-1]
    $command = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($encoded))
    Assert-CLPTest ($command.Contains("User''s Config")) 'Encoded command preserves apostrophes and spaces.'
    $now = [DateTimeOffset]::UtcNow
    $payload = @{
        session_id='test-session'; workspace=@{current_dir='C:\Projets\Shōnen Café'}
        model=@{display_name='Claude'}; cost=@{total_api_duration_ms=1200}
        rate_limits=@{five_hour=@{used_percentage=23.5;resets_at=$now.AddHours(2).ToUnixTimeSeconds()};seven_day=@{used_percentage=41.2;resets_at=$now.AddDays(3).ToUnixTimeSeconds()}}
        context_window=@{used_percentage=99;total_input_tokens=15500;total_output_tokens=1200}
        secret_unrelated_field='DO_NOT_STORE_THIS'
    }
    [void](Invoke-TestCollector $payload $cachePath -EncodedCommand $encoded)
    Update-ClaudePillReader $reader
    $snapshot = Get-ClaudePillSnapshot $reader
    Assert-CLPTest ($snapshot.Primary.UsedPercent -eq 23.5 -and $snapshot.Secondary.UsedPercent -eq 41.2) 'Installed encoded statusLine supplies subscription percentages, not context usage.'
    Assert-CLPTest ($snapshot.Activity[0].Project -ceq 'Shōnen Café') 'UTF-8 project names survive the installed statusLine command.'
    Assert-CLPTest ($snapshot.Primary.WindowMinutes -eq 300 -and $snapshot.Secondary.WindowMinutes -eq 10080) 'Five-hour and weekly durations are mapped correctly.'
    Assert-CLPTest ($null -eq $snapshot.Activity[0].TotalTokens -and $snapshot.Activity[0].ContextTokens -eq 16700) 'Context tokens are not mislabeled as cumulative session tokens.'
    $cacheFile = Get-ChildItem -LiteralPath $cachePath -Filter 'session-*.json' | Select-Object -First 1
    Assert-CLPTest (-not [IO.File]::ReadAllText($cacheFile.FullName).Contains('DO_NOT_STORE_THIS')) 'The collector stores only selected metrics and metadata.'
    $olderRepaint = [IO.File]::ReadAllText($cacheFile.FullName) | ConvertFrom-Json
    $olderRepaint.session_id = 'older-idle-session'
    $olderRepaint.captured_at = [DateTimeOffset]::UtcNow.AddSeconds(2).ToString('o')
    $olderRepaint.observed_at = [DateTimeOffset]::UtcNow.AddMinutes(-10).ToString('o')
    $olderRepaint.five_hour.used_percentage = 8
    Write-CLPJsonAtomic (Join-Path $cachePath 'session-older-idle.json') $olderRepaint
    Update-ClaudePillReader $reader
    $snapshot = Get-ClaudePillSnapshot $reader
    Assert-CLPTest ($snapshot.Primary.UsedPercent -eq 23.5 -and $snapshot.LastSession -eq 'test-session') 'A repaint of an older session cannot override a newer actual observation.'
    $firstObserved = $snapshot.LastUpdated
    Start-Sleep -Milliseconds 50
    [void](Invoke-TestCollector $payload $cachePath)
    Update-ClaudePillReader $reader
    Assert-CLPTest ((Get-ClaudePillSnapshot $reader).LastUpdated -eq $firstObserved) 'Identical status repaints do not manufacture a fresh observation.'
    $payload.rate_limits.five_hour.resets_at = $now.AddSeconds(-1).ToUnixTimeSeconds()
    [void](Invoke-TestCollector $payload $cachePath)
    Update-ClaudePillReader $reader
    $snapshot = Get-ClaudePillSnapshot $reader
    Assert-CLPTest ($snapshot.Primary.IsExpired -and $snapshot.Primary.UsedPercent -eq 23.5) 'Expiration remains unconfirmed instead of becoming zero used.'
    $payload.rate_limits.Remove('five_hour')
    [void](Invoke-TestCollector $payload $cachePath)
    Update-ClaudePillReader $reader
    Assert-CLPTest ($null -eq (Get-ClaudePillSnapshot $reader).Primary) 'An absent newer window clears the previous quota.'
    $otherReader = New-ClaudePillReader -ClaudeHome (Join-Path $fixtureRoot 'another-account')
    Update-ClaudePillReader $otherReader
    Assert-CLPTest ($null -eq (Get-ClaudePillSnapshot $otherReader).Secondary) 'Different Claude configuration folders never share cached quotas.'
    [void](Disable-ClaudePillIntegration $claudeHome)
    $restored = [IO.File]::ReadAllText($settingsPath) | ConvertFrom-Json
    Assert-CLPTest ($null -eq $restored.PSObject.Properties['statusLine']) 'Disabling restores the absence of a prior statusLine.'
    $custom = [pscustomobject]@{permissions=[pscustomobject]@{allow=@('Read')};statusLine=[pscustomobject]@{type='command';command='my-existing-status-line';padding=2}}
    Write-CLPJsonAtomic $settingsPath $custom
    $beforeBytes = [IO.File]::ReadAllText($settingsPath)
    $conflict = Enable-ClaudePillIntegration $claudeHome
    Assert-CLPTest ($conflict.Status -eq 'ExistingStatusLine' -and [IO.File]::ReadAllText($settingsPath) -ceq $beforeBytes) 'An existing statusLine is preserved without explicit replacement.'
    $replacement = Enable-ClaudePillIntegration $claudeHome -ReplaceExisting
    Assert-CLPTest ([IO.File]::Exists($replacement.BackupPath)) 'Explicit replacement creates a real settings backup.'
    [void](Disable-ClaudePillIntegration $claudeHome)
    $restored = [IO.File]::ReadAllText($settingsPath) | ConvertFrom-Json
    Assert-CLPTest ($restored.statusLine.command -ceq 'my-existing-status-line' -and $restored.statusLine.padding -eq 2 -and $restored.permissions.allow[0] -eq 'Read') 'Disable restores prior statusLine and retains other settings.'
    [void](Enable-ClaudePillIntegration $claudeHome -ReplaceExisting)
    $changed = [IO.File]::ReadAllText($settingsPath) | ConvertFrom-Json
    $changed.statusLine.command='a-new-user-choice'
    Write-CLPJsonAtomic $settingsPath $changed
    $disableChanged = Disable-ClaudePillIntegration $claudeHome
    Assert-CLPTest ($disableChanged.Status -eq 'ChangedExternally' -and ([IO.File]::ReadAllText($settingsPath) | ConvertFrom-Json).statusLine.command -ceq 'a-new-user-choice') 'Disable never overwrites a later external choice.'

    # --- Source « compte » (service /usage), sans réseau ---
    Assert-CLPTest ((Get-ClaudePillPlanName 'max' 'default_claude_max_5x') -eq 'Max 5x' -and (Get-ClaudePillPlanName 'pro' '') -eq 'Pro') 'Le nom de l''offre est lisible.'
    Assert-CLPTest ((Format-ClaudePillModel 'claude-opus-5-5') -eq 'Opus 5.5' -and (Format-ClaudePillModel 'claude-sonnet-4-5-20250929') -eq 'Sonnet 4.5' -and (Format-ClaudePillModel 'gpt-5') -eq '') 'Le nom du modèle est lisible.'
    $window = ConvertFrom-ClaudePillUsageWindow ([pscustomobject]@{ utilization = 27.0; resets_at = $now.AddHours(1).ToString('o') })
    Assert-CLPTest ($window.used_percentage -eq 27 -and [Math]::Abs($window.resets_at - $now.AddHours(1).ToUnixTimeSeconds()) -le 1) 'Une fenêtre du service est convertie.'
    Assert-CLPTest ($null -eq (ConvertFrom-ClaudePillUsageWindow $null)) 'Une fenêtre absente du service reste inconnue.'
    $apiHome = Join-Path $fixtureRoot 'api-account'
    $apiReader = New-ClaudePillReader -ClaudeHome $apiHome -Offline
    Update-ClaudePillReader $apiReader
    Assert-CLPTest ((Get-ClaudePillSnapshot $apiReader).Status -eq 'Missing') 'Sans connexion ni cache, aucun quota n''est inventé.'
    $apiReader.ApiRecord = [pscustomobject]@{ Data = [pscustomobject]@{ five_hour = $window; seven_day = $null }; ObservedAt = $now; CapturedAt = $now; Path = 'test' }
    $apiSnapshot = Get-ClaudePillSnapshot $apiReader
    Assert-CLPTest ($apiSnapshot.Status -eq 'Ready' -and $apiSnapshot.Source -eq 'Account' -and $apiSnapshot.Primary.RemainingPercent -eq 73 -and $null -eq $apiSnapshot.Secondary) 'La mesure du compte est affichée en part restante.'
    $apiReader.Records = @([pscustomobject]@{ Data = [pscustomobject]@{ five_hour = @{ used_percentage = 50; resets_at = $null } }; ObservedAt = $now.AddMinutes(5); CapturedAt = $now.AddMinutes(5); Path = 'cache' })
    Assert-CLPTest ((Get-ClaudePillSnapshot $apiReader).Source -eq 'StatusLine') 'La mesure la plus récente gagne entre les deux sources.'
    $transcriptDirectory = Join-Path (Join-Path $apiHome 'projects') 'c--Projets-Demo'
    [void][IO.Directory]::CreateDirectory($transcriptDirectory)
    $line = @{ type = 'assistant'; cwd = 'C:\Projets\Démo Café'; message = @{ model = 'claude-opus-5-5'; content = 'secret' } } | ConvertTo-Json -Compress -Depth 5
    [IO.File]::WriteAllText((Join-Path $transcriptDirectory 'session-a.jsonl'), $line + "`n", [Text.UTF8Encoding]::new($false))
    $activity = @(Get-ClaudePillTranscriptActivity $apiHome)
    Assert-CLPTest ($activity.Count -eq 1 -and $activity[0].Project -eq 'Démo Café' -and $activity[0].Detail -eq 'Opus 5.5') 'L''activité récente vient des conversations locales.'
    Write-Output ($testCount.ToString() + ' Claude checks passed.')
} finally { if ([IO.Directory]::Exists($fixtureRoot)) { Remove-Item -LiteralPath $fixtureRoot -Recurse -Force } }
