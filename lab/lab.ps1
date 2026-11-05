# Creates and removes WSL instances from Windows, so it works even if every
# existing WSL instance is broken. Keep this file ASCII: Windows PowerShell 5.1
# misreads UTF-8 without a BOM.
#
#   lab.ps1 new dev
#   lab.ps1 new dev -Source C:\path\to\copy
#   lab.ps1 rm dev
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)][ValidateSet('new', 'rm')][string]$Command,
    [Parameter(Mandatory, Position = 1)][ValidatePattern('^[A-Za-z0-9-]+$')][string]$Name,
    [ValidateSet('main')][string]$ProfileName = 'main',
    [string]$Distro = 'Ubuntu-26.04',
    [string]$User = 'maru',
    [string]$Source = 'https://github.com/Maru32768/dotfiles.git',
    [string]$Branch = ''
)

$ErrorActionPreference = 'Stop'

function Invoke-Wsl {
    & wsl.exe @args
    if ($LASTEXITCODE -ne 0) {
        throw "wsl.exe failed with exit code ${LASTEXITCODE}: $args"
    }
}

function Get-Instances {
    $previous = [Console]::OutputEncoding
    [Console]::OutputEncoding = [Text.Encoding]::Unicode
    try {
        return (& wsl.exe --list --quiet) | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    } finally {
        [Console]::OutputEncoding = $previous
    }
}

function ConvertTo-WslPath([string]$Path) {
    $full = (Resolve-Path -LiteralPath $Path).ProviderPath
    $drive = $full.Substring(0, 1).ToLowerInvariant()
    return "/mnt/$drive" + $full.Substring(2).Replace('\', '/')
}

if ($Command -eq 'rm') {
    if ($Name -in @('Ubuntu', 'Ubuntu-24.04', 'PostgreSQL-Experiment', 'docker-desktop', 'docker-desktop-data')) {
        throw "Refusing to remove $Name"
    }
    Invoke-Wsl --unregister $Name
    return
}

if ((Get-Instances) -contains $Name) {
    throw "Instance $Name already exists"
}

$isLocal = Test-Path -LiteralPath $Source
$sourceInWsl = if ($isLocal) { ConvertTo-WslPath $Source } else { $Source }
$bootstrap = '/var/tmp/dotfiles-bootstrap'

Write-Host "==> Installing $Distro as $Name"
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
Invoke-Wsl -d $Name -u root -e bash "$bootstrap/provision/root.sh" $User "$bootstrap/packages/apt.txt"

Write-Host '==> Restarting to apply wsl.conf'
Invoke-Wsl --terminate $Name

Write-Host "==> Provisioning as $User"
$arguments = @($ProfileName, $(if ($isLocal) { $bootstrap } else { $Source }))
if ($Branch) { $arguments += $Branch }
Invoke-Wsl -d $Name -u $User --cd '~' -e bash "$bootstrap/provision/user.sh" @arguments

Write-Host '==> Checking the result'
& wsl.exe -d $Name -u $User --cd '~' -e bash -lc 'bash ~/dotfiles/tests/doctor.sh'
Invoke-Wsl -d $Name -u root -e rm -rf $bootstrap
Write-Host "==> Done. Next: wsl -d $Name -u root passwd $User"
