# Sets up Windows from nothing but this file. Keep it ASCII: Windows PowerShell
# 5.1 misreads UTF-8 without a BOM. Safe to run again.
#
#   powershell -ExecutionPolicy Bypass -File bootstrap.ps1
#   powershell -ExecutionPolicy Bypass -File bootstrap.ps1 -Branch redesign
[CmdletBinding()]
param(
    [string]$Source = 'https://github.com/Maru32768/dotfiles.git',
    [string]$Branch = '',
    [switch]$SkipPackages
)

$ErrorActionPreference = 'Stop'

# Keep in step with MISE_VERSION in provision/user.sh. See docs/tools.md.
$MiseVersion = '2026.11.0'
$Repo = Join-Path $HOME 'dotfiles'

function Update-SessionPath {
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
        [Environment]::GetEnvironmentVariable('Path', 'User')
}

function Assert-LastExit([string]$What) {
    if ($LASTEXITCODE -ne 0) { throw "$What failed with exit code $LASTEXITCODE" }
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host '==> Installing Git'
    & winget install --id Git.Git --exact --accept-source-agreements --accept-package-agreements --disable-interactivity
    Update-SessionPath
}

if (-not (Test-Path $Repo)) {
    Write-Host "==> Cloning dotfiles to $Repo"
    $clone = @('clone')
    if ($Branch) { $clone += @('--branch', $Branch) }
    & git @clone $Source $Repo
    Assert-LastExit 'git clone'
}

if (-not $SkipPackages) {
    Write-Host '==> Installing packages'
    # winget returns non-zero when packages are already installed, so this is not fatal
    & winget import --import-file (Join-Path $Repo 'packages\winget.json') --ignore-unavailable --ignore-versions --accept-source-agreements --accept-package-agreements --disable-interactivity
    Update-SessionPath
}

Write-Host "==> Pinning mise to $MiseVersion"
& mise self-update $MiseVersion --yes
Assert-LastExit 'mise self-update'

Write-Host '==> Applying settings'
$miseConfig = Join-Path $HOME '.config\mise'
New-Item -ItemType Directory -Force -Path $miseConfig | Out-Null
Copy-Item (Join-Path $Repo 'home\dot_config\mise\config.toml'), (Join-Path $Repo 'home\dot_config\mise\mise.lock') $miseConfig
Push-Location $HOME
try {
    & mise install --yes chezmoi
    Assert-LastExit 'mise install chezmoi'
    $env:DOTFILES_PROFILE = 'main'
    & mise exec chezmoi -- chezmoi init --source $Repo --apply --no-tty
    Assert-LastExit 'chezmoi init'
} finally {
    Pop-Location
}

Write-Host '==> Checking the result'
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Repo 'tests\doctor.ps1')
Assert-LastExit 'doctor.ps1'
