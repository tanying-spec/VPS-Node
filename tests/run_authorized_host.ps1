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
        Write-Host 'Acceptance evidence verification self-test passed; no network connection was attempted.'
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
foreach ($required in @('vp.sh', 'vp.sh.sha256', 'tests\isolated_acceptance.sh', 'tests\memory_profiles.sh')) {
    if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot $required) -PathType Leaf)) {
        throw "Required local acceptance file is missing: $required"
    }
}
if ((Test-Path -LiteralPath $EvidenceDirectory) -and @(Get-ChildItem -LiteralPath $EvidenceDirectory -Force).Count -ne 0) {
    throw "Evidence directory must be absent or empty to prevent mixing runs: $EvidenceDirectory"
}

Write-Host "Connecting read-only to the only authorized host $AuthorizedHost`:$AuthorizedPort (public key only)..."
$probe = Invoke-AuthorizedSsh "printf 'authorized-host-connected\n'"
if (($probe.Output -join "`n") -notmatch 'authorized-host-connected') {
    throw 'SSH probe did not return the expected marker.'
}

try {
    & tar -czf $LocalArchive -C $RepoRoot vp.sh vp.sh.sha256 tests/isolated_acceptance.sh tests/memory_profiles.sh
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
            "VP_TEST_MIHOMO_BIN=$(Quote-Sh $MihomoPath) sh tests/memory_profiles.sh " +
            "> $(Quote-Sh "$RemoteRoot/evidence/memory-profiles.txt"); " +
            "cd $(Quote-Sh "$RemoteRoot/evidence"); sha256sum memory-profiles.txt > memory-profiles.txt.sha256"
        Invoke-AuthorizedSsh $memoryCommand | Out-Null
    }

    New-Item -ItemType Directory -Force -Path $EvidenceDirectory | Out-Null
    & scp @ScpOptions "$AuthorizedUser@$AuthorizedHost`:$RemoteRoot/evidence/*" "$EvidenceDirectory\"
    if ($LASTEXITCODE -ne 0) { throw 'Failed to download redacted acceptance evidence.' }
    Assert-EvidenceChecksums $EvidenceDirectory
    Assert-AcceptanceEvidence $EvidenceDirectory ($TunnelInputCount -eq 4)
    Write-Host "Acceptance complete; downloaded evidence passed SHA-256 verification: $EvidenceDirectory"
}
finally {
    Remove-Item -LiteralPath $LocalArchive -Force -ErrorAction SilentlyContinue
    if ($RemoteCreated -and $RemoteRoot -match '^/tmp/vps-node-authorized-[0-9a-f]{32}$') {
        Invoke-AuthorizedSsh "rm -rf -- $(Quote-Sh $RemoteRoot)" -AllowFailure | Out-Null
    }
}
