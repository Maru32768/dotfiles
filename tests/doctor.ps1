# Checks that Windows is set up as expected. Exits 1 if anything is wrong.
# TODO lines are manual steps still to do and do not count as failures.
# Keep this file ASCII: Windows PowerShell 5.1 misreads UTF-8 without a BOM.
$ErrorActionPreference = 'Continue'
Set-Location $HOME

$script:Failures = 0
$GitBash = 'C:\Program Files\Git\bin\bash.exe'
$GpgFingerprint = '7AF93B4735CF2AAC930EF5CD78324D99D34D3111'

function Pass([string]$Name) { Write-Host "PASS $Name" }
function Fail([string]$Name) { Write-Host "FAIL $Name"; $script:Failures++ }
function Todo([string]$Name) { Write-Host "TODO $Name" }
function Check([string]$Name, [scriptblock]$Test) {
    $ok = $false
    try { $ok = [bool](& $Test) } catch { $ok = $false }
    if ($ok) { Pass $Name } else { Fail $Name }
}

foreach ($tool in 'git', 'gpg', 'mise', 'winget', 'pwsh') {
    Check "command: $tool" { Get-Command $tool -ErrorAction Stop }
}
Check 'Git Bash' { Test-Path $GitBash }
Check 'aws (winget)' { Get-Command aws -ErrorAction Stop }

$lockPath = Join-Path $HOME '.config\mise\mise.lock'
$locked = @{}
$name = $null
foreach ($line in Get-Content $lockPath) {
    if ($line -match '^\[\[tools\.(.+)\]\]$') { $name = $Matches[1].Trim('"') }
    elseif ($line -match '^version = "(.+)"$' -and $name) { $locked[$name] = $Matches[1]; $name = $null }
}
$current = @{}
foreach ($line in (& mise ls --current 2>$null)) {
    $fields = -split $line
    if ($fields.Count -ge 2) { $current[$fields[0]] = $fields[1] }
}
foreach ($tool in ($locked.Keys | Sort-Object)) {
    if ($tool -eq 'aws-cli') { continue }
    Check "mise: $tool $($locked[$tool])" { $current[$tool] -eq $locked[$tool] }
}

# Claude Code and Codex rewrite these files themselves. The hook registration is checked below.
# A failed status prints nothing, so the exit code is checked too.
Check 'chezmoi: no differences' {
    $status = & mise exec chezmoi -- chezmoi status --exclude=scripts 2>$null
    ($LASTEXITCODE -eq 0) -and -not ($status | Where-Object { $_ -notmatch '(\.claude/settings\.json|\.codex/config\.toml)$' })
}

Check 'gh extension: gh-stack' {
    & mise exec gh -- gh stack --version 2>$null | Out-Null
    $LASTEXITCODE -eq 0
}

Check 'git: commit signing on' { (& git config --global commit.gpgsign) -eq 'true' }
Check 'git: gpg.program has no path' { (& git config --global gpg.program) -eq 'gpg' }
Check 'git: signing key set' { (& git config --global user.signingkey) -eq $GpgFingerprint.Substring(24) }
Check 'git: old misspelled key removed' { -not (& git config --global user.signinkey) }

if (& gpg --list-secret-keys $GpgFingerprint 2>$null) {
    Pass 'GPG signing key'
} else {
    Todo 'GPG signing key: restore it, see docs/gpg.md'
}

$bwsToken = Join-Path $HOME '.config\bws\token.gpg'
if ((Test-Path -LiteralPath $bwsToken) -and (Get-Item -LiteralPath $bwsToken).Length -gt 0) {
    Pass 'Bitwarden Secrets Manager token'
} else {
    Todo 'Bitwarden Secrets Manager token: run bws-run --set-token, see docs/secrets.md'
}
Check 'bws-run on PATH' { Get-Command bws-run.cmd -ErrorAction Stop }

$settings = Get-Content -Raw (Join-Path $HOME '.claude\settings.json') | ConvertFrom-Json
$hookCommand = $settings.hooks.PreToolUse[0].hooks[0].command
Check 'Claude settings: hook registered' { $hookCommand -match 'block-signing-bypass' }

function Invoke-Hook([string]$Json) {
    $Json | & $GitBash -c $hookCommand
}
Check 'hook denies a bypass' {
    (Invoke-Hook '{"tool_name":"Bash","tool_input":{"command":"git commit --no-gpg-sign"}}') -match 'deny'
}
Check 'hook allows a normal command' {
    -not (Invoke-Hook '{"tool_name":"Bash","tool_input":{"command":"git status"}}')
}

$expectedGo = $locked['go']
Check "Git Bash login shell uses Go $expectedGo" {
    (& $GitBash -lc 'go version') -match [regex]::Escape("go$expectedGo")
}
Check "pwsh uses Go $expectedGo" {
    (& pwsh -NoLogo -Command 'go version') -match [regex]::Escape("go$expectedGo")
}

# A scheduled restore test has nobody watching it, so its result is reported here.
$restoreResult = Join-Path $env:LOCALAPPDATA 'dotfiles-lab\restore-test.json'
if (Test-Path -LiteralPath $restoreResult) {
    $restore = Get-Content -Raw -LiteralPath $restoreResult | ConvertFrom-Json
    $restoreAge = ((Get-Date) - [datetime]$restore.time).Days
    if (-not $restore.passed) {
        Todo "restore test failed $restoreAge day(s) ago: see $env:LOCALAPPDATA\dotfiles-lab\restore-test.log"
    } elseif ($restoreAge -gt 45) {
        Todo "restore test is $restoreAge days old: run lab\lab.ps1 restore-test"
    } else {
        Pass "restore test passed $restoreAge day(s) ago"
    }
} else {
    Todo 'restore test: run lab\lab.ps1 restore-test'
}

Write-Host ''
if ($script:Failures -gt 0) {
    Write-Host "$script:Failures problem(s) found"
    exit 1
}
Write-Host 'No problems found'
exit 0
