[CmdletBinding()]
param(
    [int]$IcySeconds = 120,
    [int]$ProbeSeconds = 20,
    [string]$FfprobePath = '',
    [string]$OutputRoot = ''
)

$ErrorActionPreference = 'Stop'


$titleHighlights = New-Object System.Collections.Generic.List[object]

function Protect-DiagnosticText {
    param([string]$Text)
    if ($null -eq $Text) { return '' }
    $safe = [regex]::Replace($Text, '(?i)\bhttps?://[^\s<>]+', '[URL omitted]')
    $safe = [regex]::Replace($safe, '(?i)\b(api[_-]?key|access[_-]?token|x-emby-token|token|password)\s*([=:])\s*([^\s&;,]+)', '$1$2[redacted]')
    $safe = [regex]::Replace($safe, '(?im)^(authorization\s*:\s*).+$', '$1[redacted]')
    return $safe
}

function Get-TitleClassification {
    param([string]$Title)
    if ([string]::IsNullOrWhiteSpace($Title)) { return 'Empty title' }
    if ($Title -match '(?i)\b(this station|station break|after this break|will continue after|commercial break|listen live|now playing|coming up next|station identification|visit our website|news bulletin)\b') {
        return 'Possible station message'
    }
    if ($Title -match '\s[-–—]\s') { return 'Song-like title format' }
    return 'Title found — review'
}

function Add-TitleHighlight {
    param(
        [string]$Source,
        [int]$BlockNumber,
        [string]$Title,
        [string]$Timestamp,
        [string]$Notes = ''
    )
    if ([string]::IsNullOrWhiteSpace($Title)) { return }
    $cleanTitle = Protect-DiagnosticText -Text ([System.Net.WebUtility]::HtmlDecode($Title).Trim())
    $classification = Get-TitleClassification -Title $cleanTitle
    $titleHighlights.Add([pscustomobject]@{
        Timestamp = $Timestamp
        Source = $Source
        BlockNumber = $BlockNumber
        Title = $cleanTitle
        Classification = $classification
        Notes = $Notes
    })
    if ($classification -eq 'Possible station message') {
        Write-Host ("`n[CHECK STATION MESSAGE] {0}" -f $cleanTitle) -ForegroundColor Yellow
    }
    else {
        Write-Host ("`n[TITLE FOUND] {0}" -f $cleanTitle) -ForegroundColor Green
    }
}

function Add-FFprobeTitleCandidatesFromNode {
    param($Node, [System.Collections.Generic.List[string]]$Found)
    if ($null -eq $Node -or $Node -is [string] -or $Node.GetType().IsPrimitive) { return }

    if ($Node -is [System.Collections.IDictionary]) {
        foreach ($key in $Node.Keys) {
            $value = $Node[$key]
            if ([string]$key -match '(?i)^(streamtitle|icy-title|songtitle|title)$' -and $value -is [string]) {
                $textValue = $value.Trim()
                if (-not [string]::IsNullOrWhiteSpace($textValue) -and -not $Found.Contains($textValue)) { [void]$Found.Add($textValue) }
            }
            if ($null -ne $value -and $value -isnot [string] -and -not $value.GetType().IsPrimitive) {
                Add-FFprobeTitleCandidatesFromNode -Node $value -Found $Found
            }
        }
        return
    }

    if ($Node -is [System.Collections.IEnumerable] -and $Node -isnot [string]) {
        foreach ($child in $Node) { Add-FFprobeTitleCandidatesFromNode -Node $child -Found $Found }
        return
    }

    foreach ($property in @($Node.PSObject.Properties)) {
        if ($property.Name -match '(?i)^(streamtitle|icy-title|songtitle|title)$' -and $property.Value -is [string]) {
            $textValue = $property.Value.Trim()
            if (-not [string]::IsNullOrWhiteSpace($textValue) -and -not $Found.Contains($textValue)) { [void]$Found.Add($textValue) }
        }
        $value = $property.Value
        if ($null -ne $value -and $value -isnot [string] -and -not $value.GetType().IsPrimitive) {
            Add-FFprobeTitleCandidatesFromNode -Node $value -Found $Found
        }
    }
}

function Get-FFprobeTitleCandidates {
    param([string]$JsonText)
    $found = New-Object System.Collections.Generic.List[string]
    if ([string]::IsNullOrWhiteSpace($JsonText)) { return @() }
    try { $root = ConvertFrom-Json -InputObject $JsonText -ErrorAction Stop }
    catch { return @() }
    Add-FFprobeTitleCandidatesFromNode -Node $root -Found $found
    return @($found.ToArray())
}

function Write-TitleHighlightReport {
    param([string]$Directory, [System.Collections.Generic.List[object]]$Events)
    $rows = New-Object System.Collections.Generic.List[string]
    foreach ($event in $Events) {
        $class = 'review'
        if ($event.Classification -eq 'Song-like title format') { $class = 'song' }
        elseif ($event.Classification -eq 'Possible station message') { $class = 'warning' }
        $timestamp = [System.Net.WebUtility]::HtmlEncode([string]$event.Timestamp)
        $source = [System.Net.WebUtility]::HtmlEncode([string]$event.Source)
        $block = if ([int]$event.BlockNumber -gt 0) { [System.Net.WebUtility]::HtmlEncode([string]$event.BlockNumber) } else { '—' }
        $title = [System.Net.WebUtility]::HtmlEncode([string]$event.Title)
        $classification = [System.Net.WebUtility]::HtmlEncode([string]$event.Classification)
        $notes = [System.Net.WebUtility]::HtmlEncode([string]$event.Notes)
        $rows.Add("<article class=`"event $class`"><div class=`"meta`"><span>$timestamp</span><span>$source</span><span>Block $block</span></div><h2>$title</h2><div class=`"classification`">$classification</div><p>$notes</p></article>")
    }
    if ($rows.Count -eq 0) {
        $rows.Add('<p class="empty">No non-empty ICY StreamTitle or FFprobe title fields were detected during this capture.</p>')
    }
    $html = @"
<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Radio Meta — Title Highlights</title>
<style>
:root{color-scheme:dark}body{margin:0;padding:24px;background:#17191d;color:#f3f4f6;font:16px/1.5 system-ui,Segoe UI,Arial,sans-serif}main{max-width:1050px;margin:auto}h1{margin:0 0 6px;font-size:1.7rem}header p{color:#c2c8cf;margin:0 0 20px}.legend{display:flex;flex-wrap:wrap;gap:8px;margin:14px 0 20px}.legend span,.classification{font-weight:700;font-size:.85rem}.legend span{padding:4px 9px;border:1px solid #555;border-radius:99px}.event{border:1px solid #454a53;border-left:5px solid #4aa76a;border-radius:8px;padding:13px 16px;margin:10px 0;background:#202329}.event h2{font-size:1.15rem;line-height:1.3;margin:8px 0;color:#69d68b;overflow-wrap:anywhere}.event.song{border-left-color:#399ded}.event.song h2{color:#75bdff}.event.review{border-left-color:#43b66a}.event.warning{border-left-color:#e1a12e;background:#27241e}.event.warning h2,.event.warning .classification{color:#ffc65d}.meta{display:flex;flex-wrap:wrap;gap:7px 14px;color:#b9c0c9;font-size:.82rem}.event p{margin:5px 0 0;color:#c9ced5;font-size:.9rem}.empty{padding:18px;border:1px dashed #666;border-radius:8px;color:#c2c8cf}
</style></head><body><main><header><h1>Radio Meta — Title Highlights</h1><p>Detected title-like values are shown prominently. Amber entries may be station messages; ordinary song titles are not automatically classified as invalid.</p><div class="legend"><span>Green: title found / review</span><span style="color:#75bdff">Blue: song-like format</span><span style="color:#ffc65d">Amber: possible station message</span></div></header>
$($rows -join "`n")
</main></body></html>
"@
    $path = Join-Path $Directory '04-title-highlights.html'
    Set-Content -LiteralPath $path -Value $html -Encoding UTF8
    return $path
}

trap {
    $fatalMessage = Protect-DiagnosticText -Text ('Fatal script error: ' + $_.Exception.ToString())
    if (-not [string]::IsNullOrWhiteSpace($outDir) -and (Test-Path -LiteralPath $outDir -PathType Container)) {
        try {
            Add-Content -LiteralPath (Join-Path $outDir '03-ffprobe-diagnostics.txt') -Value $fatalMessage -Encoding UTF8
            Set-Content -LiteralPath (Join-Path $outDir '00-SUMMARY.txt') -Value @(
                'Radio Meta stream diagnostic',
                ('Failed: {0}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')),
                ('Results folder: {0}' -f $outDir),
                'Status: FAILED before final report generation.',
                $fatalMessage
            ) -Encoding UTF8
        } catch { }
    }
    Write-Host $fatalMessage -ForegroundColor Red
    exit 1
}

function Get-SafeUrlText {
    param([Uri]$Uri)
    $portText = ''
    if (-not $Uri.IsDefaultPort) { $portText = ':' + $Uri.Port }
    # Deliberately omit URL username/password and query parameters from saved logs.
    return ('{0}://{1}{2}{3}{4}' -f $Uri.Scheme, $Uri.Host, $portText, $Uri.AbsolutePath, $(if ($Uri.Query) { '?[query redacted]' } else { '' }))
}

function Read-ExactBytes {
    param(
        [System.IO.Stream]$Stream,
        [int]$Count,
        [System.Threading.CancellationToken]$Token
    )
    $buffer = New-Object byte[] $Count
    $offset = 0
    while ($offset -lt $Count) {
        $read = $Stream.ReadAsync($buffer, $offset, ($Count - $offset), $Token).GetAwaiter().GetResult()
        if ($read -le 0) { return $null }
        $offset += $read
    }
    return ,$buffer
}

function Read-DiscardBytes {
    param(
        [System.IO.Stream]$Stream,
        [int]$Count,
        [System.Threading.CancellationToken]$Token
    )
    $remaining = $Count
    while ($remaining -gt 0) {
        $size = [Math]::Min(8192, $remaining)
        $buffer = New-Object byte[] $size
        $read = $Stream.ReadAsync($buffer, 0, $size, $Token).GetAwaiter().GetResult()
        if ($read -le 0) { return $false }
        $remaining -= $read
    }
    return $true
}

function Get-HeaderValue {
    param([System.Net.Http.HttpResponseMessage]$Response, [string]$Name)
    foreach ($header in $Response.Headers) {
        if ($header.Key -ieq $Name) { return (@($header.Value) -join ', ') }
    }
    foreach ($header in $Response.Content.Headers) {
        if ($header.Key -ieq $Name) { return (@($header.Value) -join ', ') }
    }
    return $null
}

function Quote-WindowsArgument {
    param([AllowEmptyString()][string]$Value)
    if ($null -eq $Value) { $Value = '' }
    if ($Value.Length -gt 0 -and $Value -notmatch '[\s"]') { return $Value }

    $builder = New-Object System.Text.StringBuilder
    [void]$builder.Append([char]34)
    $backslashes = 0
    foreach ($character in $Value.ToCharArray()) {
        if ([int]$character -eq 92) {
            $backslashes++
            continue
        }
        if ([int]$character -eq 34) {
            for ($i = 0; $i -lt (($backslashes * 2) + 1); $i++) { [void]$builder.Append([char]92) }
            [void]$builder.Append([char]34)
        }
        else {
            for ($i = 0; $i -lt $backslashes; $i++) { [void]$builder.Append([char]92) }
            [void]$builder.Append($character)
        }
        $backslashes = 0
    }
    for ($i = 0; $i -lt ($backslashes * 2); $i++) { [void]$builder.Append([char]92) }
    [void]$builder.Append([char]34)
    return $builder.ToString()
}

function Redact-StreamUrl {
    param([string]$Text, [string]$OriginalUrl, [Uri]$Uri)
    if ($null -eq $Text) { return '' }
    $safe = $Text
    if (-not [string]::IsNullOrEmpty($OriginalUrl)) { $safe = $safe.Replace($OriginalUrl, '[STREAM URL REDACTED]') }
    if ($Uri) { $safe = $safe.Replace($Uri.AbsoluteUri, '[STREAM URL REDACTED]') }
    # Redact redirect/location URLs too, not only the exact URL the user entered.
    $safe = [regex]::Replace($safe, '(?i)\bhttps?://[^\s<>]+', '[URL omitted]')
    $safe = [regex]::Replace($safe, '(?i)\b(api[_-]?key|access[_-]?token|x-emby-token|token|password)\s*([=:])\s*([^\s&;,]+)', '$1$2[redacted]')
    $safe = [regex]::Replace($safe, '(?im)^(authorization\s*:\s*).+$', '$1[redacted]')
    return $safe
}

function Save-IcyProgress {
    param(
        [System.Collections.Generic.List[string]]$Lines,
        [string]$OutputPath,
        [string]$OriginalUrl,
        [Uri]$Uri
    )
    $text = $Lines -join [Environment]::NewLine
    $text = Redact-StreamUrl -Text $text -OriginalUrl $OriginalUrl -Uri $Uri
    Set-Content -LiteralPath $OutputPath -Value $text -Encoding UTF8
}

Write-Host ''
Write-Host 'Radio Meta — ICY + ffprobe stream diagnostic' -ForegroundColor Cyan
Write-Host 'This is read-only. It does not change Emby or Radio Meta.'
Write-Host 'Detected titles are highlighted in the console and saved to 04-title-highlights.html.'
Write-Host 'The stream URL is not written verbatim to the report; URL query parameters are omitted.'
Write-Host ''

$streamUrl = Read-Host 'Paste the full radio stream URL (http:// or https://)'
if ([string]::IsNullOrWhiteSpace($streamUrl)) {
    Write-Host 'No URL entered. Exiting.' -ForegroundColor Yellow
    exit 1
}

try {
    $streamUri = [Uri]$streamUrl
    if (-not $streamUri.IsAbsoluteUri -or @('http', 'https') -notcontains $streamUri.Scheme.ToLowerInvariant()) {
        throw 'URL must be an absolute HTTP or HTTPS address.'
    }
}
catch {
    Write-Host ('Invalid URL: ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}

if ($IcySeconds -lt 20 -or $IcySeconds -gt 600) {
    $IcySeconds = 120
}
if ($ProbeSeconds -lt 5 -or $ProbeSeconds -gt 60) {
    $ProbeSeconds = 20
}

# Portable output: default to a Results folder beside this script. If that location
# is read-only, fall back to Desktop, then TEMP. An explicit -OutputRoot takes priority.
$desktop = [Environment]::GetFolderPath('Desktop')
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $preferredRoot = Join-Path $PSScriptRoot 'Results'
}
else {
    $preferredRoot = $OutputRoot
}
try {
    New-Item -ItemType Directory -Path $preferredRoot -Force -ErrorAction Stop | Out-Null
    $outputBase = (Resolve-Path -LiteralPath $preferredRoot).Path
}
catch {
    if (-not [string]::IsNullOrWhiteSpace($desktop)) {
        $outputBase = Join-Path $desktop 'RadioMeta-Stream-Diagnostics'
    }
    else {
        $outputBase = Join-Path $env:TEMP 'RadioMeta-Stream-Diagnostics'
    }
    New-Item -ItemType Directory -Path $outputBase -Force -ErrorAction Stop | Out-Null
    Write-Host ('Could not write to the preferred output path. Using: {0}' -f $outputBase) -ForegroundColor Yellow
}
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$outDir = Join-Path $outputBase ('RadioMeta-Stream-Diagnostics-' + $stamp)
New-Item -ItemType Directory -Path $outDir -Force -ErrorAction Stop | Out-Null
$icyPath = Join-Path $outDir '01-icy-headers-and-metadata.txt'
$safeUrl = Get-SafeUrlText -Uri $streamUri

# Create all report files immediately. If the run is interrupted, these placeholders
# explain that the capture did not finish instead of leaving an empty folder.
$startText = @(
    'Radio Meta stream diagnostic',
    ('Started: {0}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')),
    ('Endpoint: {0}' -f $safeUrl),
    ('Requested ICY duration: {0} seconds' -f $IcySeconds),
    ('Requested FFprobe duration: {0} seconds' -f $ProbeSeconds),
    'Status: RUNNING. If this file still says RUNNING after the script exits, the run ended before reports were finalized.',
    ''
) -join [Environment]::NewLine
Set-Content -LiteralPath (Join-Path $outDir '00-SUMMARY.txt') -Value $startText -Encoding UTF8
Set-Content -LiteralPath $icyPath -Value 'ICY capture is pending or incomplete. See 00-SUMMARY.txt.' -Encoding UTF8
Set-Content -LiteralPath (Join-Path $outDir '02-ffprobe-output.json') -Value 'FFprobe has not run yet.' -Encoding UTF8
Set-Content -LiteralPath (Join-Path $outDir '03-ffprobe-diagnostics.txt') -Value 'FFprobe diagnostics have not been generated yet.' -Encoding UTF8
Write-Host ('Results will be written to: {0}' -f $outDir) -ForegroundColor Cyan

$summary = New-Object System.Collections.Generic.List[string]
$summary.Add('Radio Meta stream diagnostic')
$summary.Add(('Started: {0}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')))
$summary.Add(('Endpoint: {0}' -f $safeUrl))
$summary.Add(('ICY capture requested: {0} seconds' -f $IcySeconds))
$summary.Add(('ffprobe capture requested: {0} seconds' -f $ProbeSeconds))
$summary.Add('URL credentials and query parameters are intentionally omitted from the summary.')
$summary.Add('')

# --- ICY headers and in-band StreamTitle metadata ---
$icyReport = New-Object System.Collections.Generic.List[string]
$icyReport.Add('ICY/HTTP response and in-band metadata capture')
$icyReport.Add(('Requested endpoint: {0}' -f $safeUrl))
$icyReport.Add(('Capture started: {0}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')))
$icyReport.Add('')

$client = $null
$response = $null
$captureCts = $null
try {
    Add-Type -AssemblyName System.Net.Http
    $handler = New-Object System.Net.Http.HttpClientHandler
    $handler.AllowAutoRedirect = $true
    $client = [System.Net.Http.HttpClient]::new($handler)
    $client.Timeout = [TimeSpan]::FromSeconds(20)

    $request = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Get, $streamUri)
    [void]$request.Headers.TryAddWithoutValidation('Icy-MetaData', '1')
    [void]$request.Headers.TryAddWithoutValidation('User-Agent', 'RadioMeta-StreamDiagnostic/1.0')
    [void]$request.Headers.TryAddWithoutValidation('Accept', '*/*')

    Write-Host ('Requesting ICY headers from {0} ...' -f $safeUrl) -ForegroundColor Cyan
    $response = $client.SendAsync($request, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
    $icyReport.Add(('HTTP status: {0} {1}' -f [int]$response.StatusCode, $response.ReasonPhrase))
    $icyReport.Add(('Final endpoint: {0}' -f (Get-SafeUrlText -Uri $response.RequestMessage.RequestUri)))
    $icyReport.Add('Response headers:')

    foreach ($header in $response.Headers) {
        $headerValue = @($header.Value) -join ', '
        if ($header.Key -ieq 'Location') { $headerValue = '[redirect URL omitted]' }
        if ($header.Key -ieq 'Set-Cookie') { $headerValue = '[cookie omitted]' }
        $icyReport.Add(('  {0}: {1}' -f $header.Key, $headerValue))
    }
    foreach ($header in $response.Content.Headers) {
        $headerValue = @($header.Value) -join ', '
        $icyReport.Add(('  {0}: {1}' -f $header.Key, $headerValue))
    }
    # Save headers immediately so the report is useful even if the stream read is interrupted.
    Save-IcyProgress -Lines $icyReport -OutputPath $icyPath -OriginalUrl $streamUrl -Uri $streamUri

    $metaIntText = Get-HeaderValue -Response $response -Name 'icy-metaint'
    $icyReport.Add('')
    if ($metaIntText -and $metaIntText -match '^\d+$' -and [int]$metaIntText -gt 0) {
        $metaInt = [int]$metaIntText
        $icyReport.Add(('ICY metadata interval: {0} audio bytes' -f $metaInt))
        $icyReport.Add(('Reading ICY metadata for up to {0} seconds...' -f $IcySeconds))
        $stream = $response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
        $captureCts = New-Object System.Threading.CancellationTokenSource
        $captureCts.CancelAfter([TimeSpan]::FromSeconds($IcySeconds))
        $token = $captureCts.Token
        $blocks = 0
        $changes = 0
        $emptyBlocks = 0
        $lastMetadata = $null
        $encoding = [System.Text.Encoding]::GetEncoding(28591)

        try {
            while ($true) {
                if (-not (Read-DiscardBytes -Stream $stream -Count $metaInt -Token $token)) { break }
                $lengthByte = Read-ExactBytes -Stream $stream -Count 1 -Token $token
                if ($null -eq $lengthByte) { break }
                $blocks++
                $metadataLength = ([int]$lengthByte[0]) * 16
                if ($metadataLength -le 0) {
                    $emptyBlocks++
                    if ($lastMetadata -ne '') { $lastMetadata = '' }
                    continue
                }
                $metadataBytes = Read-ExactBytes -Stream $stream -Count $metadataLength -Token $token
                if ($null -eq $metadataBytes) { break }
                $metadataText = $encoding.GetString($metadataBytes)
                $metadataText = [regex]::Replace($metadataText, '[\x00]+$', '').Trim()
                if ([string]::IsNullOrWhiteSpace($metadataText)) { continue }

                if ($metadataText -ne $lastMetadata) {
                    $changes++
                    $lastMetadata = $metadataText
                    # ICY title values can contain apostrophes. Prefer the closing quote before StreamUrl.
                    $titleMatch = [regex]::Match($metadataText, "(?is)StreamTitle\s*=\s*'(?<value>.*?)(?='\s*;\s*(?:StreamUrl\s*=|$))")
                    if (-not $titleMatch.Success) {
                        $titleMatch = [regex]::Match($metadataText, "(?is)StreamTitle\s*=\s*'(?<value>.*)'")
                    }
                    $icyReport.Add(('[{0}] metadata change #{1} (block {2})' -f (Get-Date -Format 'HH:mm:ss.fff'), $changes, $blocks))
                    if ($titleMatch.Success) {
                        $titleValue = $titleMatch.Groups['value'].Value.Trim()
                        $safeTitleValue = Protect-DiagnosticText -Text $titleValue
                        $icyReport.Add(('  StreamTitle: {0}' -f $safeTitleValue))
                        Add-TitleHighlight -Source 'ICY StreamTitle' -BlockNumber $blocks -Title $titleValue -Timestamp (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff') -Notes ('ICY metadata change #{0}' -f $changes)
                    }
                    else {
                        $icyReport.Add('  StreamTitle: (no field found)')
                    }
                    # Do not save a StreamUrl field; it can reveal a different private URL.
                    if ($metadataText -match '(?i)StreamUrl\s*=') { $icyReport.Add('  StreamUrl: [omitted for privacy]') }
                    $rawSafe = [regex]::Replace($metadataText, '(?i)(StreamUrl\s*=\s*)(?:''[^'']*''|"[^"]*"|[^;]*)', '$1[omitted]')
                    $rawSafe = Protect-DiagnosticText -Text $rawSafe
                    $icyReport.Add(('  Raw: {0}' -f $rawSafe))
                    Save-IcyProgress -Lines $icyReport -OutputPath $icyPath -OriginalUrl $streamUrl -Uri $streamUri
                }
            }
        }
        catch [System.OperationCanceledException] {
            $icyReport.Add(('ICY capture reached its {0}-second time limit.' -f $IcySeconds))
        }
        catch {
            $icyReport.Add(('ICY body read ended with: {0}' -f $_.Exception.Message))
        }
        $icyReport.Add('')
        $icyReport.Add(('Metadata blocks read: {0}' -f $blocks))
        $icyReport.Add(('Empty metadata blocks: {0}' -f $emptyBlocks))
        $icyReport.Add(('Distinct consecutive metadata values logged: {0}' -f $changes))
        if ($changes -eq 0) { $icyReport.Add('No non-empty ICY StreamTitle metadata was observed during this capture.') }
    }
    else {
        $icyReport.Add('The server did not provide a positive icy-metaint response header.')
        $icyReport.Add('HTTP headers were captured, but in-band ICY blocks could not be parsed by this script.')
    }
}
catch {
    $icyReport.Add(('ICY request/capture error: {0}' -f $_.Exception.ToString()))
    $summary.Add(('ICY capture error: {0}' -f $_.Exception.Message))
}
finally {
    if ($captureCts) { $captureCts.Dispose() }
    if ($response) { $response.Dispose() }
    if ($client) { $client.Dispose() }
}

# Redact the exact URL entered by the user before saving logs, in case ffprobe echoes it.
$icyText = $icyReport -join [Environment]::NewLine
$icyText = Redact-StreamUrl -Text $icyText -OriginalUrl $streamUrl -Uri $streamUri
Set-Content -LiteralPath $icyPath -Value $icyText -Encoding UTF8
$summary.Add('ICY capture: 01-icy-headers-and-metadata.txt')
$summary.Add('Titles detected during capture are highlighted in green/blue; suspected station messages appear amber in 04-title-highlights.html.')

# --- Locate ffprobe ---
$resolvedFfprobe = $null
if (-not [string]::IsNullOrWhiteSpace($FfprobePath) -and (Test-Path -LiteralPath $FfprobePath -PathType Leaf)) {
    $resolvedFfprobe = (Resolve-Path -LiteralPath $FfprobePath).Path
}
if (-not $resolvedFfprobe) {
    $command = Get-Command 'ffprobe.exe' -ErrorAction SilentlyContinue
    if (-not $command) { $command = Get-Command 'ffprobe' -ErrorAction SilentlyContinue }
    if ($command) { $resolvedFfprobe = $command.Source }
}
if (-not $resolvedFfprobe) {
    $candidates = New-Object System.Collections.Generic.List[string]
    $candidates.Add((Join-Path $PSScriptRoot 'ffprobe.exe'))
    $candidates.Add((Join-Path $PSScriptRoot 'tools\ffprobe.exe'))
    if ($env:APPDATA) { $candidates.Add((Join-Path $env:APPDATA 'Emby-Server\system\ffprobe.exe')) }
    if ($env:ProgramFiles) { $candidates.Add((Join-Path $env:ProgramFiles 'ffmpeg\bin\ffprobe.exe')) }
    if (Test-Path 'C:\ffmpeg\bin\ffprobe.exe') { $candidates.Add('C:\ffmpeg\bin\ffprobe.exe') }
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { $resolvedFfprobe = (Resolve-Path -LiteralPath $candidate).Path; break }
    }
}
if (-not $resolvedFfprobe) {
    $manualPath = Read-Host 'ffprobe.exe was not found. Enter its full path, or press Enter to skip ffprobe'
    if (-not [string]::IsNullOrWhiteSpace($manualPath) -and (Test-Path -LiteralPath $manualPath -PathType Leaf)) {
        $resolvedFfprobe = (Resolve-Path -LiteralPath $manualPath).Path
    }
}

if ($resolvedFfprobe) {
    Write-Host ('Running ffprobe for up to {0} seconds...' -f $ProbeSeconds) -ForegroundColor Cyan
    $stdoutPath = Join-Path $outDir '02-ffprobe-output.json'
    $stderrPath = Join-Path $outDir '03-ffprobe-diagnostics.txt'
    $probeArgs = @(
        '-hide_banner', '-loglevel', 'info',
        '-rw_timeout', '15000000',
        '-analyzeduration', '5000000',
        '-probesize', '5000000',
        '-read_intervals', ('%+' + $ProbeSeconds),
        '-show_streams', '-show_format', '-of', 'json',
        '-i', $streamUrl
    )
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $resolvedFfprobe
        $psi.Arguments = (($probeArgs | ForEach-Object { Quote-WindowsArgument -Value ([string]$_) }) -join ' ')
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true

        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $psi
        [void]$process.Start()
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $timeoutMs = ($ProbeSeconds + 20) * 1000
        $timedOut = -not $process.WaitForExit($timeoutMs)
        if ($timedOut) {
            try { $process.Kill() } catch {}
            $process.WaitForExit()
        }
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        $exitCode = if ($timedOut) { 'TIMEOUT' } else { [string]$process.ExitCode }
        $ffprobeTitles = @(Get-FFprobeTitleCandidates -JsonText $stdout)
        foreach ($candidateTitle in $ffprobeTitles) {
            Add-TitleHighlight -Source 'FFprobe metadata' -BlockNumber 0 -Title ([string]$candidateTitle) -Timestamp (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff') -Notes ('FFprobe exit status: {0}' -f $exitCode)
        }
        if (-not $ffprobeTitles.Count) {
            Write-Host 'FFprobe did not expose a title-like tag in its JSON output.' -ForegroundColor DarkGray
        }
        $safeStdout = Redact-StreamUrl -Text $stdout -OriginalUrl $streamUrl -Uri $streamUri
        $safeStderr = Redact-StreamUrl -Text $stderr -OriginalUrl $streamUrl -Uri $streamUri
        Set-Content -LiteralPath $stdoutPath -Value $safeStdout -Encoding UTF8
        Set-Content -LiteralPath $stderrPath -Value $safeStderr -Encoding UTF8
        $summary.Add('ffprobe executable: found (local path omitted)')
        $summary.Add(('ffprobe exit status: {0}' -f $exitCode))
        $summary.Add('ffprobe JSON: 02-ffprobe-output.json')
        $summary.Add('ffprobe diagnostics: 03-ffprobe-diagnostics.txt')
        $process.Dispose()
    }
    catch {
        $message = 'ffprobe could not complete: ' + $_.Exception.ToString()
        Set-Content -LiteralPath (Join-Path $outDir '03-ffprobe-diagnostics.txt') -Value $message -Encoding UTF8
        $summary.Add($message)
    }
}
else {
    $summary.Add('ffprobe was skipped because ffprobe.exe was not found or supplied.')
    Set-Content -LiteralPath (Join-Path $outDir '02-ffprobe-output.json') -Value 'ffprobe skipped.' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $outDir '03-ffprobe-diagnostics.txt') -Value 'Install FFmpeg or rerun the script and enter the path to ffprobe.exe.' -Encoding UTF8
}

$titleReportPath = Write-TitleHighlightReport -Directory $outDir -Events $titleHighlights
$summary.Add(('Title highlights report: {0}' -f (Split-Path -Leaf $titleReportPath)))
$summary.Add(('Distinct title-like values highlighted: {0}' -f $titleHighlights.Count))
$summary.Add('')
$summary.Add(('Finished: {0}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')))
$summary.Add('Status: COMPLETE')
$summary.Add(('Results folder: {0}' -f $outDir))
$summary.Add('Before sharing logs, review them for any private station details. The supplied stream URL and its query parameters are redacted where echoed exactly.')
Set-Content -LiteralPath (Join-Path $outDir '00-SUMMARY.txt') -Value ($summary -join [Environment]::NewLine) -Encoding UTF8

Write-Host ''
Write-Host 'Capture finished.' -ForegroundColor Green
Write-Host ('Results folder: {0}' -f $outDir) -ForegroundColor Cyan
Write-Host 'Files: 00-SUMMARY.txt, 01-icy-headers-and-metadata.txt, 02-ffprobe-output.json, 03-ffprobe-diagnostics.txt, 04-title-highlights.html'
Write-Host 'Open 04-title-highlights.html to scan song titles and possible station messages in color.'
Write-Host 'Review the files for private station details before sharing them.'
Write-Host ''
exit 0
