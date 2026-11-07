# Creates and removes WSL instances from Windows, so it works even if every
# existing WSL instance is broken. Keep this file ASCII: Windows PowerShell 5.1
# misreads UTF-8 without a BOM.
#
#   lab.ps1 new dev
#   lab.ps1 new dev -Source C:\path\to\copy
#   lab.ps1 new agent-foo          (a name starting with agent- gets the agent profile)
#   lab.ps1 token                  (stores the token from claude setup-token)
#   lab.ps1 run agent-foo [-Path ~/work/repo]   (the default path is ~/work)
#   lab.ps1 verify agent-foo
#   lab.ps1 rm agent-foo           (only agent-* and restore-test*)
#   lab.ps1 restore-test           (builds main and agent, checks them, removes them)
#
# -NoClaude skips the checks that run Claude, so the stored token is not used.
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)][ValidateSet('new', 'rm', 'run', 'verify', 'token', 'restore-test')][string]$Command,
    [Parameter(Position = 1)][ValidatePattern('^[A-Za-z0-9-]+$')][string]$Name,
    [string]$Distro = 'Ubuntu-26.04',
    [string]$User = '',
    [string]$Source = 'https://github.com/Maru32768/dotfiles.git',
    [string]$Branch = '',
    [string]$Path = '~/work',
    [switch]$NoClaude
)

$ErrorActionPreference = 'Stop'

$LabDir = Join-Path $env:LOCALAPPDATA 'dotfiles-lab'
$TokenPath = Join-Path $LabDir 'claude-oauth-token.dpapi'
$ResultPath = Join-Path $LabDir 'restore-test.json'
$LogPath = Join-Path $LabDir 'restore-test.log'

function Invoke-Wsl {
    & wsl.exe @args
    if ($LASTEXITCODE -ne 0) {
        throw "wsl.exe failed with exit code ${LASTEXITCODE}: $args"
    }
}

function Get-Instances {
    # wsl.exe writes UTF-16 by default, which PowerShell misreads when capturing it
    $env:WSL_UTF8 = '1'
    try {
        return (& wsl.exe --list --quiet) | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    } finally {
        Remove-Item Env:WSL_UTF8
    }
}

function ConvertTo-WslPath([string]$Path) {
    $full = (Resolve-Path -LiteralPath $Path).ProviderPath
    $drive = $full.Substring(0, 1).ToLowerInvariant()
    return "/mnt/$drive" + $full.Substring(2).Replace('\', '/')
}

# Gives the token to one wsl.exe call only. A user-level environment variable
# would also override /login for Claude Code on Windows.
function Invoke-WithToken([scriptblock]$Action) {
    if (-not (Test-Path -LiteralPath $TokenPath)) {
        throw "No token stored. Run: claude setup-token, then lab.ps1 token"
    }
    $secure = Get-Content -LiteralPath $TokenPath | ConvertTo-SecureString
    $savedWslEnv = $env:WSLENV
    $env:CLAUDE_CODE_OAUTH_TOKEN = [System.Net.NetworkCredential]::new('', $secure).Password
    $env:WSLENV = (@($savedWslEnv, 'CLAUDE_CODE_OAUTH_TOKEN/u') | Where-Object { $_ }) -join ':'
    try {
        & $Action
    } finally {
        Remove-Item Env:CLAUDE_CODE_OAUTH_TOKEN
        $env:WSLENV = $savedWslEnv
    }
}

# A real Windows executable shows whether interop is really off. The instance
# cannot reach one by itself, so it is copied in from outside.
function Invoke-Verify {
    $probeExe = '/tmp/isolation-whoami.exe'
    Invoke-Wsl -d $Name -u root -e true
    Copy-Item -LiteralPath "$env:WINDIR\System32\whoami.exe" -Destination "\\wsl.localhost\$Name$($probeExe.Replace('/', '\'))"
    Invoke-Wsl -d $Name -u root -e chmod 755 $probeExe
    try {
        if ((-not $NoClaude) -and (Test-Path -LiteralPath $TokenPath)) {
            Invoke-WithToken {
                & wsl.exe -d $Name -u $User --cd '~' -e bash -lc "bash ~/dotfiles/tests/verify-isolation.sh --exe $probeExe --e2e"
            }
        } else {
            Write-Host 'The checks that run Claude are skipped (no token stored, or -NoClaude).'
            & wsl.exe -d $Name -u $User --cd '~' -e bash -lc "bash ~/dotfiles/tests/verify-isolation.sh --exe $probeExe"
        }
        if ($LASTEXITCODE -ne 0) {
            throw "verify-isolation.sh reported problems in $Name"
        }
    } finally {
        Invoke-Wsl -d $Name -u root -e rm -f $probeExe
    }
}

# Runs one step as a separate process, so a failed step cannot stop the others.
function Invoke-LabStep([string[]]$Arguments) {
    # wsl.exe prints its own messages in UTF-16, which leaves NUL characters in the log
    & powershell -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath @Arguments 2>&1 |
        ForEach-Object {
            $line = "$_" -replace "`0", ''
            Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
            Write-Host $line
        }
    return $LASTEXITCODE
}

# Builds each profile from nothing, checks it and removes it again. The result
# goes to a file because nobody is watching a scheduled run: doctor.ps1 reports
# it, and provision/promote-stable.sh only tags a commit that passed.
function Invoke-RestoreTest {
    # Windows PowerShell turns the stderr of a native command into errors. A
    # failed step has to reach the result file instead of stopping here.
    $ErrorActionPreference = 'Continue'

    $targets = @(
        @{ Profile = 'main'; Instance = 'restore-test'; User = 'maru' },
        @{ Profile = 'agent'; Instance = 'agent-restore-test'; User = 'agent' }
    )
    $existing = Get-Instances
    foreach ($target in $targets) {
        if ($existing -contains $target.Instance) {
            throw "Instance $($target.Instance) already exists. Remove it first: lab.ps1 rm $($target.Instance)"
        }
    }

    New-Item -ItemType Directory -Force -Path $LabDir -ErrorAction Stop | Out-Null
    "Restore test started at $(Get-Date -Format o)" | Set-Content -LiteralPath $LogPath -Encoding UTF8 -ErrorAction Stop
    # doctor.sh prints Japanese in UTF-8
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8

    $options = @('-Source', $Source)
    if ($Branch) { $options += @('-Branch', $Branch) }
    if ($NoClaude) { $options += '-NoClaude' }

    $results = [ordered]@{}
    $commits = @()
    foreach ($target in $targets) {
        Write-Host "==> Restore test: $($target.Profile)"
        $code = Invoke-LabStep (@('new', $target.Instance) + $options)
        $results[$target.Profile] = ($code -eq 0)
        if ($code -eq 0) {
            $commits += (& wsl.exe -d $target.Instance -u $target.User --cd '~' -e git -C dotfiles rev-parse HEAD 2>$null)
        }
        if ((Get-Instances) -contains $target.Instance) {
            $code = Invoke-LabStep @('rm', $target.Instance)
            if ($code -ne 0) { $results[$target.Profile] = $false }
        }
    }

    # A push between the two builds would mean they did not test the same thing
    $uniqueCommits = @($commits | Sort-Object -Unique)
    $passed = (@($results.Values | Where-Object { -not $_ }).Count -eq 0) -and ($uniqueCommits.Count -eq 1)
    [ordered]@{
        time    = Get-Date -Format o
        passed  = $passed
        commit  = $(if ($uniqueCommits.Count -eq 1) { $uniqueCommits[0] } else { $null })
        claude  = ((-not $NoClaude) -and (Test-Path -LiteralPath $TokenPath))
        results = $results
    } | ConvertTo-Json | Set-Content -LiteralPath $ResultPath -Encoding Ascii -ErrorAction Stop

    Write-Host "Result: $ResultPath"
    Write-Host "Log: $LogPath"
    if (-not $passed) {
        Write-Host 'Restore test FAILED'
        exit 1
    }
    Write-Host 'Restore test passed'
    exit 0
}

if ($Command -eq 'restore-test') {
    Invoke-RestoreTest
}

if ($Command -eq 'token') {
    $secure = Read-Host -AsSecureString 'Paste the token from claude setup-token'
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $TokenPath) | Out-Null
    $secure | ConvertFrom-SecureString | Set-Content -LiteralPath $TokenPath
    Write-Host "Stored, encrypted for this Windows user: $TokenPath"
    return
}

if (-not $Name) {
    throw "lab.ps1 $Command needs an instance name"
}

$isAgent = $Name -like 'agent-*'
if (-not $User) {
    $User = if ($isAgent) { 'agent' } else { 'maru' }
}

if ($Command -eq 'rm') {
    # Only disposable instances. Anything else needs a deliberate wsl --unregister.
    if ($Name -notmatch '^(agent-|restore-test)') {
        throw "Refusing to remove ${Name}: only agent-* and restore-test* can be removed here"
    }
    Invoke-Wsl --unregister $Name
    return
}

if ($Command -in @('run', 'verify') -and -not $isAgent) {
    throw "lab.ps1 $Command only works on agent-* instances"
}

if ($Command -eq 'verify') {
    Invoke-Verify
    return
}

if ($Command -eq 'run') {
    Invoke-WithToken {
        & wsl.exe -d $Name -u $User --cd $Path -e /usr/local/bin/agent-claude
    }
    exit $LASTEXITCODE
}

if ((Get-Instances) -contains $Name) {
    throw "Instance $Name already exists"
}

$profileName = if ($isAgent) { 'agent' } else { 'main' }
$isLocal = Test-Path -LiteralPath $Source
$sourceInWsl = if ($isLocal) { ConvertTo-WslPath $Source } else { $Source }
$bootstrap = '/var/tmp/dotfiles-bootstrap'

Write-Host "==> Installing $Distro as $Name ($profileName)"
Invoke-Wsl --install $Distro --name $Name --no-launch

Write-Host '==> Waiting for first boot'
& wsl.exe -d $Name -u root -e sh -c 'command -v cloud-init >/dev/null && cloud-init status --wait; true'

Write-Host '==> Fetching dotfiles'
if ($isLocal) {
    Invoke-Wsl -d $Name -u root -e cp -a $sourceInWsl $bootstrap
} else {
    Invoke-Wsl -d $Name -u root -e sh -c 'apt-get update -q && apt-get install -y -q git ca-certificates'
    $clone = @('git', 'clone')
    if ($Branch) { $clone += @('--branch', $Branch) }
    Invoke-Wsl -d $Name -u root -e @clone $Source $bootstrap
}

Write-Host '==> Provisioning as root'
Invoke-Wsl -d $Name -u root -e bash "$bootstrap/provision/root.sh" $User "$bootstrap/packages/apt.txt" $profileName

Write-Host '==> Restarting to apply wsl.conf'
Invoke-Wsl --terminate $Name

Write-Host "==> Provisioning as $User"
$arguments = @($profileName, $(if ($isLocal) { $bootstrap } else { $Source }))
if ($Branch) { $arguments += $Branch }
Invoke-Wsl -d $Name -u $User --cd '~' -e bash "$bootstrap/provision/user.sh" @arguments

Write-Host '==> Restarting to apply the user environment'
Invoke-Wsl -d $Name -u root -e rm -rf $bootstrap
Invoke-Wsl --terminate $Name

Write-Host '==> Checking the result'
if ($isAgent) {
    Invoke-Verify
    Write-Host "==> Done. Next: lab.ps1 token (once), then lab.ps1 run $Name"
} else {
    & wsl.exe -d $Name -u $User --cd '~' -e bash -lc 'bash ~/dotfiles/tests/doctor.sh'
    if ($LASTEXITCODE -ne 0) {
        throw "doctor.sh reported problems in $Name"
    }
    Write-Host "==> Done. Next: wsl -d $Name -u root passwd $User"
}
