#requires -Version 5.1
# End-to-end worker switching, using only synthetic temporary data.
$ErrorActionPreference = 'Stop'
$packageDirectory = Split-Path -Parent $PSScriptRoot
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $packageDirectory 'codex-pill.ps1'), [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'The main script does not parse.' }
foreach ($functionName in @('Start-PillReader','Stop-PillReader')) {
    $definition = $ast.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $functionName }, $false) | Select-Object -First 1
    . ([scriptblock]::Create($definition.Extent.Text))
}
function Wait-ProviderSnapshot {
    param([string]$Provider, [string]$Source, $ExpectedUsed)
    $deadline = [DateTimeOffset]::UtcNow.AddSeconds(10)
    do {
        $snapshot = $script:PillShared.Snapshot
        if ($null -ne $snapshot -and $snapshot.Provider -eq $Provider -and $snapshot.SourceHome -eq $Source) {
            if ($null -eq $ExpectedUsed -and $null -eq $snapshot.Primary) { return }
            if ($null -ne $snapshot.Primary -and $snapshot.Primary.UsedPercent -eq $ExpectedUsed) { return }
        }
        Start-Sleep -Milliseconds 20
    } while ([DateTimeOffset]::UtcNow -lt $deadline)
    throw ('Unexpected snapshot for ' + $Provider + ': ' + $script:PillShared.ErrorText)
}
$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ('pill-providers-' + [guid]::NewGuid().ToString('N'))
$script:PillDirectory = $packageDirectory
$script:PillCodexHome = Join-Path $temporaryRoot 'codex'
$script:PillClaudeHome = Join-Path $temporaryRoot 'claude'
$script:PillSettings = @{ Provider = 'Codex' }
$script:PillShared = $null
$script:PillWorker = $null
$script:PillRunspace = $null
$script:PillWorkerResult = $null
try {
    $codexSessions = Join-Path $script:PillCodexHome 'sessions'
    $claudeCache = Join-Path (Join-Path $script:PillClaudeHome 'codex-pill') 'cache'
    [void][IO.Directory]::CreateDirectory($codexSessions)
    [void][IO.Directory]::CreateDirectory($claudeCache)
    $now = [DateTimeOffset]::UtcNow
    $codexEvent = @{ timestamp = $now.ToString('o'); type = 'event_msg'; payload = @{ type = 'token_count'; rate_limits = @{ primary = @{ used_percent = 42; window_minutes = 300; resets_at = $now.AddHours(2).ToUnixTimeSeconds() } } } }
    [IO.File]::WriteAllText((Join-Path $codexSessions 'rollout-providers.jsonl'), (($codexEvent | ConvertTo-Json -Depth 8 -Compress) + "`n"), [Text.UTF8Encoding]::new($false))
    $claudeEvent = @{ schema_version = 1; provider = 'claude'; captured_at = $now.ToString('o'); observed_at = $now.ToString('o'); session_id = 'provider-test'; cwd = 'C:\Test'; five_hour = @{ used_percentage = 71.5; resets_at = $now.AddHours(2).ToUnixTimeSeconds() }; seven_day = $null }
    [IO.File]::WriteAllText((Join-Path $claudeCache 'session-provider.json'), ($claudeEvent | ConvertTo-Json -Depth 8 -Compress), [Text.UTF8Encoding]::new($false))
    Start-PillReader
    Wait-ProviderSnapshot 'Codex' $script:PillCodexHome 42
    Write-Output 'PASS: Codex data is labeled and isolated.'
    $script:PillShared.Provider = 'Claude'; $script:PillShared.ForceRefresh = $true
    [void]$script:PillShared.Wake.Set()
    Wait-ProviderSnapshot 'Claude' $script:PillClaudeHome 71.5
    Write-Output 'PASS: The running worker switches to the Claude source.'
    $script:PillShared.Provider = 'Codex'; $script:PillShared.ForceRefresh = $true
    [void]$script:PillShared.Wake.Set()
    Wait-ProviderSnapshot 'Codex' $script:PillCodexHome 42
    Write-Output 'PASS: Switching back restores only Codex data.'
    $changedSource = Join-Path $temporaryRoot 'empty-codex'
    $script:PillShared.CodexHome = $changedSource; $script:PillShared.ForceRefresh = $true
    [void]$script:PillShared.Wake.Set()
    Wait-ProviderSnapshot 'Codex' $changedSource $null
    Write-Output 'PASS: A changed source cannot retain the old quota.'
    Stop-PillReader
    $script:PillShared = $null
    Write-Output '4 provider-switch checks passed.'
} finally {
    if ($null -ne $script:PillShared -and -not $script:PillWorkerResult.IsCompleted) { try { Stop-PillReader } catch { } }
    if ([IO.Directory]::Exists($temporaryRoot)) { Remove-Item -LiteralPath $temporaryRoot -Recurse -Force }
}
