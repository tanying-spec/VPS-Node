[CmdletBinding()]
param(
    [string]$KeyPath = "$HOME\.ssh\codex_u683775765_62_72_48_31",
    [string]$EvidenceDirectory = "",
    [string]$TunnelTokenFile = "",
    [string]$TunnelHost = "",
    [string]$TunnelPath = "",
    [int]$TunnelOriginPort = 0,
    [switch]$SelfTestEvidence,
    [switch]$ValidateOnly,
    [switch]$PreflightOnly,
    [switch]$SkipCpuProfiles,
    [switch]$SkipMemoryProfiles
)

$ErrorActionPreference = 'Stop'
$AuthorizedHost = '134.209.180.134'
$AuthorizedPort = 18750
$AuthorizedUser = 'root'
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$RunId = [Guid]::NewGuid().ToString('N')
$RemoteRoot = "/tmp/vps-node-authorized-$RunId"
$LocalArchive = Join-Path ([IO.Path]::GetTempPath()) "vps-node-authorized-$RunId.tar.gz"
$RemoteCreated = $false

if ([string]::IsNullOrWhiteSpace($EvidenceDirectory)) {
    $EvidenceDirectory = Join-Path $RepoRoot "evidence\$RunId"
}
$EvidenceDirectory = [IO.Path]::GetFullPath($EvidenceDirectory)

$SshOptions = @(
    '-i', $KeyPath,
    '-p', $AuthorizedPort,
    '-o', 'BatchMode=yes',
    '-o', 'PasswordAuthentication=no',
    '-o', 'KbdInteractiveAuthentication=no',
    '-o', 'PreferredAuthentications=publickey',
    '-o', 'StrictHostKeyChecking=accept-new',
    '-o', 'ConnectTimeout=8'
)
$ScpOptions = @(
    '-i', $KeyPath,
    '-P', $AuthorizedPort,
    '-o', 'BatchMode=yes',
    '-o', 'PasswordAuthentication=no',
    '-o', 'KbdInteractiveAuthentication=no',
    '-o', 'PreferredAuthentications=publickey',
    '-o', 'StrictHostKeyChecking=accept-new',
    '-o', 'ConnectTimeout=8'
)

function Quote-Sh([string]$Value) {
    $singleQuote = [string][char]39
    $doubleQuote = [string][char]34
    $replacement = $singleQuote + $doubleQuote + $singleQuote + $doubleQuote + $singleQuote
    return $singleQuote + $Value.Replace($singleQuote, $replacement) + $singleQuote
}

function Invoke-AuthorizedSsh([string]$Command, [switch]$AllowFailure) {
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = & ssh @SshOptions "$AuthorizedUser@$AuthorizedHost" $Command 2>&1
        $code = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }
    if ($code -ne 0 -and -not $AllowFailure) {
        throw "Authorized-host command failed (exit $code): $($output -join [Environment]::NewLine)"
    }
    return [pscustomobject]@{ ExitCode = $code; Output = @($output) }
}

function Assert-EvidenceChecksums([string]$Directory) {
    $sidecars = @(Get-ChildItem -LiteralPath $Directory -Filter '*.sha256' -File)
    if ($sidecars.Count -eq 0) {
        throw 'No acceptance SHA-256 evidence was downloaded.'
    }
    foreach ($sidecar in $sidecars) {
        $line = (Get-Content -LiteralPath $sidecar.FullName -TotalCount 1).Trim()
        $parts = $line -split '\s+', 2
        if ($parts.Count -lt 2 -or $parts[0] -notmatch '^[0-9a-fA-F]{64}$') {
            throw "Invalid evidence checksum format: $($sidecar.Name)"
        }
        $targetName = $parts[1].Trim().TrimStart('*')
        if ($targetName -ne [IO.Path]::GetFileName($targetName)) {
            throw "Evidence checksum contains a non-flat target path: $targetName"
        }
        $target = Join-Path $Directory $targetName
        if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
            throw "Evidence target is missing: $targetName"
        }
        $actual = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actual -ne $parts[0].ToLowerInvariant()) {
            throw "Evidence SHA-256 mismatch: $targetName"
        }
    }
}

function Assert-AcceptanceEvidence([string]$Directory, [bool]$TunnelRequested) {
    $acceptanceFiles = @(Get-ChildItem -LiteralPath $Directory -Filter 'vps-node-acceptance-*.txt' -File)
    if ($acceptanceFiles.Count -ne 1) {
        throw "Expected exactly one acceptance evidence file; found $($acceptanceFiles.Count)."
    }
    $values = @{}
    foreach ($line in Get-Content -LiteralPath $acceptanceFiles[0].FullName) {
        if ($line -notmatch '^([a-z0-9_]+)=(.*)$') { throw 'Acceptance evidence contains a malformed line.' }
        if ($values.ContainsKey($Matches[1])) { throw "Acceptance evidence contains a duplicate key: $($Matches[1])" }
        $values[$Matches[1]] = $Matches[2]
    }
    $versionMatch = Select-String -LiteralPath (Join-Path $RepoRoot 'vp.sh') -Pattern '^VP_VERSION="([^"]+)"$' | Select-Object -First 1
    if (-not $versionMatch) { throw 'Unable to determine the local VPS-Node version.' }
    $expectedVersion = $versionMatch.Matches[0].Groups[1].Value
    $expectedScriptHash = (Get-FileHash -LiteralPath (Join-Path $RepoRoot 'vp.sh') -Algorithm SHA256).Hash.ToLowerInvariant()
    $required = @{
        vps_node_version = $expectedVersion
        tested_script_sha256 = $expectedScriptHash
        source_checksum_verified = 'yes'
        authorized_host = $AuthorizedHost
        reality_ipv4_loopback_concurrency = '2/2'
        credential_rotation = 'passed'
        backup_restore_roundtrip = 'passed'
        config_drift_self_heal = 'passed'
        diagnostic_redaction = 'passed'
        recoverable_uninstall = 'passed'
        formal_mihomo_pids_unchanged = 'yes'
        formal_tunnel_pids_unchanged = 'yes'
        formal_config_and_init_digests_unchanged = 'yes'
        formal_sensitive_state_digests_unchanged = 'yes'
        formal_process_images_and_cmdlines_unchanged = 'yes'
        independent_cloudflare_tunnel = $(if ($TunnelRequested) { 'public-concurrency-and-respawn-passed' } else { 'not-requested' })
    }
    foreach ($key in $required.Keys) {
        if (-not $values.ContainsKey($key) -or $values[$key] -ne $required[$key]) {
            throw "Acceptance evidence did not prove required result: $key"
        }
    }
}

function Assert-MemoryEvidence([string]$Directory) {
    $summaryFiles = @(Get-ChildItem -LiteralPath $Directory -Filter 'memory-profiles-summary.txt' -File)
    $csvFiles = @(Get-ChildItem -LiteralPath $Directory -Filter 'memory-profiles.csv' -File)
    if ($summaryFiles.Count -ne 1 -or $csvFiles.Count -ne 1) {
        throw 'Expected exactly one memory summary and one memory profile CSV.'
    }
    $summary = @{}
    foreach ($line in Get-Content -LiteralPath $summaryFiles[0].FullName) {
        if ($line -notmatch '^([a-z0-9_]+)=(.*)$') { throw 'Memory evidence summary contains a malformed line.' }
        if ($summary.ContainsKey($Matches[1])) { throw "Memory evidence contains a duplicate key: $($Matches[1])" }
        $summary[$Matches[1]] = $Matches[2]
    }
    $versionMatch = Select-String -LiteralPath (Join-Path $RepoRoot 'vp.sh') -Pattern '^VP_VERSION="([^"]+)"$' | Select-Object -First 1
    if (-not $versionMatch) { throw 'Unable to determine the local VPS-Node version.' }
    $expectedScriptHash = (Get-FileHash -LiteralPath (Join-Path $RepoRoot 'vp.sh') -Algorithm SHA256).Hash.ToLowerInvariant()
    $requiredSummary = @{
        vps_node_version = $versionMatch.Matches[0].Groups[1].Value
        tested_script_sha256 = $expectedScriptHash
        authorized_host = $AuthorizedHost
        cgroup_version = '2'
        memory_limits_tested = '64,96,97,128,160,161,192,256,320,321,512,640,641,1024,2048'
        profile_count = '15'
        real_core_startups = '15'
        functional_proxy_checks = '15'
        traffic_survival_checks = '15'
        concurrent_transfer_checks = '60'
        verified_transfer_bytes = '62914560'
        oom_kill_total = '0'
        formal_services_and_sensitive_state_unchanged = 'yes'
    }
    foreach ($key in $requiredSummary.Keys) {
        if (-not $summary.ContainsKey($key) -or $summary[$key] -ne $requiredSummary[$key]) {
            throw "Memory evidence did not prove required result: $key"
        }
    }
    $rows = @(Import-Csv -LiteralPath $csvFiles[0].FullName)
    $limits = @(64, 96, 97, 128, 160, 161, 192, 256, 320, 321, 512, 640, 641, 1024, 2048)
    $budgets = @(38, 57, 58, 76, 96, 96, 115, 153, 192, 192, 307, 384, 384, 512, 512)
    $profiles = @('ultra-compact', 'ultra-compact', 'compact', 'compact', 'compact', 'balanced', 'balanced', 'balanced', 'balanced', 'standard', 'standard', 'standard', 'performance', 'performance', 'performance')
    $gogc = @(50, 50, 60, 60, 60, 80, 80, 80, 80, 100, 100, 100, 100, 100, 100)
    $gomaxprocs = @(1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 4, 4, 4)
    if ($rows.Count -ne $limits.Count) { throw "Expected fifteen memory profile rows; found $($rows.Count)." }
    $maximumPeak = 0
    for ($index = 0; $index -lt $limits.Count; $index++) {
        $row = $rows[$index]
        if ([int]$row.limit_mib -ne $limits[$index] -or [int]$row.budget_mib -ne $budgets[$index]) { throw "Unexpected memory budget at row $index." }
        if ($row.profile -ne $profiles[$index] -or $row.gomemlimit -ne "$($budgets[$index])MiB") { throw "Unexpected memory profile at row $index." }
        if ([int]$row.gogc -ne $gogc[$index] -or [int]$row.gomaxprocs -ne $gomaxprocs[$index]) { throw "Unexpected Go runtime tuning at row $index." }
        $peak = [int]$row.peak_mib
        if ($peak -lt 1 -or $peak -gt $limits[$index]) { throw "Invalid observed memory peak at row $index." }
        if ([int]$row.oom_kill -ne 0 -or $row.proxy_result -ne 'passed') { throw "Memory profile runtime failed at row $index." }
        if ([int]$row.concurrent_success -ne 4 -or [int64]$row.total_bytes -ne 4194304) { throw "Memory profile concurrency failed at row $index." }
        if ($peak -gt $maximumPeak) { $maximumPeak = $peak }
    }
    if (-not $summary.ContainsKey('max_observed_peak_mib') -or [int]$summary.max_observed_peak_mib -ne $maximumPeak) {
        throw 'Memory evidence maximum peak does not match the profile rows.'
    }
}

function Assert-CpuEvidence([string]$Directory) {
    $summaryFile = Get-Item -LiteralPath (Join-Path $Directory 'cpu-profiles-summary.txt') -ErrorAction Stop
    $csvFile = Get-Item -LiteralPath (Join-Path $Directory 'cpu-profiles.csv') -ErrorAction Stop
    $summary = @{}
    foreach ($line in Get-Content -LiteralPath $summaryFile.FullName) {
        if ($line -notmatch '^([a-z0-9_]+)=(.*)$') { throw 'CPU evidence summary contains a malformed line.' }
        if ($summary.ContainsKey($Matches[1])) { throw "CPU evidence contains a duplicate key: $($Matches[1])" }
        $summary[$Matches[1]] = $Matches[2]
    }
    $versionMatch = Select-String -LiteralPath (Join-Path $RepoRoot 'vp.sh') -Pattern '^VP_VERSION="([^"]+)"$' | Select-Object -First 1
    $expectedHash = (Get-FileHash -LiteralPath (Join-Path $RepoRoot 'vp.sh') -Algorithm SHA256).Hash.ToLowerInvariant()
    if (-not $versionMatch -or $summary.vps_node_version -ne $versionMatch.Matches[0].Groups[1].Value -or $summary.tested_script_sha256 -ne $expectedHash) {
        throw 'CPU evidence does not match the current source.'
    }
    if ($summary.authorized_host -ne $AuthorizedHost -or $summary.cgroup_version -ne '2' -or $summary.formal_services_and_sensitive_state_unchanged -ne 'yes') {
        throw 'CPU evidence did not prove the fixed host, cgroup v2 and formal-service invariants.'
    }
    $hostCpus = [int]$summary.host_cpu_count
    if ($hostCpus -lt 1) { throw 'CPU evidence contains an invalid host CPU count.' }
    $expectedQuotas = @(500, 999, 1000)
    if ($hostCpus -ge 2) { $expectedQuotas += @(1001, 1500, 2000) }
    if ($hostCpus -ge 4) { $expectedQuotas += @(2001, 4000) }
    if ($summary.cpu_quotas_tested -ne ($expectedQuotas -join ',')) { throw 'CPU evidence quota matrix is incomplete.' }
    $rows = @(Import-Csv -LiteralPath $csvFile.FullName)
    if ($rows.Count -ne $expectedQuotas.Count) { throw 'CPU evidence row count is incomplete.' }
    for ($index = 0; $index -lt $expectedQuotas.Count; $index++) {
        $quota = $expectedQuotas[$index]
        $effective = [Math]::Ceiling($quota / 1000.0)
        if ($effective -gt $hostCpus) { $effective = $hostCpus }
        if ($effective -gt 4) { $effective = 4 }
        $row = $rows[$index]
        if ([int]$row.quota_milli -ne $quota -or [int]$row.effective_count -ne $effective -or [int]$row.gomaxprocs -ne $effective) { throw "CPU quota detection failed at row $index." }
        $expectedGogc = $(if ($quota -lt 1000) { 120 } else { 100 })
        $expectedProfile = $(if ($quota -lt 1000) { 'performance-cpu-limited' } else { 'performance' })
        if ([int]$row.gogc -ne $expectedGogc -or $row.profile -ne $expectedProfile) { throw "CPU runtime profile failed at row $index." }
        if ($row.proxy_result -ne 'passed' -or [int]$row.concurrent_success -ne 4 -or [int64]$row.total_bytes -ne 4194304) { throw "CPU runtime transfer failed at row $index." }
        if ([int64]$row.throttled_events -lt 0) { throw "CPU throttling evidence is invalid at row $index." }
        $throttlingRequired = $quota -lt ($hostCpus * 1000)
        if ($row.throttling_required -ne $(if ($throttlingRequired) { 'yes' } else { 'no' })) { throw "CPU throttling requirement is wrong at row $index." }
        if ($throttlingRequired -and [int64]$row.throttled_events -lt 1) { throw "CPU quota was not proven to throttle at row $index." }
    }
    $expectedCount = $expectedQuotas.Count
    if ([int]$summary.profile_count -ne $expectedCount -or [int]$summary.real_core_startups -ne $expectedCount -or
        [int]$summary.concurrent_transfer_checks -ne ($expectedCount * 4) -or [int]$summary.saturated_quota_checks -ne $expectedCount -or
        [int64]$summary.verified_transfer_bytes -ne ($expectedCount * 4194304)) {
        throw 'CPU evidence summary totals do not match the quota rows.'
    }
}

function Assert-PreflightResult([string[]]$Output, [bool]$MemoryRequested, [bool]$CpuRequested, [bool]$TunnelRequested) {
    $values = @{}
    foreach ($line in $Output) {
        if ($line -notmatch '^preflight_([a-z0-9_]+)=(.*)$') { continue }
        if ($values.ContainsKey($Matches[1])) { throw "Preflight output contains a duplicate key: $($Matches[1])" }
        $values[$Matches[1]] = $Matches[2]
    }
    $required = @{
        status = 'passed'
        authorized_host = 'yes'
        root = 'yes'
        alpine = 'yes'
        commands = 'yes'
        mihomo = 'yes'
        ipify = 'yes'
        speed_endpoint = 'yes'
        formal_snapshot = 'yes'
        memory_mode = $(if ($MemoryRequested) { 'required' } else { 'skipped' })
        cpu_mode = $(if ($CpuRequested) { 'required' } else { 'skipped' })
        tunnel_mode = $(if ($TunnelRequested) { 'required' } else { 'skipped' })
    }
    if ($MemoryRequested) {
        $required.cgroup_v2 = 'yes'
        $required.memory_controller = 'yes'
        $required.cgroup_root_writable = 'yes'
    }
    if ($CpuRequested) {
        $required.cpu_controller = 'yes'
    }
    if ($TunnelRequested) {
        $required.cloudflared = 'yes'
        $required.independent_tunnel_inputs = 'yes'
        $required.tunnel_edge = 'reachable'
    }
    foreach ($key in $required.Keys) {
        if (-not $values.ContainsKey($key) -or $values[$key] -ne $required[$key]) {
            throw "Authorized-host preflight did not prove required result: $key"
        }
    }
    if (-not $values.ContainsKey('tmp_free_mib') -or [int64]$values.tmp_free_mib -lt 128) {
        throw 'Authorized-host preflight did not prove at least 128 MiB free in /tmp.'
    }
    return @($Output | Where-Object { $_ -match '^preflight_[a-z0-9_]+=' })
}

$TunnelInputCount = 0
foreach ($tunnelInputPresent in @(
    -not [string]::IsNullOrWhiteSpace($TunnelTokenFile),
    -not [string]::IsNullOrWhiteSpace($TunnelHost),
    -not [string]::IsNullOrWhiteSpace($TunnelPath),
    $TunnelOriginPort -ne 0
)) {
    if ($tunnelInputPresent) { $TunnelInputCount++ }
}
if ($TunnelInputCount -ne 0 -and $TunnelInputCount -ne 4) {
    throw 'Independent Tunnel acceptance requires TunnelTokenFile, TunnelHost, TunnelPath and TunnelOriginPort together.'
}
if ($TunnelInputCount -eq 4) {
    if ($TunnelTokenFile -notmatch '^/') { throw 'TunnelTokenFile must be an absolute path on the authorized host.' }
    if ($TunnelTokenFile -match "[\r\n]") { throw 'TunnelTokenFile contains an invalid newline.' }
    if ($TunnelTokenFile -eq '/etc/cloudflared/token') { throw 'TunnelTokenFile must not reference the formal Cloudflare Tunnel token.' }
    if ($TunnelHost -notmatch '^[A-Za-z0-9.-]+\.[A-Za-z]{2,63}$') { throw 'TunnelHost is invalid.' }
    if ($TunnelHost.Contains('..') -or $TunnelHost.StartsWith('.') -or $TunnelHost.EndsWith('.')) { throw 'TunnelHost is invalid.' }
    if (-not $TunnelPath.StartsWith('/') -or $TunnelPath -match "[\r\n]") { throw 'TunnelPath must begin with / and contain no newline.' }
    if ($TunnelOriginPort -lt 1024 -or $TunnelOriginPort -gt 65535) { throw 'TunnelOriginPort must be between 1024 and 65535.' }
}
if ($SelfTestEvidence) {
    $selfTestDirectory = Join-Path ([IO.Path]::GetTempPath()) "vps-node-evidence-self-test-$RunId"
    try {
        New-Item -ItemType Directory -Path $selfTestDirectory | Out-Null
        $versionMatch = Select-String -LiteralPath (Join-Path $RepoRoot 'vp.sh') -Pattern '^VP_VERSION="([^"]+)"$' | Select-Object -First 1
        if (-not $versionMatch) { throw 'Unable to determine the local VPS-Node version for evidence self-test.' }
        $expectedVersion = $versionMatch.Matches[0].Groups[1].Value
        $expectedScriptHash = (Get-FileHash -LiteralPath (Join-Path $RepoRoot 'vp.sh') -Algorithm SHA256).Hash.ToLowerInvariant()
        $evidencePath = Join-Path $selfTestDirectory 'vps-node-acceptance-selftest.txt'
        $validLines = @(
            "vps_node_version=$expectedVersion",
            "tested_script_sha256=$expectedScriptHash",
            'source_checksum_verified=yes',
            "authorized_host=$AuthorizedHost",
            'reality_ipv4_loopback_concurrency=2/2',
            'independent_cloudflare_tunnel=not-requested',
            'credential_rotation=passed',
            'backup_restore_roundtrip=passed',
            'config_drift_self_heal=passed',
            'diagnostic_redaction=passed',
            'recoverable_uninstall=passed',
            'formal_mihomo_pids_unchanged=yes',
            'formal_tunnel_pids_unchanged=yes',
            'formal_config_and_init_digests_unchanged=yes',
            'formal_sensitive_state_digests_unchanged=yes',
            'formal_process_images_and_cmdlines_unchanged=yes'
        )
        $validLines | Set-Content -LiteralPath $evidencePath -Encoding ascii
        $evidenceName = [IO.Path]::GetFileName($evidencePath)
        $sidecarPath = "$evidencePath.sha256"
        $hash = (Get-FileHash -LiteralPath $evidencePath -Algorithm SHA256).Hash.ToLowerInvariant()
        "$hash  $evidenceName" | Set-Content -LiteralPath $sidecarPath -Encoding ascii
        Assert-EvidenceChecksums $selfTestDirectory
        Assert-AcceptanceEvidence $selfTestDirectory $false

        Add-Content -LiteralPath $evidencePath -Value 'tampered=yes' -Encoding ascii
        $checksumRejected = $false
        try { Assert-EvidenceChecksums $selfTestDirectory } catch { $checksumRejected = $true }
        if (-not $checksumRejected) { throw 'Evidence self-test failed to reject modified content.' }

        $invalidLines = $validLines | ForEach-Object { if ($_ -like 'tested_script_sha256=*') { 'tested_script_sha256=' + ('0' * 64) } else { $_ } }
        $invalidLines | Set-Content -LiteralPath $evidencePath -Encoding ascii
        $hash = (Get-FileHash -LiteralPath $evidencePath -Algorithm SHA256).Hash.ToLowerInvariant()
        "$hash  $evidenceName" | Set-Content -LiteralPath $sidecarPath -Encoding ascii
        Assert-EvidenceChecksums $selfTestDirectory
        $metadataRejected = $false
        try { Assert-AcceptanceEvidence $selfTestDirectory $false } catch { $metadataRejected = $true }
        if (-not $metadataRejected) { throw 'Evidence self-test failed to reject mismatched source metadata.' }

        $validLines | Set-Content -LiteralPath $evidencePath -Encoding ascii
        $hash = (Get-FileHash -LiteralPath $evidencePath -Algorithm SHA256).Hash.ToLowerInvariant()
        "$hash  $evidenceName" | Set-Content -LiteralPath $sidecarPath -Encoding ascii
        $memorySummary = Join-Path $selfTestDirectory 'memory-profiles-summary.txt'
        @(
            "vps_node_version=$expectedVersion",
            "tested_script_sha256=$expectedScriptHash",
            "authorized_host=$AuthorizedHost",
            'cgroup_version=2',
            'memory_limits_tested=64,96,97,128,160,161,192,256,320,321,512,640,641,1024,2048',
            'profile_count=15',
            'real_core_startups=15',
            'functional_proxy_checks=15',
            'traffic_survival_checks=15',
            'concurrent_transfer_checks=60',
            'verified_transfer_bytes=62914560',
            'oom_kill_total=0',
            'max_observed_peak_mib=55',
            'formal_services_and_sensitive_state_unchanged=yes'
        ) | Set-Content -LiteralPath $memorySummary -Encoding ascii
        $memoryCsv = Join-Path $selfTestDirectory 'memory-profiles.csv'
        $validMemoryRows = @(
            'limit_mib,budget_mib,profile,gomemlimit,gogc,gomaxprocs,peak_mib,oom_kill,proxy_result,concurrent_success,total_bytes',
            '64,38,ultra-compact,38MiB,50,1,31,0,passed,4,4194304',
            '96,57,ultra-compact,57MiB,50,1,32,0,passed,4,4194304',
            '97,58,compact,58MiB,60,1,33,0,passed,4,4194304',
            '128,76,compact,76MiB,60,1,34,0,passed,4,4194304',
            '160,96,compact,96MiB,60,1,35,0,passed,4,4194304',
            '161,96,balanced,96MiB,80,2,36,0,passed,4,4194304',
            '192,115,balanced,115MiB,80,2,37,0,passed,4,4194304',
            '256,153,balanced,153MiB,80,2,38,0,passed,4,4194304',
            '320,192,balanced,192MiB,80,2,39,0,passed,4,4194304',
            '321,192,standard,192MiB,100,2,40,0,passed,4,4194304',
            '512,307,standard,307MiB,100,2,42,0,passed,4,4194304',
            '640,384,standard,384MiB,100,2,44,0,passed,4,4194304',
            '641,384,performance,384MiB,100,4,46,0,passed,4,4194304',
            '1024,512,performance,512MiB,100,4,50,0,passed,4,4194304',
            '2048,512,performance,512MiB,100,4,55,0,passed,4,4194304'
        )
        $validMemoryRows | Set-Content -LiteralPath $memoryCsv -Encoding ascii
        foreach ($memoryFile in @($memorySummary, $memoryCsv)) {
            $memoryHash = (Get-FileHash -LiteralPath $memoryFile -Algorithm SHA256).Hash.ToLowerInvariant()
            $memoryName = [IO.Path]::GetFileName($memoryFile)
            "$memoryHash  $memoryName" | Set-Content -LiteralPath "$memoryFile.sha256" -Encoding ascii
        }
        Assert-EvidenceChecksums $selfTestDirectory
        Assert-MemoryEvidence $selfTestDirectory
        (Get-Content -LiteralPath $memoryCsv) -replace ',0,passed,4,4194304$', ',1,passed,4,4194304' | Set-Content -LiteralPath $memoryCsv -Encoding ascii
        $memoryHash = (Get-FileHash -LiteralPath $memoryCsv -Algorithm SHA256).Hash.ToLowerInvariant()
        "$memoryHash  memory-profiles.csv" | Set-Content -LiteralPath "$memoryCsv.sha256" -Encoding ascii
        Assert-EvidenceChecksums $selfTestDirectory
        $memoryMetadataRejected = $false
        try { Assert-MemoryEvidence $selfTestDirectory } catch { $memoryMetadataRejected = $true }
        if (-not $memoryMetadataRejected) { throw 'Evidence self-test failed to reject a memory profile reporting an OOM kill.' }

        $validMemoryRows -replace ',4,4194304$', ',4,4194303' | Set-Content -LiteralPath $memoryCsv -Encoding ascii
        $memoryHash = (Get-FileHash -LiteralPath $memoryCsv -Algorithm SHA256).Hash.ToLowerInvariant()
        "$memoryHash  memory-profiles.csv" | Set-Content -LiteralPath "$memoryCsv.sha256" -Encoding ascii
        Assert-EvidenceChecksums $selfTestDirectory
        $truncatedTransferRejected = $false
        try { Assert-MemoryEvidence $selfTestDirectory } catch { $truncatedTransferRejected = $true }
        if (-not $truncatedTransferRejected) { throw 'Evidence self-test failed to reject truncated concurrent transfers.' }

        $validPreflight = @(
            'preflight_status=passed',
            'preflight_authorized_host=yes',
            'preflight_root=yes',
            'preflight_alpine=yes',
            'preflight_commands=yes',
            'preflight_mihomo=yes',
            'preflight_ipify=yes',
            'preflight_speed_endpoint=yes',
            'preflight_tmp_free_mib=512',
            'preflight_formal_snapshot=yes',
            'preflight_memory_mode=required',
            'preflight_cgroup_v2=yes',
            'preflight_memory_controller=yes',
            'preflight_cgroup_root_writable=yes',
            'preflight_cpu_mode=required',
            'preflight_cpu_controller=yes',
            'preflight_tunnel_mode=skipped'
        )
        Assert-PreflightResult $validPreflight $true $true $false | Out-Null
        $badPreflight = $validPreflight -replace 'preflight_speed_endpoint=yes', 'preflight_speed_endpoint=no'
        $preflightRejected = $false
        try { Assert-PreflightResult $badPreflight $true $true $false | Out-Null } catch { $preflightRejected = $true }
        if (-not $preflightRejected) { throw 'Evidence self-test failed to reject an unavailable transfer endpoint.' }

        $cpuSummary = Join-Path $selfTestDirectory 'cpu-profiles-summary.txt'
        @(
            "vps_node_version=$expectedVersion",
            "tested_script_sha256=$expectedScriptHash",
            "authorized_host=$AuthorizedHost",
            'cgroup_version=2',
            'host_cpu_count=4',
            'cpu_quotas_tested=500,999,1000,1001,1500,2000,2001,4000',
            'profile_count=8',
            'real_core_startups=8',
            'concurrent_transfer_checks=32',
            'saturated_quota_checks=8',
            'verified_transfer_bytes=33554432',
            'formal_services_and_sensitive_state_unchanged=yes'
        ) | Set-Content -LiteralPath $cpuSummary -Encoding ascii
        $cpuCsv = Join-Path $selfTestDirectory 'cpu-profiles.csv'
        $validCpuRows = @(
            'quota_milli,effective_count,gomaxprocs,gogc,profile,proxy_result,concurrent_success,total_bytes,throttling_required,throttled_events',
            '500,1,1,120,performance-cpu-limited,passed,4,4194304,yes,3',
            '999,1,1,120,performance-cpu-limited,passed,4,4194304,yes,2',
            '1000,1,1,100,performance,passed,4,4194304,yes,2',
            '1001,2,2,100,performance,passed,4,4194304,yes,1',
            '1500,2,2,100,performance,passed,4,4194304,yes,1',
            '2000,2,2,100,performance,passed,4,4194304,yes,1',
            '2001,3,3,100,performance,passed,4,4194304,yes,1',
            '4000,4,4,100,performance,passed,4,4194304,no,0'
        )
        $validCpuRows | Set-Content -LiteralPath $cpuCsv -Encoding ascii
        foreach ($cpuFile in @($cpuSummary, $cpuCsv)) {
            $cpuHash = (Get-FileHash -LiteralPath $cpuFile -Algorithm SHA256).Hash.ToLowerInvariant()
            $cpuName = [IO.Path]::GetFileName($cpuFile)
            "$cpuHash  $cpuName" | Set-Content -LiteralPath "$cpuFile.sha256" -Encoding ascii
        }
        Assert-EvidenceChecksums $selfTestDirectory
        Assert-CpuEvidence $selfTestDirectory
        $validCpuRows -replace '^1001,2,2,', '1001,1,1,' | Set-Content -LiteralPath $cpuCsv -Encoding ascii
        $cpuHash = (Get-FileHash -LiteralPath $cpuCsv -Algorithm SHA256).Hash.ToLowerInvariant()
        "$cpuHash  cpu-profiles.csv" | Set-Content -LiteralPath "$cpuCsv.sha256" -Encoding ascii
        Assert-EvidenceChecksums $selfTestDirectory
        $cpuQuotaRejected = $false
        try { Assert-CpuEvidence $selfTestDirectory } catch { $cpuQuotaRejected = $true }
        if (-not $cpuQuotaRejected) { throw 'Evidence self-test failed to reject an incorrect CPU quota transition.' }
        $validCpuRows -replace '^1500,2,2,100,performance,passed,4,4194304,yes,1$', '1500,2,2,100,performance,passed,4,4194304,yes,0' | Set-Content -LiteralPath $cpuCsv -Encoding ascii
        $cpuHash = (Get-FileHash -LiteralPath $cpuCsv -Algorithm SHA256).Hash.ToLowerInvariant()
        "$cpuHash  cpu-profiles.csv" | Set-Content -LiteralPath "$cpuCsv.sha256" -Encoding ascii
        Assert-EvidenceChecksums $selfTestDirectory
        $cpuThrottleRejected = $false
        try { Assert-CpuEvidence $selfTestDirectory } catch { $cpuThrottleRejected = $true }
        if (-not $cpuThrottleRejected) { throw 'Evidence self-test failed to reject a quota without required throttling.' }
        Write-Host 'Acceptance, memory, CPU and preflight verification self-test passed; no network connection was attempted.'
        return
    }
    finally {
        Remove-Item -LiteralPath $selfTestDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
}
if ($ValidateOnly) {
    Write-Host 'Authorized-host runner parameters are valid; no network connection was attempted.'
    return
}
if (-not (Test-Path -LiteralPath $KeyPath -PathType Leaf)) {
    throw "SSH private key does not exist: $KeyPath"
}
foreach ($commandName in @('ssh', 'scp', 'tar')) {
    if (-not (Get-Command $commandName -ErrorAction SilentlyContinue)) {
        throw "Required local command is missing: $commandName"
    }
}
foreach ($required in @('vp.sh', 'vp.sh.sha256', 'tests\isolated_acceptance.sh', 'tests\memory_profiles.sh', 'tests\cpu_profiles.sh')) {
    if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot $required) -PathType Leaf)) {
        throw "Required local acceptance file is missing: $required"
    }
}
if (-not $PreflightOnly -and (Test-Path -LiteralPath $EvidenceDirectory) -and @(Get-ChildItem -LiteralPath $EvidenceDirectory -Force).Count -ne 0) {
    throw "Evidence directory must be absent or empty to prevent mixing runs: $EvidenceDirectory"
}

Write-Host "Connecting read-only to the only authorized host $AuthorizedHost`:$AuthorizedPort (public key only)..."
$probe = Invoke-AuthorizedSsh "printf 'authorized-host-connected\n'"
if (($probe.Output -join "`n") -notmatch 'authorized-host-connected') {
    throw 'SSH probe did not return the expected marker.'
}

$preflightScript = @'
set -eu
fail() { printf 'preflight_status=failed\npreflight_reason=%s\n' "$1"; exit 1; }
[ "$(id -u)" = 0 ] || fail root-required
observed_host=$(curl -4 -fsS --max-time 8 https://api.ipify.org 2>/dev/null || true)
[ "$observed_host" = "134.209.180.134" ] || fail unauthorized-host
[ -r /etc/os-release ] && grep -q '^ID=alpine$' /etc/os-release || fail alpine-required
for command_name in sh curl tar sha256sum awk sed grep rc-service rc-update pidof readlink netstat df; do
  command -v "$command_name" >/dev/null 2>&1 || fail "missing-command-$command_name"
done
mihomo_found=no
mihomo_path=
for process_pid in $(pidof mihomo 2>/dev/null || true); do
  candidate=$(readlink -f "/proc/$process_pid/exe" 2>/dev/null || true)
  if [ -n "$candidate" ] && [ -x "$candidate" ] && "$candidate" -v >/dev/null 2>&1; then mihomo_found=yes; mihomo_path=$candidate; break; fi
done
if [ "$mihomo_found" = no ]; then
  for candidate in "$(command -v mihomo 2>/dev/null || true)" /usr/local/bin/mihomo /usr/bin/mihomo /etc/mihomo/mihomo /usr/local/lib/mihomo/mihomo; do
    if [ -n "$candidate" ] && [ -x "$candidate" ] && "$candidate" -v >/dev/null 2>&1; then mihomo_found=yes; mihomo_path=$candidate; break; fi
  done
fi
[ "$mihomo_found" = yes ] || fail mihomo-unavailable
sha256sum "$mihomo_path" >/dev/null 2>&1 || fail mihomo-unreadable
rc-service mihomo status >/dev/null 2>&1 || true
rc-service cloudflared-tunnel status >/dev/null 2>&1 || true
for formal_file in /etc/mihomo/config.yaml /etc/mihomo/nodes.db /etc/mihomo/state.env /etc/init.d/mihomo /etc/init.d/cloudflared-tunnel /etc/cloudflared/token; do
  if [ -e "$formal_file" ]; then sha256sum "$formal_file" >/dev/null 2>&1 || fail formal-state-unreadable; fi
done
for formal_pid in $(pidof mihomo 2>/dev/null || true) $(pidof cloudflared 2>/dev/null || true); do
  [ -r "/proc/$formal_pid/cmdline" ] || fail formal-process-unreadable
  readlink -f "/proc/$formal_pid/exe" >/dev/null 2>&1 || fail formal-process-unreadable
done
tmp_free_mib=$(df -Pk /tmp | awk 'NR==2{print int($4/1024)}')
[ "${tmp_free_mib:-0}" -ge 128 ] || fail insufficient-tmp-space
speed_bytes=$(curl -4 -fsS --max-time 12 -o /dev/null -w '%{size_download}' 'https://speed.cloudflare.com/__down?bytes=1' 2>/dev/null || true)
[ "$speed_bytes" = 1 ] || fail speed-endpoint-unavailable
if [ "$PREFLIGHT_MEMORY" = 1 ]; then
  [ -f /sys/fs/cgroup/cgroup.controllers ] || fail cgroup-v2-required
  grep -qw memory /sys/fs/cgroup/cgroup.controllers || fail memory-controller-unavailable
  [ -w /sys/fs/cgroup ] || fail cgroup-root-not-writable
fi
if [ "$PREFLIGHT_CPU" = 1 ]; then
  [ -f /sys/fs/cgroup/cgroup.controllers ] || fail cgroup-v2-required
  grep -qw cpu /sys/fs/cgroup/cgroup.controllers || fail cpu-controller-unavailable
  [ -w /sys/fs/cgroup ] || fail cgroup-root-not-writable
fi
if [ "$PREFLIGHT_TUNNEL" = 1 ]; then
  [ -r "$PREFLIGHT_TOKEN_FILE" ] || fail independent-token-unreadable
  if [ -r /etc/cloudflared/token ] && [ "$(sha256sum "$PREFLIGHT_TOKEN_FILE" | awk '{print $1}')" = "$(sha256sum /etc/cloudflared/token | awk '{print $1}')" ]; then
    fail formal-token-reused
  fi
  if [ -r /etc/mihomo/nodes.db ] && grep -Fq "$PREFLIGHT_HOST" /etc/mihomo/nodes.db; then fail formal-host-reused; fi
  netstat -lnt 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]$PREFLIGHT_PORT$" && fail origin-port-in-use
  cloudflared_found=no
  for process_pid in $(pidof cloudflared 2>/dev/null || true); do
    candidate=$(readlink -f "/proc/$process_pid/exe" 2>/dev/null || true)
    if [ -n "$candidate" ] && [ -x "$candidate" ] && "$candidate" --version >/dev/null 2>&1; then cloudflared_found=yes; break; fi
  done
  if [ "$cloudflared_found" = no ]; then
    for candidate in "$(command -v cloudflared 2>/dev/null || true)" /usr/local/bin/cloudflared /usr/bin/cloudflared /etc/cloudflared/cloudflared; do
      if [ -n "$candidate" ] && [ -x "$candidate" ] && "$candidate" --version >/dev/null 2>&1; then cloudflared_found=yes; break; fi
    done
  fi
  [ "$cloudflared_found" = yes ] || fail cloudflared-unavailable
  edge_code=$(curl -4 -sS --max-time 12 -o /dev/null -w '%{http_code}' "https://$PREFLIGHT_HOST$PREFLIGHT_PATH" 2>/dev/null || true)
  [ -n "$edge_code" ] && [ "$edge_code" != 000 ] || fail tunnel-edge-unreachable
fi
printf 'preflight_status=passed\n'
printf 'preflight_authorized_host=yes\n'
printf 'preflight_root=yes\n'
printf 'preflight_alpine=yes\n'
printf 'preflight_commands=yes\n'
printf 'preflight_mihomo=yes\n'
printf 'preflight_ipify=yes\n'
printf 'preflight_speed_endpoint=yes\n'
printf 'preflight_tmp_free_mib=%s\n' "$tmp_free_mib"
printf 'preflight_formal_snapshot=yes\n'
if [ "$PREFLIGHT_MEMORY" = 1 ]; then
  printf 'preflight_memory_mode=required\npreflight_cgroup_v2=yes\npreflight_memory_controller=yes\npreflight_cgroup_root_writable=yes\n'
else
  printf 'preflight_memory_mode=skipped\n'
fi
if [ "$PREFLIGHT_CPU" = 1 ]; then
  printf 'preflight_cpu_mode=required\npreflight_cpu_controller=yes\n'
else
  printf 'preflight_cpu_mode=skipped\n'
fi
if [ "$PREFLIGHT_TUNNEL" = 1 ]; then
  printf 'preflight_tunnel_mode=required\npreflight_cloudflared=yes\npreflight_independent_tunnel_inputs=yes\npreflight_tunnel_edge=reachable\n'
else
  printf 'preflight_tunnel_mode=skipped\n'
fi
'@
$preflightCommand = "PREFLIGHT_MEMORY=$(if ($SkipMemoryProfiles) { '0' } else { '1' }); " +
    "PREFLIGHT_CPU=$(if ($SkipCpuProfiles) { '0' } else { '1' }); " +
    "PREFLIGHT_TUNNEL=$(if ($TunnelInputCount -eq 4) { '1' } else { '0' }); " +
    "PREFLIGHT_TOKEN_FILE=$(Quote-Sh $TunnelTokenFile); " +
    "PREFLIGHT_HOST=$(Quote-Sh $TunnelHost); " +
    "PREFLIGHT_PATH=$(Quote-Sh $TunnelPath); " +
    "PREFLIGHT_PORT=$(Quote-Sh ([string]$TunnelOriginPort)); " +
    "export PREFLIGHT_MEMORY PREFLIGHT_CPU PREFLIGHT_TUNNEL PREFLIGHT_TOKEN_FILE PREFLIGHT_HOST PREFLIGHT_PATH PREFLIGHT_PORT; " +
    $preflightScript
$preflight = Invoke-AuthorizedSsh $preflightCommand
$PreflightLines = Assert-PreflightResult $preflight.Output (-not $SkipMemoryProfiles) (-not $SkipCpuProfiles) ($TunnelInputCount -eq 4)
$PreflightLines | ForEach-Object { Write-Host $_ }
if ($PreflightOnly) {
    Write-Host 'Authorized-host preflight passed; no files were uploaded and no test was started.'
    return
}

try {
    & tar -czf $LocalArchive -C $RepoRoot vp.sh vp.sh.sha256 tests/isolated_acceptance.sh tests/memory_profiles.sh tests/cpu_profiles.sh
    if ($LASTEXITCODE -ne 0) { throw 'Failed to package the current acceptance source.' }

    Invoke-AuthorizedSsh "set -eu; umask 077; mkdir -p $(Quote-Sh $RemoteRoot)/source $(Quote-Sh $RemoteRoot)/evidence" | Out-Null
    $RemoteCreated = $true
    & scp @ScpOptions $LocalArchive "$AuthorizedUser@$AuthorizedHost`:$RemoteRoot/source.tar.gz"
    if ($LASTEXITCODE -ne 0) { throw 'Failed to upload the acceptance source.' }
    Invoke-AuthorizedSsh "set -eu; tar -xzf $(Quote-Sh "$RemoteRoot/source.tar.gz") -C $(Quote-Sh "$RemoteRoot/source"); rm -f $(Quote-Sh "$RemoteRoot/source.tar.gz")" | Out-Null

    $discover = @'
set -eu
for pid in $(pidof mihomo 2>/dev/null || true); do
  candidate=$(readlink -f "/proc/$pid/exe" 2>/dev/null || true)
  if [ -n "$candidate" ] && [ -x "$candidate" ]; then printf '%s\n' "$candidate"; exit 0; fi
done
for candidate in "$(command -v mihomo 2>/dev/null || true)" /usr/local/bin/mihomo /usr/bin/mihomo /etc/mihomo/mihomo /usr/local/lib/mihomo/mihomo; do
  if [ -n "$candidate" ] && [ -x "$candidate" ]; then printf '%s\n' "$candidate"; exit 0; fi
done
exit 1
'@
    $discovery = Invoke-AuthorizedSsh $discover
    $MihomoPath = [string]($discovery.Output | Where-Object { $_ -match '^/' } | Select-Object -First 1)
    $MihomoPath = $MihomoPath.Trim()
    if ([string]::IsNullOrWhiteSpace($MihomoPath)) { throw 'Unable to discover the formal Mihomo executable read-only.' }
    Write-Host 'Mihomo discovered; starting isolated acceptance without reading or changing formal credentials.'

    $acceptanceEnvironment = "VP_TEST_MIHOMO_BIN=$(Quote-Sh $MihomoPath) " +
        "VP_ACCEPTANCE_EVIDENCE_DIR=$(Quote-Sh "$RemoteRoot/evidence") "
    if ($TunnelInputCount -eq 4) {
        $discoverCloudflared = @'
set -eu
for pid in $(pidof cloudflared 2>/dev/null || true); do
  candidate=$(readlink -f "/proc/$pid/exe" 2>/dev/null || true)
  if [ -n "$candidate" ] && [ -x "$candidate" ]; then printf '%s\n' "$candidate"; exit 0; fi
done
for candidate in "$(command -v cloudflared 2>/dev/null || true)" /usr/local/bin/cloudflared /usr/bin/cloudflared /etc/cloudflared/cloudflared; do
  if [ -n "$candidate" ] && [ -x "$candidate" ]; then printf '%s\n' "$candidate"; exit 0; fi
done
exit 1
'@
        $cloudflaredDiscovery = Invoke-AuthorizedSsh $discoverCloudflared
        $CloudflaredPath = [string]($cloudflaredDiscovery.Output | Where-Object { $_ -match '^/' } | Select-Object -First 1)
        $CloudflaredPath = $CloudflaredPath.Trim()
        if ([string]::IsNullOrWhiteSpace($CloudflaredPath)) { throw 'Unable to discover cloudflared read-only.' }
        $acceptanceEnvironment += "VP_TEST_CLOUDFLARED_BIN=$(Quote-Sh $CloudflaredPath) " +
            "VP_TEST_TUNNEL_TOKEN_FILE=$(Quote-Sh $TunnelTokenFile) " +
            "VP_TEST_ARGO_HOST=$(Quote-Sh $TunnelHost) " +
            "VP_TEST_ARGO_PATH=$(Quote-Sh $TunnelPath) " +
            "VP_TEST_ARGO_ORIGIN_PORT=$(Quote-Sh ([string]$TunnelOriginPort)) "
        Write-Host 'Independent Cloudflare Tunnel inputs validated; public edge acceptance is enabled.'
    }

    $acceptanceCommand = "set -eu; cd $(Quote-Sh "$RemoteRoot/source"); " +
        $acceptanceEnvironment +
        "sh tests/isolated_acceptance.sh"
    $acceptance = Invoke-AuthorizedSsh $acceptanceCommand
    $acceptance.Output | ForEach-Object { Write-Host $_ }

    if (-not $SkipMemoryProfiles) {
        $memoryCommand = "set -eu; cd $(Quote-Sh "$RemoteRoot/source"); " +
            "VP_TEST_MIHOMO_BIN=$(Quote-Sh $MihomoPath) " +
            "VP_MEMORY_EVIDENCE_DIR=$(Quote-Sh "$RemoteRoot/evidence") " +
            "sh tests/memory_profiles.sh"
        Invoke-AuthorizedSsh $memoryCommand | Out-Null
    }
    if (-not $SkipCpuProfiles) {
        $cpuCommand = "set -eu; cd $(Quote-Sh "$RemoteRoot/source"); " +
            "VP_TEST_MIHOMO_BIN=$(Quote-Sh $MihomoPath) " +
            "VP_CPU_EVIDENCE_DIR=$(Quote-Sh "$RemoteRoot/evidence") " +
            "sh tests/cpu_profiles.sh"
        Invoke-AuthorizedSsh $cpuCommand | Out-Null
    }

    New-Item -ItemType Directory -Force -Path $EvidenceDirectory | Out-Null
    & scp @ScpOptions "$AuthorizedUser@$AuthorizedHost`:$RemoteRoot/evidence/*" "$EvidenceDirectory\"
    if ($LASTEXITCODE -ne 0) { throw 'Failed to download redacted acceptance evidence.' }
    $preflightEvidence = Join-Path $EvidenceDirectory 'authorized-host-preflight.txt'
    $PreflightLines | Set-Content -LiteralPath $preflightEvidence -Encoding ascii
    $preflightHash = (Get-FileHash -LiteralPath $preflightEvidence -Algorithm SHA256).Hash.ToLowerInvariant()
    "$preflightHash  authorized-host-preflight.txt" | Set-Content -LiteralPath "$preflightEvidence.sha256" -Encoding ascii
    Assert-EvidenceChecksums $EvidenceDirectory
    Assert-PreflightResult (Get-Content -LiteralPath $preflightEvidence) (-not $SkipMemoryProfiles) (-not $SkipCpuProfiles) ($TunnelInputCount -eq 4) | Out-Null
    Assert-AcceptanceEvidence $EvidenceDirectory ($TunnelInputCount -eq 4)
    if (-not $SkipMemoryProfiles) { Assert-MemoryEvidence $EvidenceDirectory }
    if (-not $SkipCpuProfiles) { Assert-CpuEvidence $EvidenceDirectory }
    Write-Host "Acceptance complete; downloaded evidence passed SHA-256 verification: $EvidenceDirectory"
}
finally {
    Remove-Item -LiteralPath $LocalArchive -Force -ErrorAction SilentlyContinue
    if ($RemoteCreated -and $RemoteRoot -match '^/tmp/vps-node-authorized-[0-9a-f]{32}$') {
        Invoke-AuthorizedSsh "rm -rf -- $(Quote-Sh $RemoteRoot)" -AllowFailure | Out-Null
    }
}
