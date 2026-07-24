[CmdletBinding()]
param(
    [string]$KeyPath = "$HOME\.ssh\codex_u683775765_62_72_48_31",
    [string]$EvidenceDirectory = "",
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
    $MihomoPath = ($discovery.Output | Where-Object { $_ -match '^/' } | Select-Object -First 1).Trim()
    if ([string]::IsNullOrWhiteSpace($MihomoPath)) { throw 'Unable to discover the formal Mihomo executable read-only.' }
    Write-Host 'Mihomo discovered; starting isolated acceptance without reading or changing formal credentials.'

    $acceptanceCommand = "set -eu; cd $(Quote-Sh "$RemoteRoot/source"); " +
        "VP_TEST_MIHOMO_BIN=$(Quote-Sh $MihomoPath) " +
        "VP_ACCEPTANCE_EVIDENCE_DIR=$(Quote-Sh "$RemoteRoot/evidence") " +
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
    Write-Host "Acceptance complete; downloaded evidence passed SHA-256 verification: $EvidenceDirectory"
}
finally {
    Remove-Item -LiteralPath $LocalArchive -Force -ErrorAction SilentlyContinue
    if ($RemoteCreated -and $RemoteRoot -match '^/tmp/vps-node-authorized-[0-9a-f]{32}$') {
        Invoke-AuthorizedSsh "rm -rf -- $(Quote-Sh $RemoteRoot)" -AllowFailure | Out-Null
    }
}
