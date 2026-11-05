#requires -Version 5.1
# Integration test: the actual background worker, with synthetic local journals.
$ErrorActionPreference = 'Stop'
$packageDirectory = Split-Path -Parent $PSScriptRoot
$mainPath = Join-Path $packageDirectory 'codex-pill.ps1'
$parseTokens = $null; $parseErrors = $null
$syntaxTree = [Management.Automation.Language.Parser]::ParseFile($mainPath, [ref]$parseTokens, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) { throw 'Main script does not parse.' }
foreach ($functionName in @('Start-PillReader','Stop-PillReader')) {
    $definition = $syntaxTree.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $functionName }, $false) | Select-Object -First 1
    if ($null -eq $definition) { throw ('Missing function: ' + $functionName) }
    . ([scriptblock]::Create($definition.Extent.Text))
}
$fixtureDirectory = Join-Path ([IO.Path]::GetTempPath()) ('codex-pill-lifecycle-' + [Guid]::NewGuid().ToString('N'))
$script:PillDirectory = $packageDirectory
$script:PillCodexHome = $fixtureDirectory
$script:PillShared = $null
$script:PillWorker = $null
$script:PillRunspace = $null
$script:PillWorkerResult = $null
try {
    $sessionsDirectory = Join-Path $fixtureDirectory 'sessions'
    [void][IO.Directory]::CreateDirectory($sessionsDirectory)
    $observedTime = [DateTimeOffset]::UtcNow
    $fixtureRecord = @{
        timestamp = $observedTime.ToString('o'); type = 'event_msg'
        payload = @{ type = 'token_count'; rate_limits = @{ limit_id = 'codex'; primary = @{ used_percent = 42; window_minutes = 300; resets_at = $observedTime.AddHours(3).ToUnixTimeSeconds() } } }
    }
    [IO.File]::WriteAllText((Join-Path $sessionsDirectory 'rollout-lifecycle.jsonl'), (($fixtureRecord | ConvertTo-Json -Depth 8 -Compress) + "`n"), [Text.UTF8Encoding]::new($false))
    Start-PillReader
    $deadline = [DateTimeOffset]::UtcNow.AddSeconds(15)
    while ($null -eq $script:PillShared.Snapshot -and [DateTimeOffset]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 20 }
    if ($null -eq $script:PillShared.Snapshot -or $script:PillShared.Snapshot.Primary.UsedPercent -ne 42) { throw ('Worker did not produce the expected quota: ' + $script:PillShared.ErrorText) }
    Write-Output 'PASS: Actual background worker returns a synthetic quota.'
    $script:PillShared.CodexHome = Join-Path $fixtureDirectory 'missing-source'
    $script:PillShared.ForceRefresh = $true
    [void]$script:PillShared.Wake.Set()
    $deadline = [DateTimeOffset]::UtcNow.AddSeconds(10)
    while ($script:PillShared.Snapshot.Status -ne 'Missing' -and [DateTimeOffset]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 20 }
    if ($script:PillShared.Snapshot.Status -ne 'Missing') { throw 'The worker did not switch source.' }
    Write-Output 'PASS: Source changes are handled by the same worker.'
    $shutdownWatch = [Diagnostics.Stopwatch]::StartNew()
    Stop-PillReader
    $shutdownWatch.Stop()
    if (-not $script:PillWorkerResult.IsCompleted -or $shutdownWatch.ElapsedMilliseconds -gt 3500) { throw 'Worker did not finish promptly.' }
    Write-Output ('PASS: Worker wakes and exits cleanly ({0} ms).' -f $shutdownWatch.ElapsedMilliseconds)
    $script:PillShared = $null
    Write-Output '3 integration checks passed.'
} finally {
    if ($null -ne $script:PillShared -and -not $script:PillWorkerResult.IsCompleted) { try { Stop-PillReader } catch { } }
    if ([IO.Directory]::Exists($fixtureDirectory)) { Remove-Item -LiteralPath $fixtureDirectory -Recurse -Force }
}
