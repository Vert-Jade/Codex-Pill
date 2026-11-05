# Codex Pill - read-only local rollout reader. Windows PowerShell 5.1 compatible.
# This file has no UI, network calls, credentials access, or global reader state.

function Get-CPProperty {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    if ($Object -is [System.Collections.IDictionary]) { return $Object[$Name] }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -ne $property) { return $property.Value }
    return $null
}

function ConvertTo-CPDate {
    param($Value)
    if ($null -eq $Value) { return $null }
    try {
        if ($Value -is [DateTimeOffset]) { return $Value.ToUniversalTime() }
        if ($Value -is [datetime]) { return ([DateTimeOffset]$Value).ToUniversalTime() }
        $number = 0L
        if ([long]::TryParse([string]$Value, [ref]$number)) {
            if ($number -le 0) { return $null }
            return [DateTimeOffset]::FromUnixTimeSeconds($number)
        }
        $date = [DateTimeOffset]::MinValue
        if ([DateTimeOffset]::TryParse([string]$Value,
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::AssumeUniversal, [ref]$date)) {
            return $date.ToUniversalTime()
        }
    } catch { }
    return $null
}

function ConvertTo-CPNumber {
    param($Value)
    if ($null -eq $Value -or $Value -is [bool]) { return $null }
    $number = 0.0
    if ([double]::TryParse([string]$Value, [Globalization.NumberStyles]::Float,
        [Globalization.CultureInfo]::InvariantCulture, [ref]$number)) {
        if (-not [double]::IsNaN($number) -and -not [double]::IsInfinity($number)) { return $number }
    }
    return $null
}

function ConvertTo-CPWindow {
    param($Value, [DateTimeOffset]$ObservedAt)
    $used = ConvertTo-CPNumber (Get-CPProperty $Value 'used_percent')
    if ($null -eq $used -or $used -lt 0) { return $null }
    $minutes = ConvertTo-CPNumber (Get-CPProperty $Value 'window_minutes')
    if ($null -eq $minutes) { $minutes = ConvertTo-CPNumber (Get-CPProperty $Value 'window_duration_mins') }
    if ($null -ne $minutes -and $minutes -le 0) { $minutes = $null }
    [pscustomobject]@{
        UsedPercent = [Math]::Min(100.0, $used)
        RemainingPercent = [Math]::Max(0.0, 100.0 - $used)
        ResetAt = ConvertTo-CPDate (Get-CPProperty $Value 'resets_at')
        WindowMinutes = $minutes
        ObservedAt = $ObservedAt
    }
}

function New-CodexPillReader {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$CodexHome)
    $resolved = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($CodexHome))
    [pscustomobject]@{
        CodexHome = $resolved
        SessionsPath = Join-Path $resolved 'sessions'
        Files = @{}
        FileCapacity = 96
        ScanEnumerator = $null
        ScanDirectories = New-Object 'System.Collections.Generic.Stack[string]'
        ScanLastCompleted = [DateTimeOffset]::MinValue
        ScanStarted = $false
        Seeded = $false
        ReadCursor = 0
        Buffer = New-Object byte[] (256 * 1024)
        InitialTailBytes = 1024 * 1024
        RootExists = $false
        Diagnostics = [pscustomobject]@{
            FilesTracked = 0
            FilesDiscovered = 0L
            ParseErrors = 0L
            ReadErrors = 0L
            OversizedLines = 0L
            ReadBytes = 0L
            LastError = ''
            IsScanning = $false
            IsCatchingUp = $false
        }
    }
}

function New-CPFileState {
    param([IO.FileInfo]$Info)
    [pscustomobject]@{
        Path = $Info.FullName
        LastWriteUtc = $Info.LastWriteTimeUtc
        CreationUtc = $Info.CreationTimeUtc
        Offset = 0L
        LastLength = -1L
        LastReadWriteUtc = [datetime]::MinValue
        Initialized = $false
        AwaitingAppend = $false
        SkipToNewLine = $false
        Cwd = ''
        SessionId = [IO.Path]::GetFileNameWithoutExtension($Info.Name)
        MetadataAt = [DateTimeOffset]::MinValue
        LastActivity = $null
        TokenAt = [DateTimeOffset]::MinValue
        TotalTokens = $null
        Primary = $null
        Secondary = $null
    }
}

function Add-CPFile {
    param($Reader, [string]$Path)
    try {
        $info = New-Object IO.FileInfo $Path
        if (-not $info.Exists) { return }
        if (($info.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return }
        if ($Reader.Files.ContainsKey($info.FullName)) {
            $Reader.Files[$info.FullName].LastWriteUtc = $info.LastWriteTimeUtc
            return
        }
        if ($Reader.Files.Count -ge $Reader.FileCapacity) {
            $oldest = $Reader.Files.Values | Sort-Object LastWriteUtc | Select-Object -First 1
            if ($info.LastWriteTimeUtc -le $oldest.LastWriteUtc) { return }
            $Reader.Files.Remove($oldest.Path)
        }
        $Reader.Files[$info.FullName] = New-CPFileState $info
    } catch {
        $Reader.Diagnostics.ReadErrors++
        $Reader.Diagnostics.LastError = 'Un fichier de session est inaccessible.'
    }
}

function Read-CPLine {
    param($Reader, $Entry, [string]$Line)
    if ([string]::IsNullOrWhiteSpace($Line)) { return }
    # Do not deserialize arbitrary prompts/tool output. Only relevant record types.
    if ($Line.IndexOf('"token_count"', [StringComparison]::Ordinal) -lt 0 -and
        $Line.IndexOf('"session_meta"', [StringComparison]::Ordinal) -lt 0 -and
        $Line.IndexOf('"turn_context"', [StringComparison]::Ordinal) -lt 0) { return }
    try { $record = ConvertFrom-Json -InputObject $Line -ErrorAction Stop }
    catch { $Reader.Diagnostics.ParseErrors++; return }
    $kind = Get-CPProperty $record 'type'
    $payload = Get-CPProperty $record 'payload'
    if ($null -eq $payload) { return }
    $at = ConvertTo-CPDate (Get-CPProperty $record 'timestamp')
    if ($kind -eq 'session_meta' -or $kind -eq 'turn_context') {
        if ($null -eq $at) { $at = ConvertTo-CPDate (Get-CPProperty $payload 'timestamp') }
        $cwd = Get-CPProperty $payload 'cwd'
        if ($cwd -is [string] -and $cwd.Length -gt 0 -and
            ($null -eq $at -or $at -ge $Entry.MetadataAt)) {
            $Entry.Cwd = $cwd
            if ($null -ne $at) { $Entry.MetadataAt = $at }
        }
        if ($kind -eq 'session_meta') {
            $sessionId = Get-CPProperty $payload 'id'
            if ($sessionId -is [string] -and $sessionId.Length -gt 0) { $Entry.SessionId = $sessionId }
        }
        if ($null -ne $at -and ($null -eq $Entry.LastActivity -or $at -gt $Entry.LastActivity)) {
            $Entry.LastActivity = $at
        }
        return
    }
    if ($kind -ne 'event_msg' -or (Get-CPProperty $payload 'type') -ne 'token_count') { return }
    # Without an observation timestamp we cannot order account snapshots honestly.
    if ($null -eq $at) { return }
    if ($null -eq $Entry.LastActivity -or $at -gt $Entry.LastActivity) { $Entry.LastActivity = $at }
    $info = Get-CPProperty $payload 'info'
    $usage = Get-CPProperty $info 'total_token_usage'
    $tokens = ConvertTo-CPNumber (Get-CPProperty $usage 'total_tokens')
    if ($null -ne $tokens -and $tokens -ge 0 -and $at -ge $Entry.TokenAt) {
        $Entry.TotalTokens = $tokens
        $Entry.TokenAt = $at
    }
    $limits = Get-CPProperty $payload 'rate_limits'
    if ($null -eq $limits) { return }
    $limitId = Get-CPProperty $limits 'limit_id'
    if ($null -ne $limitId -and [string]$limitId -ne '' -and [string]$limitId -ne 'codex') { return }
    foreach ($name in @('Primary', 'Secondary')) {
        $window = ConvertTo-CPWindow (Get-CPProperty $limits $name.ToLowerInvariant()) $at
        if ($null -ne $window -and ($null -eq $Entry.$name -or $at -ge $Entry.$name.ObservedAt)) {
            $Entry.$name = $window
        }
    }
}

function Read-CPBlock {
    param($Reader, $Entry, [IO.FileStream]$Stream, [int]$MaxBytes, [switch]$Header)
    $count = [int][Math]::Min($MaxBytes, $Stream.Length - $Stream.Position)
    if ($count -le 0) { return 0 }
    $start = $Stream.Position
    $read = 0
    while ($read -lt $count) {
        $n = $Stream.Read($Reader.Buffer, $read, $count - $read)
        if ($n -le 0) { break }
        $read += $n
    }
    $Reader.Diagnostics.ReadBytes += $read
    if ($read -eq 0) { return 0 }
    if (-not $Header) { $Entry.AwaitingAppend = ($start + $read -ge $Stream.Length) }
    $end = [Array]::LastIndexOf($Reader.Buffer, [byte]10, $read - 1) + 1
    if ($end -eq 0) {
        if (-not $Header -and $read -eq $Reader.Buffer.Length) {
            # Bound memory even for an enormous tool-output JSON record.
            if (-not $Entry.SkipToNewLine) { $Reader.Diagnostics.OversizedLines++ }
            $Entry.SkipToNewLine = $true
            $Entry.Offset = $start + $read
        }
        return $read
    }
    $first = 0
    if (-not $Header -and $Entry.SkipToNewLine) {
        $first = [Array]::IndexOf($Reader.Buffer, [byte]10, 0, $end) + 1
        $Entry.SkipToNewLine = $false
    }
    if ($end -gt $first) {
        # Only decode newline-terminated records; a split UTF-8 character is reread later.
        $text = [Text.Encoding]::UTF8.GetString($Reader.Buffer, $first, $end - $first)
        foreach ($line in $text.Split([char]10)) { Read-CPLine $Reader $Entry $line }
    }
    if (-not $Header) { $Entry.Offset = $start + $end }
    return $read
}

function Read-CPFile {
    param($Reader, $Entry)
    $stream = $null
    $before = $Reader.Diagnostics.ReadBytes
    try {
        $info = New-Object IO.FileInfo $Entry.Path
        if (-not $info.Exists) { $Reader.Files.Remove($Entry.Path); return 0 }
        $Entry.LastWriteUtc = $info.LastWriteTimeUtc
        if ($Entry.Initialized -and ($info.Length -lt $Entry.LastLength -or $info.Length -lt $Entry.Offset -or
            $info.CreationTimeUtc -ne $Entry.CreationUtc -or
            ($info.Length -eq $Entry.LastLength -and $info.LastWriteTimeUtc -ne $Entry.LastReadWriteUtc))) {
            # Truncation/replacement invalidates per-file state rather than keeping phantom usage.
            $fresh = New-CPFileState $info
            foreach ($property in $fresh.PSObject.Properties) { $Entry.($property.Name) = $property.Value }
        }
        if ($Entry.Initialized -and $info.Length -eq $Entry.LastLength -and
            $Entry.Offset -ge $info.Length) { return 0 }
        if ($Entry.Initialized -and $info.Length -eq $Entry.LastLength -and
            $info.LastWriteTimeUtc -eq $Entry.LastReadWriteUtc -and $Entry.AwaitingAppend) { return 0 }
        $share = [IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete
        $stream = New-Object IO.FileStream($Entry.Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, $share)
        if (-not $Entry.Initialized) {
            if ($stream.Length -gt $Reader.InitialTailBytes) {
                [void](Read-CPBlock $Reader $Entry $stream (64 * 1024) -Header)
                $Entry.Offset = $stream.Length - $Reader.InitialTailBytes
                $Entry.SkipToNewLine = $true
            }
            $Entry.Initialized = $true
            $Entry.CreationUtc = $info.CreationTimeUtc
        }
        [void]$stream.Seek($Entry.Offset, [IO.SeekOrigin]::Begin)
        [void](Read-CPBlock $Reader $Entry $stream $Reader.Buffer.Length)
        $Entry.LastLength = $info.Length
        $Entry.LastReadWriteUtc = $info.LastWriteTimeUtc
    } catch {
        $Reader.Diagnostics.ReadErrors++
        $Reader.Diagnostics.LastError = 'Un journal est temporairement illisible.'
    } finally {
        if ($null -ne $stream) { $stream.Dispose() }
    }
    return $Reader.Diagnostics.ReadBytes - $before
}

function Update-CodexPillReader {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Reader, [switch]$ForceScan)
    $Reader.RootExists = [IO.Directory]::Exists($Reader.SessionsPath)
    if (-not $Reader.RootExists) {
        if ($null -ne $Reader.ScanEnumerator) { $Reader.ScanEnumerator.Dispose(); $Reader.ScanEnumerator = $null }
        $Reader.ScanDirectories.Clear()
        $Reader.ScanStarted = $false
        $Reader.Diagnostics.IsScanning = $false
        return
    }
    $now = [DateTimeOffset]::UtcNow
    if (-not $Reader.Seeded) {
        # Read current activity first even when the complete history is very large.
        foreach ($days in 0..2) {
            $date = $now.AddDays(-$days)
            $directory = Join-Path (Join-Path (Join-Path $Reader.SessionsPath $date.ToString('yyyy')) $date.ToString('MM')) $date.ToString('dd')
            if ([IO.Directory]::Exists($directory)) {
                $seed = $null
                try {
                    $seed = [IO.Directory]::EnumerateFiles($directory, 'rollout-*.jsonl').GetEnumerator()
                    $seedCount = 0
                    while ($seedCount -lt 256 -and $seed.MoveNext()) { Add-CPFile $Reader $seed.Current; $seedCount++ }
                } catch { $Reader.Diagnostics.ReadErrors++ }
                finally { if ($null -ne $seed) { $seed.Dispose() } }
            }
        }
        $Reader.Seeded = $true
    }
    if (-not $Reader.Diagnostics.IsScanning -and ($ForceScan -or -not $Reader.ScanStarted -or
        ($now - $Reader.ScanLastCompleted).TotalSeconds -ge 30)) {
        $Reader.ScanDirectories.Clear()
        $Reader.ScanDirectories.Push($Reader.SessionsPath)
        $Reader.ScanStarted = $true
        $Reader.Diagnostics.IsScanning = $true
    }
    $watch = [Diagnostics.Stopwatch]::StartNew()
    if ($Reader.Diagnostics.IsScanning) {
        $seen = 0
        while ($seen -lt 512 -and $watch.ElapsedMilliseconds -lt 120) {
            $seen++
            try {
                if ($null -eq $Reader.ScanEnumerator) {
                    if ($Reader.ScanDirectories.Count -gt 0) {
                        $directory = $Reader.ScanDirectories.Pop()
                        $Reader.ScanEnumerator = [IO.Directory]::EnumerateFileSystemEntries($directory).GetEnumerator()
                    } else {
                        $Reader.ScanLastCompleted = $now
                        $Reader.Diagnostics.IsScanning = $false
                        break
                    }
                }
                if (-not $Reader.ScanEnumerator.MoveNext()) {
                    $Reader.ScanEnumerator.Dispose()
                    $Reader.ScanEnumerator = $null
                    continue
                }
                $path = $Reader.ScanEnumerator.Current
                try { $attributes = [IO.File]::GetAttributes($path) }
                catch { $Reader.Diagnostics.ReadErrors++; continue }
                if (($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
                if (($attributes -band [IO.FileAttributes]::Directory) -ne 0) {
                    $Reader.ScanDirectories.Push($path)
                } elseif ([IO.Path]::GetFileName($path) -like 'rollout-*.jsonl') {
                    $Reader.Diagnostics.FilesDiscovered++
                    Add-CPFile $Reader $path
                }
            } catch {
                # One inaccessible directory must not prevent reading its siblings.
                if ($null -ne $Reader.ScanEnumerator) { $Reader.ScanEnumerator.Dispose(); $Reader.ScanEnumerator = $null }
                $Reader.Diagnostics.ReadErrors++
                $Reader.Diagnostics.LastError = 'Une partie du dossier des sessions est inaccessible.'
                if ($Reader.ScanDirectories.Count -eq 0) {
                    $Reader.ScanLastCompleted = $now
                    $Reader.Diagnostics.IsScanning = $false
                }
            }
        }
    }
    $entries = @($Reader.Files.Values | Sort-Object LastWriteUtc -Descending)
    $bytes = 0L
    $visited = 0
    # Reach the newest journal's tail before rotating through the other 95 files.
    # Otherwise four blocks per file could delay the current quota for many polls.
    if ($entries.Count -gt 0) {
        $priority = $entries[0]
        do {
            $priorityBytes = Read-CPFile $Reader $priority
            $bytes += $priorityBytes
        } while ($priorityBytes -gt 0 -and -not $priority.AwaitingAppend -and
            $priority.Offset -lt $priority.LastLength -and
            $bytes -lt (1024 * 1024) -and $watch.ElapsedMilliseconds -lt 300)
    }
    while ($visited -lt $entries.Count -and $bytes -lt (1024 * 1024) -and $watch.ElapsedMilliseconds -lt 300) {
        $index = ($Reader.ReadCursor + $visited) % $entries.Count
        if ($index -ne 0) { $bytes += Read-CPFile $Reader $entries[$index] }
        $visited++
    }
    if ($entries.Count -gt 0) { $Reader.ReadCursor = ($Reader.ReadCursor + $visited) % $entries.Count }
    $Reader.Diagnostics.FilesTracked = $Reader.Files.Count
    $Reader.Diagnostics.IsCatchingUp = @($Reader.Files.Values | Where-Object {
        -not $_.Initialized -or (-not $_.AwaitingAppend -and $_.Offset -lt $_.LastLength)
    }).Count -gt 0
}

function Copy-CPDisplayWindow {
    param($Value, [DateTimeOffset]$Now)
    if ($null -eq $Value) { return $null }
    $expired = $null -ne $Value.ResetAt -and $Value.ResetAt -le $Now
    [pscustomobject]@{
        UsedPercent = $Value.UsedPercent
        RemainingPercent = $Value.RemainingPercent
        ResetAt = $Value.ResetAt
        WindowMinutes = $Value.WindowMinutes
        IsExpired = $expired
        IsStale = ($Now - $Value.ObservedAt).TotalMinutes -ge 15
        ObservedAt = $Value.ObservedAt
    }
}

function Get-CodexPillSnapshot {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Reader)
    $now = [DateTimeOffset]::UtcNow
    $primary = $null
    $secondary = $null
    $activity = @()
    $lastUpdated = $null
    if ($Reader.RootExists) {
        $entries = @($Reader.Files.Values)
        foreach ($entry in $entries) {
            if ($null -ne $entry.Primary -and ($null -eq $primary -or $entry.Primary.ObservedAt -gt $primary.ObservedAt)) { $primary = $entry.Primary }
            if ($null -ne $entry.Secondary -and ($null -eq $secondary -or $entry.Secondary.ObservedAt -gt $secondary.ObservedAt)) { $secondary = $entry.Secondary }
        }
        # Some accounts expose their weekly quota in primary only. Do not duplicate it
        # with a secondary slot retained from an older observation.
        if ($null -ne $primary -and $null -ne $secondary -and $null -ne $primary.WindowMinutes -and
            $primary.WindowMinutes -eq $secondary.WindowMinutes) {
            if ($primary.ObservedAt -ge $secondary.ObservedAt) { $secondary = $null } else { $primary = $null }
        }
        foreach ($window in @($primary, $secondary)) {
            if ($null -ne $window -and ($null -eq $lastUpdated -or $window.ObservedAt -gt $lastUpdated)) { $lastUpdated = $window.ObservedAt }
        }
        $seen = @{}
        $activity = @($entries | Where-Object { $null -ne $_.LastActivity } | Sort-Object LastActivity -Descending | ForEach-Object {
            if (-not $seen.ContainsKey($_.SessionId)) {
                $seen[$_.SessionId] = $true
                $project = @($_.Cwd -split '[\\/]' | Where-Object { $_ }) | Select-Object -Last 1
                if ([string]::IsNullOrWhiteSpace([string]$project)) { $project = 'Sans projet' }
                [pscustomobject]@{ Project = [string]$project; SessionId = $_.SessionId; LastActivity = $_.LastActivity; TotalTokens = $_.TotalTokens; Path = $_.Path; Cwd = $_.Cwd }
            }
        } | Select-Object -First 8)
    }
    $primary = Copy-CPDisplayWindow $primary $now
    $secondary = Copy-CPDisplayWindow $secondary $now
    $status = 'Ready'
    if (-not $Reader.RootExists) { $status = 'Missing' }
    elseif ($Reader.Files.Count -eq 0) { $status = 'Empty' }
    elseif ($null -eq $primary -and $null -eq $secondary) { $status = 'Waiting' }
    elseif (($null -eq $primary -or $primary.IsExpired) -and ($null -eq $secondary -or $secondary.IsExpired)) { $status = 'Expired' }
    $lastProject = ''
    $lastSession = ''
    if ($activity.Count -gt 0) { $lastProject = $activity[0].Project; $lastSession = $activity[0].SessionId }
    [pscustomobject]@{
        Now = $now
        LastUpdated = $lastUpdated
        Status = $status
        Primary = $primary
        Secondary = $secondary
        LastProject = $lastProject
        LastSession = $lastSession
        Activity = $activity
        SourcePath = $Reader.SessionsPath
        Diagnostics = [pscustomobject]@{
            FilesTracked = $Reader.Diagnostics.FilesTracked
            FilesDiscovered = $Reader.Diagnostics.FilesDiscovered
            ParseErrors = $Reader.Diagnostics.ParseErrors
            ReadErrors = $Reader.Diagnostics.ReadErrors
            OversizedLines = $Reader.Diagnostics.OversizedLines
            ReadBytes = $Reader.Diagnostics.ReadBytes
            LastError = $Reader.Diagnostics.LastError
            IsScanning = $Reader.Diagnostics.IsScanning
            IsCatchingUp = $Reader.Diagnostics.IsCatchingUp
        }
    }
}

function Close-CodexPillReader {
    param($Reader)
    if ($null -ne $Reader -and $null -ne $Reader.ScanEnumerator) {
        $Reader.ScanEnumerator.Dispose()
        $Reader.ScanEnumerator = $null
    }
    if ($null -ne $Reader) { $Reader.ScanDirectories.Clear(); $Reader.Diagnostics.IsScanning = $false }
}
