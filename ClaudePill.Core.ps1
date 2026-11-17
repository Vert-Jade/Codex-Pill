# Claude Code statusLine reader. No credentials, transcript content or network.
# The official statusLine API supplies subscription percentages separately from
# context-window tokens. The latter must never be treated as quota consumption.

function Get-CLPProperty {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    if ($Object -is [Collections.IDictionary]) { return $Object[$Name] }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -ne $property) { return $property.Value }
    return $null
}

function ConvertTo-CLPNumber {
    param($Value)
    if ($null -eq $Value -or $Value -is [bool]) { return $null }
    $number = 0.0
    if ([double]::TryParse([string]$Value, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$number)) {
        if (-not [double]::IsNaN($number) -and -not [double]::IsInfinity($number)) { return $number }
    }
    return $null
}

function ConvertTo-CLPDate {
    param($Value)
    if ($null -eq $Value) { return $null }
    try {
        if ($Value -is [DateTimeOffset]) { return $Value.ToUniversalTime() }
        if ($Value -is [datetime]) { return ([DateTimeOffset]$Value).ToUniversalTime() }
        $seconds = 0L
        if ([long]::TryParse([string]$Value, [ref]$seconds)) {
            if ($seconds -gt 0) { return [DateTimeOffset]::FromUnixTimeSeconds($seconds) }
            return $null
        }
        return [DateTimeOffset]::Parse([string]$Value, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal).ToUniversalTime()
    } catch { return $null }
}

function Get-ClaudePillIntegrationState {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$ClaudeHome)
    $settingsPath = Join-Path $ClaudeHome 'settings.json'
    $manifestPath = Join-Path (Join-Path $ClaudeHome 'codex-pill') 'integration.json'
    $state = @{ Status = 'NotConfigured'; Message = 'Activer le suivi Claude Code pour recevoir les mesures.'; SettingsPath = $settingsPath; ClaudeHome = $ClaudeHome }
    try {
        if (-not [IO.File]::Exists($settingsPath)) { return [pscustomobject]$state }
        $settings = [IO.File]::ReadAllText($settingsPath, [Text.Encoding]::UTF8) | ConvertFrom-Json -ErrorAction Stop
        $statusLine = Get-CLPProperty $settings 'statusLine'
        if ($null -eq $statusLine) { return [pscustomobject]$state }
        $currentCommand = [string](Get-CLPProperty $statusLine 'command')
        if ([IO.File]::Exists($manifestPath)) {
            $manifest = [IO.File]::ReadAllText($manifestPath, [Text.Encoding]::UTF8) | ConvertFrom-Json -ErrorAction Stop
            if ($currentCommand -and $currentCommand -ceq [string](Get-CLPProperty $manifest 'OwnedCommand')) {
                $state.Status = 'Enabled'; $state.Message = 'Suivi Claude Code active.'
                return [pscustomobject]$state
            }
        }
        $state.Status = 'ExistingStatusLine'
        $state.Message = 'Claude Code possede deja une barre de statut personnalisee.'
    } catch {
        $state.Status = 'Error'; $state.Message = 'Les parametres Claude Code ne sont pas lisibles.'
    }
    return [pscustomobject]$state
}

# --- Source principale : service d'usage du compte Claude -------------------
# C'est la même source que la commande /usage de Claude Code. Elle couvre toute
# la consommation du compte (extension VS Code, terminal, web, mobile), alors
# que la barre de statut n'est exécutée que par Claude Code en terminal.
# Le jeton est relu à chaque appel dans le fichier local de Claude Code et
# envoyé uniquement à Anthropic ; il n'est jamais copié ailleurs ni journalisé.
$script:ClaudePillUsageEndpoint = 'https://api.anthropic.com/api/oauth/usage'
# Renouvellement : mêmes adresse, identifiant client et verrous que Claude Code
# (relevés dans Claude Code 2.1.322). Ce fichier n'est renouvelé que par les
# sessions VS Code ou terminal : l'application de bureau Claude utilise sa
# propre connexion. Après 8 h sans session VS Code, le jeton du fichier expire ;
# le widget le renouvelle alors comme le ferait une nouvelle session.
$script:ClaudePillTokenEndpoint = 'https://platform.claude.com/v1/oauth/token'
$script:ClaudePillClientId = '9d1c250a-e61b-44d9-88ed-5944d1962f5e'

function Get-ClaudePillPlanName {
    param([string]$SubscriptionType, [string]$Tier)
    if ([string]::IsNullOrWhiteSpace($SubscriptionType)) { return '' }
    $name = switch -Regex ($SubscriptionType.ToLowerInvariant()) {
        '^max' { 'Max'; break }
        '^pro' { 'Pro'; break }
        '^team' { 'Team'; break }
        '^enterprise' { 'Enterprise'; break }
        default { (Get-Culture).TextInfo.ToTitleCase($SubscriptionType) }
    }
    $multiplier = [regex]::Match([string]$Tier, '(\d+)x')
    if ($multiplier.Success) { $name += ' ' + $multiplier.Groups[1].Value + 'x' }
    return $name
}

function Get-ClaudePillCredential {
    param([string]$ClaudeHome)
    $path = Join-Path $ClaudeHome '.credentials.json'
    if (-not [IO.File]::Exists($path)) { return $null }
    try {
        $oauth = Get-CLPProperty ([IO.File]::ReadAllText($path, [Text.Encoding]::UTF8) | ConvertFrom-Json -ErrorAction Stop) 'claudeAiOauth'
        $token = [string](Get-CLPProperty $oauth 'accessToken')
        if ([string]::IsNullOrWhiteSpace($token)) { return $null }
        $expiresAt = $null
        $expiresMs = ConvertTo-CLPNumber (Get-CLPProperty $oauth 'expiresAt')
        if ($null -ne $expiresMs -and $expiresMs -gt 0) { $expiresAt = [DateTimeOffset]::FromUnixTimeMilliseconds([long]$expiresMs) }
        return [pscustomobject]@{
            Token = $token; ExpiresAt = $expiresAt
            Plan = Get-ClaudePillPlanName ([string](Get-CLPProperty $oauth 'subscriptionType')) ([string](Get-CLPProperty $oauth 'rateLimitTier'))
        }
    } catch { return $null }
}

function Invoke-ClaudePillUsageRequest {
    param([string]$Token)
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }
    $request = [Net.HttpWebRequest][Net.WebRequest]::Create($script:ClaudePillUsageEndpoint)
    $request.Method = 'GET'; $request.Timeout = 8000; $request.ReadWriteTimeout = 8000
    $request.Accept = 'application/json'; $request.UserAgent = 'codex-pill'
    $request.Headers['Authorization'] = 'Bearer ' + $Token
    $request.Headers['anthropic-beta'] = 'oauth-2025-04-20'
    $response = $null
    try {
        try { $response = $request.GetResponse() }
        catch [Net.WebException] {
            $failed = $_.Exception.Response
            $code = if ($null -ne $failed) { [int]$failed.StatusCode } else { 0 }
            if ($null -ne $failed) { $failed.Dispose() }
            return [pscustomobject]@{ StatusCode = $code; Body = $null }
        }
        $streamReader = [IO.StreamReader]::new($response.GetResponseStream(), [Text.Encoding]::UTF8)
        try { $body = $streamReader.ReadToEnd() } finally { $streamReader.Dispose() }
        return [pscustomobject]@{ StatusCode = [int]$response.StatusCode; Body = ($body | ConvertFrom-Json -ErrorAction Stop) }
    } finally { if ($null -ne $response) { $response.Dispose() } }
}

function Invoke-ClaudePillTokenRequest {
    param([hashtable]$Body)
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }
    $request = [Net.HttpWebRequest][Net.WebRequest]::Create($script:ClaudePillTokenEndpoint)
    $request.Method = 'POST'; $request.Timeout = 15000; $request.ReadWriteTimeout = 15000
    $request.ContentType = 'application/json'; $request.Accept = 'application/json'; $request.UserAgent = 'codex-pill'
    $payload = [Text.UTF8Encoding]::new($false).GetBytes(($Body | ConvertTo-Json -Compress))
    $request.ContentLength = $payload.Length
    $requestStream = $request.GetRequestStream()
    try { $requestStream.Write($payload, 0, $payload.Length) } finally { $requestStream.Dispose() }
    $response = $null
    try {
        try { $response = $request.GetResponse() }
        catch [Net.WebException] {
            $failed = $_.Exception.Response
            $code = if ($null -ne $failed) { [int]$failed.StatusCode } else { 0 }
            if ($null -ne $failed) { $failed.Dispose() }
            return [pscustomobject]@{ StatusCode = $code; Body = $null }
        }
        $streamReader = [IO.StreamReader]::new($response.GetResponseStream(), [Text.Encoding]::UTF8)
        try { $text = $streamReader.ReadToEnd() } finally { $streamReader.Dispose() }
        return [pscustomobject]@{ StatusCode = [int]$response.StatusCode; Body = ($text | ConvertFrom-Json -ErrorAction Stop) }
    } finally { if ($null -ne $response) { $response.Dispose() } }
}

function New-CLPLockDirectory {
    param([string]$Path)
    # Création atomique d'un dossier verrou, comme le module de verrouillage de
    # Claude Code : un dossier préparé à côté est renommé, ce qui échoue si le
    # verrou existe déjà. Un verrou existant n'est jamais repris par le widget.
    if ([IO.Directory]::Exists($Path) -or [IO.File]::Exists($Path)) { return $false }
    $staging = $Path + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
    [void][IO.Directory]::CreateDirectory($staging)
    try { [IO.Directory]::Move($staging, $Path); return $true }
    catch { try { [IO.Directory]::Delete($staging) } catch { }; return $false }
}

function Enter-ClaudePillRefreshLock {
    param([string]$ClaudeHome)
    $lockPaths = @((Join-Path $ClaudeHome '.oauth_refresh.lock'), ($ClaudeHome.TrimEnd('\', '/') + '.lock'))
    $acquired = New-Object Collections.ArrayList
    foreach ($lockPath in $lockPaths) {
        if (-not (New-CLPLockDirectory $lockPath)) { Exit-ClaudePillRefreshLock @($acquired); return $null }
        [void]$acquired.Add($lockPath)
    }
    return @($acquired)
}

function Exit-ClaudePillRefreshLock {
    param([string[]]$LockPaths)
    if ($null -eq $LockPaths) { return }
    [array]::Reverse($LockPaths)
    foreach ($lockPath in $LockPaths) { try { if ([IO.Directory]::Exists($lockPath)) { [IO.Directory]::Delete($lockPath, $false) } } catch { } }
}

function Invoke-ClaudePillTokenRefresh {
    # Renouvelle le jeton du fichier de connexion de Claude Code, uniquement s'il
    # a expiré (ou s'il vient d'être refusé), sous les verrous de Claude Code.
    # Résultats : Refreshed, AlreadyFresh, Busy, Rejected, RateLimited, Failed.
    param([Parameter(Mandatory=$true)][string]$ClaudeHome, [string]$RejectedAccessToken)
    $credentialPath = Join-Path $ClaudeHome '.credentials.json'
    if (-not [IO.File]::Exists($credentialPath)) { return 'Failed' }
    $lockPaths = Enter-ClaudePillRefreshLock $ClaudeHome
    if ($null -eq $lockPaths) { return 'Busy' }
    try {
        $document = [IO.File]::ReadAllText($credentialPath, [Text.Encoding]::UTF8) | ConvertFrom-Json -ErrorAction Stop
        $oauth = Get-CLPProperty $document 'claudeAiOauth'
        $postedRefreshToken = [string](Get-CLPProperty $oauth 'refreshToken')
        if ([string]::IsNullOrWhiteSpace($postedRefreshToken)) { return 'Rejected' }
        $nowMs = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        $expiresMs = ConvertTo-CLPNumber (Get-CLPProperty $oauth 'expiresAt')
        $storedAccessToken = [string](Get-CLPProperty $oauth 'accessToken')
        # Une autre session a peut-être déjà renouvelé pendant l'attente du verrou.
        if ($RejectedAccessToken) { if ($storedAccessToken -cne $RejectedAccessToken) { return 'AlreadyFresh' } }
        elseif ($null -ne $expiresMs -and $expiresMs -gt ($nowMs + 60000)) { return 'AlreadyFresh' }
        $scopes = @(Get-CLPProperty $oauth 'scopes' | Where-Object { $_ })
        $clientId = [string](Get-CLPProperty $oauth 'clientId')
        if ([string]::IsNullOrWhiteSpace($clientId)) { $clientId = $script:ClaudePillClientId }
        $body = @{ grant_type = 'refresh_token'; refresh_token = $postedRefreshToken; client_id = $clientId }
        if ($scopes.Count -gt 0) { $body.scope = ($scopes -join ' ') }
        $result = Invoke-ClaudePillTokenRequest $body
        if ($result.StatusCode -eq 400 -or $result.StatusCode -eq 401 -or $result.StatusCode -eq 403) { return 'Rejected' }
        if ($result.StatusCode -eq 429) { return 'RateLimited' }
        if ($result.StatusCode -ne 200 -or $null -eq $result.Body) { return 'Failed' }
        $newAccessToken = [string](Get-CLPProperty $result.Body 'access_token')
        $expiresIn = ConvertTo-CLPNumber (Get-CLPProperty $result.Body 'expires_in')
        if ([string]::IsNullOrWhiteSpace($newAccessToken) -or $null -eq $expiresIn -or $expiresIn -le 0) { return 'Failed' }
        $newRefreshToken = [string](Get-CLPProperty $result.Body 'refresh_token')
        if ([string]::IsNullOrWhiteSpace($newRefreshToken)) { $newRefreshToken = $postedRefreshToken }
        # Écriture seulement si personne n'a modifié la connexion entre-temps,
        # exactement comme Claude Code ; sinon la version existante est gardée.
        $current = [IO.File]::ReadAllText($credentialPath, [Text.Encoding]::UTF8) | ConvertFrom-Json -ErrorAction Stop
        $currentOauth = Get-CLPProperty $current 'claudeAiOauth'
        if ([string](Get-CLPProperty $currentOauth 'refreshToken') -cne $postedRefreshToken) { return 'AlreadyFresh' }
        $issuedMs = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        $currentOauth.accessToken = $newAccessToken
        $currentOauth.refreshToken = $newRefreshToken
        $currentOauth.expiresAt = [long]($issuedMs + $expiresIn * 1000)
        $refreshLifetime = ConvertTo-CLPNumber (Get-CLPProperty $result.Body 'refresh_token_expires_in')
        $previousRefreshExpiry = ConvertTo-CLPNumber (Get-CLPProperty $currentOauth 'refreshTokenExpiresAt')
        if ($null -ne $refreshLifetime -and $refreshLifetime -gt 0 -and $null -ne $previousRefreshExpiry) {
            $currentOauth.refreshTokenExpiresAt = [long][Math]::Min($previousRefreshExpiry, $issuedMs + $refreshLifetime * 1000)
        }
        $grantedScope = [string](Get-CLPProperty $result.Body 'scope')
        if ($grantedScope -and $null -ne $currentOauth.PSObject.Properties['scopes']) { $currentOauth.scopes = [string[]]($grantedScope -split '\s+' | Where-Object { $_ }) }
        $expectedScopes = @(Get-CLPProperty $currentOauth 'scopes').Count
        $serialized = $current | ConvertTo-Json -Depth 32 -Compress
        # Contrôle avant écriture : le texte produit doit se relire à l'identique.
        $check = Get-CLPProperty ($serialized | ConvertFrom-Json -ErrorAction Stop) 'claudeAiOauth'
        if ([string](Get-CLPProperty $check 'accessToken') -cne $newAccessToken -or [string](Get-CLPProperty $check 'refreshToken') -cne $newRefreshToken) { return 'Failed' }
        $checkScopes = $null
        if ($null -ne $check.PSObject.Properties['scopes']) { $checkScopes = $check.PSObject.Properties['scopes'].Value }
        if ($expectedScopes -gt 0 -and ($checkScopes -isnot [array] -or $checkScopes.Count -ne $expectedScopes)) { return 'Failed' }
        $temporaryPath = $credentialPath + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
        try {
            [IO.File]::WriteAllText($temporaryPath, $serialized, [Text.UTF8Encoding]::new($false))
            [IO.File]::Replace($temporaryPath, $credentialPath, [System.Management.Automation.Language.NullString]::Value)
        } finally { if ([IO.File]::Exists($temporaryPath)) { [IO.File]::Delete($temporaryPath) } }
        return 'Refreshed'
    } catch { return 'Failed' }
    finally { Exit-ClaudePillRefreshLock $lockPaths }
}

function ConvertFrom-ClaudePillUsageWindow {
    param($Value)
    $used = ConvertTo-CLPNumber (Get-CLPProperty $Value 'utilization')
    if ($null -eq $used) { return $null }
    $reset = ConvertTo-CLPDate (Get-CLPProperty $Value 'resets_at')
    $resetSeconds = $null
    if ($null -ne $reset) { $resetSeconds = $reset.ToUnixTimeSeconds() }
    return [pscustomobject]@{ used_percentage = [Math]::Max(0.0, [Math]::Min(100.0, $used)); resets_at = $resetSeconds }
}

function Update-ClaudePillUsage {
    param($Reader, [switch]$Force)
    $now = [DateTimeOffset]::UtcNow
    $credential = Get-ClaudePillCredential $Reader.ClaudeHome
    $Reader.HasCredential = $null -ne $credential
    if ($null -eq $credential) { $Reader.ApiError = 'NoCredential'; return }
    $Reader.Plan = $credential.Plan
    # Intervalle normal 60 s ; une actualisation manuelle est acceptée après 15 s.
    $minimumGap = if ($Force) { 15 } else { 60 }
    if ($null -ne $Reader.ApiLastAttempt -and ($now - $Reader.ApiLastAttempt).TotalSeconds -lt $minimumGap) { return }
    if ($null -ne $Reader.ApiRetryAfter -and $now -lt $Reader.ApiRetryAfter) { return }
    if ($null -ne $credential.ExpiresAt -and $credential.ExpiresAt -le $now) {
        # Jeton du fichier expiré : renouvellement comme une session Claude Code.
        if ($null -ne $Reader.RefreshRetryAfter -and $now -lt $Reader.RefreshRetryAfter) { return }
        $refreshOutcome = Invoke-ClaudePillTokenRefresh -ClaudeHome $Reader.ClaudeHome
        $Reader.LastRefreshOutcome = $refreshOutcome
        switch ($refreshOutcome) {
            'Busy' { $Reader.ApiError = 'Refreshing'; return }
            'Rejected' { $Reader.ApiError = 'LoginRequired'; $Reader.RefreshRetryAfter = $now.AddMinutes(10); return }
            'Failed' { $Reader.ApiError = 'Expired'; $Reader.RefreshRetryAfter = $now.AddMinutes(2); return }
            'RateLimited' { $Reader.ApiError = 'Expired'; $Reader.RefreshRetryAfter = $now.AddMinutes(10); return }
        }
        $credential = Get-ClaudePillCredential $Reader.ClaudeHome
        if ($null -eq $credential -or ($null -ne $credential.ExpiresAt -and $credential.ExpiresAt -le $now)) { $Reader.ApiError = 'Expired'; $Reader.RefreshRetryAfter = $now.AddMinutes(2); return }
        $Reader.RefreshRetryAfter = $null
    }
    $Reader.ApiLastAttempt = $now
    try {
        $result = Invoke-ClaudePillUsageRequest $credential.Token
        if ($result.StatusCode -eq 401 -and ($null -eq $Reader.RefreshRetryAfter -or $now -ge $Reader.RefreshRetryAfter)) {
            # Jeton refusé avant sa date d'expiration : un seul renouvellement, puis nouvel essai.
            $refreshOutcome = Invoke-ClaudePillTokenRefresh -ClaudeHome $Reader.ClaudeHome -RejectedAccessToken $credential.Token
            $Reader.LastRefreshOutcome = $refreshOutcome
            if ($refreshOutcome -eq 'Refreshed' -or $refreshOutcome -eq 'AlreadyFresh') {
                $credential = Get-ClaudePillCredential $Reader.ClaudeHome
                if ($null -ne $credential) { $result = Invoke-ClaudePillUsageRequest $credential.Token }
            } elseif ($refreshOutcome -eq 'Rejected' -or $refreshOutcome -eq 'RateLimited') { $Reader.RefreshRetryAfter = $now.AddMinutes(10) }
            elseif ($refreshOutcome -eq 'Failed') { $Reader.RefreshRetryAfter = $now.AddMinutes(2) }
        }
        if ($result.StatusCode -eq 200 -and $null -ne $result.Body) {
            $Reader.ApiRecord = [pscustomobject]@{
                Data = [pscustomobject]@{
                    five_hour = ConvertFrom-ClaudePillUsageWindow (Get-CLPProperty $result.Body 'five_hour')
                    seven_day = ConvertFrom-ClaudePillUsageWindow (Get-CLPProperty $result.Body 'seven_day')
                }
                ObservedAt = $now; CapturedAt = $now; Path = $script:ClaudePillUsageEndpoint
            }
            $Reader.ApiError = ''; $Reader.ApiRetryAfter = $null
        } elseif ($result.StatusCode -eq 401 -or $result.StatusCode -eq 403) {
            $Reader.ApiError = if ($Reader.LastRefreshOutcome -eq 'Rejected') { 'LoginRequired' } else { 'Expired' }
        } elseif ($result.StatusCode -eq 429) {
            $Reader.ApiError = 'RateLimited'; $Reader.ApiRetryAfter = $now.AddMinutes(5)
        } else { $Reader.ApiError = 'Unavailable' }
    } catch { $Reader.ApiError = 'Unavailable' }
}

# --- Activité récente : conversations locales de Claude Code ----------------
# Seuls l'heure de modification, le dossier du projet et le nom du modèle sont
# extraits de la fin des fichiers ; le contenu des messages n'est pas conservé.
function Format-ClaudePillModel {
    param([string]$ModelId)
    if ([string]::IsNullOrWhiteSpace($ModelId) -or $ModelId -notmatch '^claude-') { return '' }
    $parts = @(($ModelId -replace '^claude-', '' -replace '-\d{8}$', '') -split '-' | Where-Object { $_ })
    if ($parts.Count -eq 0) { return '' }
    $family = (Get-Culture).TextInfo.ToTitleCase($parts[0])
    $numbers = @($parts | Select-Object -Skip 1 | Where-Object { $_ -match '^\d+$' })
    if ($numbers.Count -gt 0) { return $family + ' ' + ($numbers -join '.') }
    return $family
}

function Get-ClaudePillTranscriptActivity {
    param([string]$ClaudeHome, [int]$Maximum = 3)
    $projectsDirectory = Join-Path $ClaudeHome 'projects'
    if (-not [IO.Directory]::Exists($projectsDirectory)) { return @() }
    $files = New-Object Collections.ArrayList
    try {
        foreach ($directory in [IO.Directory]::GetDirectories($projectsDirectory)) {
            foreach ($path in [IO.Directory]::GetFiles($directory, '*.jsonl')) { [void]$files.Add([IO.FileInfo]::new($path)) }
        }
    } catch { return @() }
    $items = New-Object Collections.ArrayList
    $seenProjects = @{}
    foreach ($file in @($files | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 16)) {
        if ($items.Count -ge $Maximum) { break }
        $cwd = ''; $model = ''
        $stream = $null
        try {
            $stream = [IO.FileStream]::new($file.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
            # Le dossier de départ de la conversation (début du fichier) identifie le
            # projet ; un « cwd » plus récent peut n'être qu'un sous-dossier visité.
            $headBuffer = New-Object byte[] ([Math]::Min($stream.Length, 65536L))
            $headCount = $stream.Read($headBuffer, 0, $headBuffer.Length)
            $headMatch = [regex]::Match([Text.Encoding]::UTF8.GetString($headBuffer, 0, $headCount), '"cwd"\s*:\s*"((?:[^"\\]|\\.)*)"')
            if ($headMatch.Success) { $cwd = [regex]::Unescape($headMatch.Groups[1].Value) }
            $tailLength = [Math]::Min($stream.Length, 131072L)
            [void]$stream.Seek(-$tailLength, [IO.SeekOrigin]::End)
            $buffer = New-Object byte[] $tailLength
            $readCount = $stream.Read($buffer, 0, $buffer.Length)
            $text = [Text.Encoding]::UTF8.GetString($buffer, 0, $readCount)
            $cwdMatches = [regex]::Matches($text, '"cwd"\s*:\s*"((?:[^"\\]|\\.)*)"')
            if (-not $cwd -and $cwdMatches.Count -gt 0) { $cwd = [regex]::Unescape($cwdMatches[$cwdMatches.Count - 1].Groups[1].Value) }
            $modelMatches = [regex]::Matches($text, '"model"\s*:\s*"(claude-[a-z0-9.\-]+)"')
            if ($modelMatches.Count -gt 0) { $model = Format-ClaudePillModel $modelMatches[$modelMatches.Count - 1].Groups[1].Value }
        } catch { continue }
        finally { if ($null -ne $stream) { $stream.Dispose() } }
        $project = @($cwd -split '[\\/]' | Where-Object { $_ }) | Select-Object -Last 1
        if ([string]::IsNullOrWhiteSpace([string]$project)) { continue }
        $projectKey = ([string]$cwd).ToLowerInvariant()
        if ($seenProjects.ContainsKey($projectKey)) { continue }
        $seenProjects[$projectKey] = $true
        [void]$items.Add([pscustomobject]@{
            Project = [string]$project; SessionId = $file.BaseName; LastActivity = [DateTimeOffset]$file.LastWriteTimeUtc
            TotalTokens = $null; ContextTokens = $null; TokenScope = 'none'; Detail = $model; Cwd = $cwd; Path = $file.FullName
        })
    }
    return @($items)
}

function New-ClaudePillReader {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$ClaudeHome, [string]$CacheDirectory, [switch]$Offline)
    $resolved = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($ClaudeHome))
    if ([string]::IsNullOrWhiteSpace($CacheDirectory)) { $CacheDirectory = Join-Path (Join-Path $resolved 'codex-pill') 'cache' }
    return [pscustomobject]@{
        ClaudeHome = $resolved; CacheDirectory = $CacheDirectory; Records = @(); RootExists = $false
        IntegrationState = 'NotConfigured'; LastError = ''; ParseErrors = 0L; FilesTracked = 0
        Offline = [bool]$Offline; HasCredential = $false; Plan = ''; ApiRecord = $null; ApiError = ''
        ApiLastAttempt = $null; ApiRetryAfter = $null; Activity = @(); ActivityScannedAt = $null
        RefreshRetryAfter = $null; LastRefreshOutcome = ''
    }
}

function Update-ClaudePillReader {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)]$Reader, [switch]$ForceScan)
    if (-not $Reader.Offline) { Update-ClaudePillUsage -Reader $Reader -Force:$ForceScan }
    $scanNow = [DateTimeOffset]::UtcNow
    if ($ForceScan -or $null -eq $Reader.ActivityScannedAt -or ($scanNow - $Reader.ActivityScannedAt).TotalSeconds -ge 20) {
        $Reader.Activity = @(Get-ClaudePillTranscriptActivity $Reader.ClaudeHome)
        $Reader.ActivityScannedAt = $scanNow
    }
    $Reader.RootExists = [IO.Directory]::Exists($Reader.CacheDirectory)
    $Reader.Records = @(); $Reader.FilesTracked = 0; $Reader.LastError = ''
    $Reader.IntegrationState = (Get-ClaudePillIntegrationState -ClaudeHome $Reader.ClaudeHome).Status
    if (-not $Reader.RootExists) { return }
    $records = New-Object Collections.ArrayList
    try {
        $files = @(Get-ChildItem -LiteralPath $Reader.CacheDirectory -Filter 'session-*.json' -File -ErrorAction Stop | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 32)
        foreach ($file in $files) {
            $stream = $null; $textReader = $null
            try {
                if ($file.Length -gt 65536 -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)) { continue }
                $stream = [IO.FileStream]::new($file.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
                $textReader = [IO.StreamReader]::new($stream, [Text.Encoding]::UTF8)
                $record = $textReader.ReadToEnd() | ConvertFrom-Json -ErrorAction Stop
                if ((Get-CLPProperty $record 'schema_version') -ne 1 -or (Get-CLPProperty $record 'provider') -ne 'claude') { continue }
                $capturedAt = ConvertTo-CLPDate (Get-CLPProperty $record 'captured_at')
                $observedAt = ConvertTo-CLPDate (Get-CLPProperty $record 'observed_at')
                if ($null -eq $capturedAt -or $null -eq $observedAt) { continue }
                [void]$records.Add([pscustomobject]@{ Data = $record; CapturedAt = $capturedAt; ObservedAt = $observedAt; Path = $file.FullName })
            } catch { $Reader.ParseErrors++; $Reader.LastError = 'Une mesure locale Claude est temporairement illisible.' }
            finally {
                if ($null -ne $textReader) { $textReader.Dispose() }
                elseif ($null -ne $stream) { $stream.Dispose() }
            }
        }
    } catch { $Reader.LastError = 'Le dossier de mesures Claude est inaccessible.' }
    # An idle older session may repaint later than a newer genuine measure.
    # Order account quotas by observation age, using receipt time only for ties.
    $Reader.Records = @($records | Sort-Object ObservedAt, CapturedAt -Descending)
    $Reader.FilesTracked = $Reader.Records.Count
}

function ConvertTo-CLPDisplayWindow {
    param($Value, [DateTimeOffset]$ObservedAt, [double]$Minutes, [DateTimeOffset]$Now)
    $used = ConvertTo-CLPNumber (Get-CLPProperty $Value 'used_percentage')
    if ($null -eq $used -or $used -lt 0) { return $null }
    $reset = ConvertTo-CLPDate (Get-CLPProperty $Value 'resets_at')
    return [pscustomobject]@{
        UsedPercent = [Math]::Min(100.0, $used); RemainingPercent = [Math]::Max(0, 100.0 - $used)
        ResetAt = $reset; WindowMinutes = $Minutes; ObservedAt = $ObservedAt
        IsExpired = ($null -ne $reset -and $reset -le $Now)
        IsStale = (($Now - $ObservedAt).TotalMinutes -ge 15)
    }
}

function Get-ClaudePillSnapshot {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)]$Reader)
    $now = [DateTimeOffset]::UtcNow
    $primary = $null; $secondary = $null; $lastUpdated = $null; $lastProject = ''; $lastSession = ''
    $status = 'Waiting'; $activity = @(); $source = ''
    # La mesure la plus récente gagne : service du compte ou barre de statut.
    $latest = $null
    if ($Reader.Records.Count -gt 0) { $latest = $Reader.Records[0]; $source = 'StatusLine' }
    if ($null -ne $Reader.ApiRecord -and ($null -eq $latest -or $Reader.ApiRecord.ObservedAt -ge $latest.ObservedAt)) { $latest = $Reader.ApiRecord; $source = 'Account' }
    if ($null -eq $latest -and -not $Reader.RootExists -and -not $Reader.HasCredential) { $status = 'Missing' }
    if ($null -ne $latest) {
        # A missing window in a newer statusLine event must NOT inherit a stale
        # window from another session/account: Claude removes expired windows.
        $primary = ConvertTo-CLPDisplayWindow (Get-CLPProperty $latest.Data 'five_hour') $latest.ObservedAt 300 $now
        $secondary = ConvertTo-CLPDisplayWindow (Get-CLPProperty $latest.Data 'seven_day') $latest.ObservedAt 10080 $now
        if ($null -ne $primary -or $null -ne $secondary) { $lastUpdated = $latest.ObservedAt; $status = 'Ready' }
        if ($status -eq 'Ready' -and ($null -eq $primary -or $primary.IsExpired) -and ($null -eq $secondary -or $secondary.IsExpired)) { $status = 'Expired' }
    }
    if (@($Reader.Activity).Count -gt 0) {
        $activity = @($Reader.Activity)
        $lastProject = $activity[0].Project; $lastSession = $activity[0].SessionId
    } elseif ($Reader.Records.Count -gt 0) {
        $activity = @($Reader.Records | Select-Object -First 8 | ForEach-Object {
            $cwd = [string](Get-CLPProperty $_.Data 'cwd')
            $project = @($cwd -split '[\\/]' | Where-Object { $_ }) | Select-Object -Last 1
            if ([string]::IsNullOrWhiteSpace([string]$project)) { $project = 'Sans projet' }
            [pscustomobject]@{
                Project = [string]$project; SessionId = [string](Get-CLPProperty $_.Data 'session_id')
                LastActivity = $_.ObservedAt; TotalTokens = $null; ContextTokens = Get-CLPProperty $_.Data 'context_tokens'
                TokenScope = 'context'; Cwd = $cwd; Path = $_.Path
            }
        })
        if ($activity.Count -gt 0) { $lastProject = $activity[0].Project; $lastSession = $activity[0].SessionId }
    }
    return [pscustomobject]@{
        Provider = 'Claude'; Now = $now; LastUpdated = $lastUpdated; Status = $status
        Primary = $primary; Secondary = $secondary; LastProject = $lastProject; LastSession = $lastSession
        Activity = $activity; SourcePath = $Reader.CacheDirectory; IntegrationState = $Reader.IntegrationState
        Source = $source; Plan = $Reader.Plan; HasCredential = $Reader.HasCredential; ApiError = $Reader.ApiError
        Diagnostics = [pscustomobject]@{
            FilesTracked = $Reader.FilesTracked; FilesDiscovered = $Reader.FilesTracked
            ParseErrors = $Reader.ParseErrors; ReadErrors = 0; OversizedLines = 0; ReadBytes = 0
            LastError = $Reader.LastError; IsScanning = $false; IsCatchingUp = $false
        }
    }
}

function Close-ClaudePillReader { param($Reader) }
