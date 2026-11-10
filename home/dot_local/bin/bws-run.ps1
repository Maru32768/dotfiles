# Runs a command with the secrets of one Bitwarden Secrets Manager project as environment variables.
# The machine account token is stored encrypted with GPG and decrypted on each run (docs/secrets.md).
# This is the Windows version of ~/.local/bin/bws-run. bws-run.cmd calls it, so cmd (and so mise
# tasks, which run through cmd on Windows) can find it.
# Keep this file ASCII: Windows PowerShell 5.1 misreads UTF-8 without a BOM.
#
#   bws-run <project> [--] <command> [args...]
#   bws-run --list <project>     prints only the names of the variables, never the values
#   bws-run --set-token          reads the token and stores it encrypted with GPG
$ErrorActionPreference = 'Stop'

$TokenFile = if ($env:BWS_TOKEN_FILE) { $env:BWS_TOKEN_FILE } else { Join-Path $HOME '.config\bws\token.gpg' }

function Stop-WithError([string]$Message) {
    [Console]::Error.WriteLine("bws-run: $Message")
    exit 1
}

function Show-Usage {
    Get-Content -LiteralPath $PSCommandPath | Where-Object { $_ -like '#   *' } |
        ForEach-Object { [Console]::Error.WriteLine($_.Substring(4)) }
    exit 2
}

# 0.<access token id>.<secret>:<encryption key (base64)>
function Test-Token([string]$Token) {
    return $Token -cmatch '^[0-9]+\.[0-9a-fA-F-]{36}\.[A-Za-z0-9]+:[A-Za-z0-9+/]+=*$'
}

function Set-Token {
    $recipient = & git config --global user.signingkey
    if (-not $recipient) { Stop-WithError 'git user.signingkey is not set (it is the GPG recipient)' }
    $secure = Read-Host -AsSecureString 'Machine account access token (not shown; paste it once, then Enter)'
    $token = [System.Net.NetworkCredential]::new('', $secure).Password.Trim()
    if (-not $token) { Stop-WithError 'the token is empty' }
    if (-not (Test-Token $token)) { Stop-WithError 'the token is malformed (was it pasted twice, or mixed with other keys?)' }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $TokenFile) | Out-Null
    $token | & gpg --quiet --yes --encrypt --recipient $recipient --output "$TokenFile.tmp"
    if ($LASTEXITCODE -ne 0) { Stop-WithError 'gpg could not encrypt the token' }
    Move-Item -Force -LiteralPath "$TokenFile.tmp" -Destination $TokenFile
    [Console]::Error.WriteLine("Stored: $TokenFile")
}

# gpg asks for the passphrase when its cache has expired
function Read-Token {
    if (-not (Test-Path -LiteralPath $TokenFile)) {
        Stop-WithError "no token: $TokenFile (store one with bws-run --set-token)"
    }
    $token = ((& gpg --quiet --decrypt $TokenFile) -join '').Trim()
    if ($LASTEXITCODE -ne 0 -or -not $token) { Stop-WithError "could not decrypt the token: $TokenFile" }
    if (-not (Test-Token $token)) { Stop-WithError "the stored token is malformed: $TokenFile (store it again with bws-run --set-token)" }
    return $token
}

# The token goes to bws only, and is removed again before the command runs
function Invoke-Bws([string]$Token, [string[]]$Arguments) {
    $env:BWS_ACCESS_TOKEN = $Token
    try {
        $output = (& bws @Arguments --output json) -join "`n"
        if ($LASTEXITCODE -ne 0) { Stop-WithError "bws $($Arguments[0]) $($Arguments[1]) failed" }
    } finally {
        Remove-Item Env:BWS_ACCESS_TOKEN -ErrorAction SilentlyContinue
    }
    return $output | ConvertFrom-Json
}

function Get-ProjectSecret([string]$Token, [string]$Name) {
    $projects = @(Invoke-Bws $Token @('project', 'list') | ForEach-Object { $_ } | Where-Object { $_.name -ceq $Name })
    if ($projects.Count -ne 1) {
        Stop-WithError "found $($projects.Count) projects named $Name (the token must see exactly one)"
    }
    $secrets = @(Invoke-Bws $Token @('secret', 'list', $projects[0].id) | ForEach-Object { $_ })
    $bad = @($secrets | Where-Object { $_.key -cnotmatch '^[A-Za-z_][A-Za-z0-9_]*$' } | ForEach-Object { $_.key })
    if ($bad.Count -gt 0) { Stop-WithError "names that cannot be environment variables: $($bad -join ' ')" }
    # Windows does not tell environment variables apart by case, so neither does this check
    if (@($secrets | ForEach-Object { $_.key } | Sort-Object -Unique).Count -ne $secrets.Count) {
        Stop-WithError 'more than one secret has the same name'
    }
    return , $secrets
}

if ($args.Count -eq 0) { Show-Usage }
if ($args[0] -eq '--set-token') {
    if ($args.Count -ne 1) { Show-Usage }
    Set-Token
    exit 0
}
if ($args[0] -eq '--list') {
    if ($args.Count -ne 2) { Show-Usage }
    $token = Read-Token
    Get-ProjectSecret $token $args[1] | ForEach-Object { $_.key } | Sort-Object
    exit 0
}
if ($args[0] -like '-*') { Show-Usage }

$project = $args[0]
$rest = @($args | Select-Object -Skip 1)
if ($rest.Count -gt 0 -and $rest[0] -eq '--') { $rest = @($rest | Select-Object -Skip 1) }
if ($rest.Count -eq 0) { Show-Usage }

$token = Read-Token
$secrets = Get-ProjectSecret $token $project
Remove-Variable token
# A token the caller already had is not passed on either
Remove-Item Env:BWS_ACCESS_TOKEN -ErrorAction SilentlyContinue
foreach ($secret in $secrets) {
    [Environment]::SetEnvironmentVariable($secret.key, [string]$secret.value, 'Process')
}
$command = $rest[0]
$commandArgs = @($rest | Select-Object -Skip 1)
& $command @commandArgs
exit $LASTEXITCODE
