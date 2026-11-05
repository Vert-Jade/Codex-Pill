# Portable regression checks for the local reader; no real Codex files are read.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'CodexPill.Core.ps1')
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('CodexPill-tests-' + [guid]::NewGuid().ToString('N'))
$encoding = New-Object Text.UTF8Encoding $false
$passed = 0
$reader = $null

function Assert-CP($Condition, [string]$Message) {
    if (-not $Condition) { throw "FAILED: $Message" }
    $script:passed++
    Write-Output "PASS: $Message"
}

function New-TestRecord([DateTimeOffset]$At, $Primary, $Secondary, $Tokens = 100, [string]$Limit = 'codex') {
    $record = @{ timestamp = $At.ToString('o'); type = 'event_msg'; payload = @{
        type = 'token_count'; info = @{ total_token_usage = @{ total_tokens = $Tokens } }
        rate_limits = @{ limit_id = $Limit; primary = $Primary; secondary = $Secondary }
    } }
    return (($record | ConvertTo-Json -Depth 8 -Compress) + "`n")
}

function New-TestWindow($Used, [DateTimeOffset]$Reset, $Minutes = 300) {
    return @{ used_percent = $Used; resets_at = $Reset.ToUnixTimeSeconds(); window_minutes = $Minutes }
}

function Update-TestReader($State, [int]$Times = 1) {
    for ($i = 0; $i -lt $Times; $i++) { Update-CodexPillReader -Reader $State -ForceScan }
}

try {
    $reader = New-CodexPillReader -CodexHome $testRoot
    Update-TestReader $reader
    Assert-CP ((Get-CodexPillSnapshot $reader).Status -eq 'Missing') 'Missing sessions folder has no fabricated quota.'
    [void][IO.Directory]::CreateDirectory((Join-Path $testRoot 'sessions/2020/01/01'))
    Update-TestReader $reader
    Assert-CP ((Get-CodexPillSnapshot $reader).Status -eq 'Empty') 'Empty sessions folder is identified.'

    $path = Join-Path $testRoot 'sessions/2020/01/01/rollout-test.jsonl'
    $now = [DateTimeOffset]::UtcNow.AddMinutes(-1)
    $meta = @{ timestamp = $now.ToString('o'); type = 'session_meta'; payload = @{ id = 'session-one'; cwd = 'C:\Projets\Projet ete' } } | ConvertTo-Json -Compress
    $first = New-TestRecord $now (New-TestWindow 23 $now.AddHours(5)) (New-TestWindow 41 $now.AddDays(7) 10080)
    [IO.File]::WriteAllText($path, ($meta + "`n" + $first), $encoding)
    Update-TestReader $reader
    $snapshot = Get-CodexPillSnapshot $reader
    Assert-CP ($snapshot.Status -eq 'Ready' -and $snapshot.Primary.RemainingPercent -eq 77 -and $snapshot.Secondary.UsedPercent -eq 41) 'Primary and secondary quotas come from an old directory too.'
    Assert-CP ($snapshot.Activity.Count -eq 1 -and $snapshot.LastProject -eq 'Projet ete' -and $snapshot.Activity[0].TotalTokens -eq 100) 'Session metadata and cumulative tokens are read.'
    Assert-CP ($snapshot.Primary.WindowMinutes -eq 300 -and $snapshot.Secondary.WindowMinutes -eq 10080) 'Actual server window durations are preserved.'

    $second = New-TestRecord $now.AddSeconds(1) (New-TestWindow 25 $now.AddHours(5)) $null 130
    [IO.File]::AppendAllText($path, $second.TrimEnd([char]10), $encoding)
    Update-TestReader $reader
    Assert-CP ((Get-CodexPillSnapshot $reader).Primary.UsedPercent -eq 23) 'A partial final JSON line is not consumed.'
    [IO.File]::AppendAllText($path, "`n", $encoding)
    Update-TestReader $reader
    $snapshot = Get-CodexPillSnapshot $reader
    Assert-CP ($snapshot.Primary.UsedPercent -eq 25 -and $snapshot.Activity[0].TotalTokens -eq 130) 'Completing the final line updates once without double counting.'
    Assert-CP ($snapshot.Secondary.UsedPercent -eq 41) 'A sparse update preserves the other known window.'

    [IO.File]::AppendAllText($path, ('{"type":"event_msg","payload":{"type":"token_count",broken}' + "`n" +
        (New-TestRecord $now.AddSeconds(2) (New-TestWindow 30 $now.AddHours(5)) $null 140)), $encoding)
    Update-TestReader $reader
    Assert-CP ((Get-CodexPillSnapshot $reader).Primary.UsedPercent -eq 30 -and $reader.Diagnostics.ParseErrors -eq 1) 'One malformed record cannot poison later records.'

    [IO.File]::AppendAllText($path, (New-TestRecord $now.AddSeconds(3) (New-TestWindow 99 $now.AddHours(5)) $null 150 'codex_other'), $encoding)
    Update-TestReader $reader
    Assert-CP ((Get-CodexPillSnapshot $reader).Primary.UsedPercent -eq 30) 'A model-specific quota never replaces the main Codex quota.'
    [IO.File]::AppendAllText($path, (New-TestRecord $now.AddSeconds(-10) (New-TestWindow 10 $now.AddHours(5)) $null 50), $encoding)
    Update-TestReader $reader
    Assert-CP ((Get-CodexPillSnapshot $reader).Primary.UsedPercent -eq 30 -and (Get-CodexPillSnapshot $reader).Activity[0].TotalTokens -eq 150) 'Out-of-order events do not overwrite newer observations.'

    $accent = [char]0x00E9
    $unicodeRecord = @{ timestamp = $now.AddSeconds(4).ToString('o'); type = 'turn_context'; payload = @{ cwd = ('C:\Projets\Caf' + $accent) } } | ConvertTo-Json -Compress
    $unicodeBytes = $encoding.GetBytes($unicodeRecord + "`n")
    $split = [Array]::IndexOf($unicodeBytes, [byte]0xC3) + 1
    $file = [IO.File]::Open($path, [IO.FileMode]::Append, [IO.FileAccess]::Write, [IO.FileShare]::ReadWrite)
    try { $file.Write($unicodeBytes, 0, $split) } finally { $file.Dispose() }
    Update-TestReader $reader
    $file = [IO.File]::Open($path, [IO.FileMode]::Append, [IO.FileAccess]::Write, [IO.FileShare]::ReadWrite)
    try { $file.Write($unicodeBytes, $split, $unicodeBytes.Length - $split) } finally { $file.Dispose() }
    Update-TestReader $reader
    Assert-CP ((Get-CodexPillSnapshot $reader).LastProject -eq ('Caf' + $accent)) 'A UTF-8 character split across writes is retained exactly.'

    [IO.File]::WriteAllText($path, (New-TestRecord $now.AddSeconds(5) (New-TestWindow 80 $now.AddSeconds(-1)) $null 12), $encoding)
    Update-TestReader $reader
    $snapshot = Get-CodexPillSnapshot $reader
    Assert-CP ($snapshot.Primary.IsExpired -and $snapshot.Primary.RemainingPercent -eq 20 -and $snapshot.Status -eq 'Expired') 'Expiration marks an observation unconfirmed instead of inventing 100 percent.'
    Assert-CP ($null -eq $snapshot.Secondary -and $snapshot.Activity[0].TotalTokens -eq 12) 'Truncation removes the prior file state.'

    [IO.File]::AppendAllText($path, (New-TestRecord $now.AddSeconds(6) (New-TestWindow 55 $now.AddDays(7) 10080) $null 25), $encoding)
    Update-TestReader $reader
    $snapshot = Get-CodexPillSnapshot $reader
    Assert-CP ($snapshot.Primary.WindowMinutes -eq 10080 -and $null -eq $snapshot.Secondary) 'A weekly-only primary is supported.'

    $largePath = Join-Path $testRoot 'sessions/2020/01/01/rollout-large.jsonl'
    $hugeLine = '{"type":"response_item","payload":{"text":"' + ('x' * (2 * 1024 * 1024)) + '"}}' + "`n"
    [IO.File]::WriteAllText($largePath, $meta + "`n" + $hugeLine + (New-TestRecord $now.AddSeconds(10) (New-TestWindow 62 $now.AddHours(5)) $null 900), $encoding)
    Update-TestReader $reader 12
    $snapshot = Get-CodexPillSnapshot $reader
    Assert-CP ($snapshot.Primary.UsedPercent -eq 62) 'A very large tool-output line does not prevent a following quota event.'
    Assert-CP ($reader.Buffer.Length -eq (256 * 1024) -and -not $reader.Diagnostics.IsCatchingUp) 'The read buffer is bounded and catches up fully.'

    $originalCulture = [Threading.Thread]::CurrentThread.CurrentCulture
    try {
        [Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]::GetCultureInfo('fr-FR')
        Assert-CP ((ConvertTo-CPWindow ([pscustomobject]@{ used_percent = 12.5; resets_at = '1890000000'; window_minutes = 60 }) $now).UsedPercent -eq 12.5) 'Decimal percentages parse correctly under a French locale.'
    } finally { [Threading.Thread]::CurrentThread.CurrentCulture = $originalCulture }

    $stale = Copy-CPDisplayWindow (ConvertTo-CPWindow (New-TestWindow 30 $now.AddDays(1)) $now.AddMinutes(-20)) ([DateTimeOffset]::UtcNow)
    Assert-CP ($stale.IsStale -and -not $stale.IsExpired) 'Stale and expired observations are distinguished.'

    # Sparse fixtures exercise the scheduling of 96 >1-MiB logs without writing
    # hundreds of megabytes of filler or running a performance benchmark.
    $pressureHome = Join-Path $testRoot 'startup-load'
    $pressureFolder = Join-Path $pressureHome 'sessions/2020/01/01'
    [void][IO.Directory]::CreateDirectory($pressureFolder)
    $pressureReader = New-CodexPillReader -CodexHome $pressureHome
    try {
        for ($fileIndex = 0; $fileIndex -lt 96; $fileIndex++) {
            $pressurePath = Join-Path $pressureFolder ('rollout-fixture-{0:000}.jsonl' -f $fileIndex)
            $observed = $now.AddHours(-2)
            $used = 10
            if ($fileIndex -eq 0) { $observed = $now.AddSeconds(20); $used = 79 }
            $finalRecord = $encoding.GetBytes("`n" + (New-TestRecord $observed (New-TestWindow $used $now.AddHours(5)) $null))
            $file = [IO.File]::Open($pressurePath, [IO.FileMode]::Create, [IO.FileAccess]::Write)
            try {
                $head = $encoding.GetBytes($meta + "`n")
                $file.Write($head, 0, $head.Length)
                $file.SetLength($pressureReader.InitialTailBytes + (32 * 1024))
                [void]$file.Seek(0, [IO.SeekOrigin]::End)
                $file.Write($finalRecord, 0, $finalRecord.Length)
            } finally { $file.Dispose() }
            [IO.File]::SetLastWriteTimeUtc($pressurePath, [datetime]::UtcNow.AddSeconds(-$fileIndex))
            Add-CPFile $pressureReader $pressurePath
        }
        $updates = 0
        do {
            Update-CodexPillReader $pressureReader
            $updates++
            $pressureSnapshot = Get-CodexPillSnapshot $pressureReader
        } while (($null -eq $pressureSnapshot.Primary -or $pressureSnapshot.Primary.UsedPercent -ne 79) -and $updates -lt 6)
        Assert-CP ($pressureReader.Files.Count -eq 96) 'The startup scheduling case contains all 96 large journals.'
        Assert-CP ($null -ne $pressureSnapshot.Primary -and $pressureSnapshot.Primary.UsedPercent -eq 79 -and $updates -le 4) "The latest final quota is available within four bounded updates (observed: $updates)."
        Assert-CP ($pressureReader.Diagnostics.ReadBytes -le ($updates * ((1024 * 1024) + (64 * 1024)))) 'The prioritized startup still respects its per-update byte budget plus header.'
    } finally { Close-CodexPillReader $pressureReader }
    Write-Output "$passed checks passed."
} finally {
    Close-CodexPillReader $reader
    if ([IO.Directory]::Exists($testRoot)) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
