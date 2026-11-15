# Runs a command with the secrets of one 1Password vault as environment variables.
# Each item in the vault becomes one variable: the item title is the name, its concealed field the value.
# The service account token is stored encrypted with GPG and decrypted on each run (docs/secrets.md).
# This is the Windows version of ~/.local/bin/op-run. op-run.cmd calls it, so cmd (and so mise
# tasks, which run through cmd on Windows) can find it.
# Keep this file ASCII: Windows PowerShell 5.1 misreads UTF-8 without a BOM.
#
#   op-run <vault> [--] <command> [args...]
#   op-run --list <vault>     prints only the names of the variables, never the values
#   op-run --set-token        reads the token and stores it encrypted with GPG
$ErrorActionPreference = 'Stop'

$TokenFile = if ($env:OP_RUN_TOKEN_FILE) { $env:OP_RUN_TOKEN_FILE } else { Join-Path $HOME '.config\op-run\token.gpg' }

function Stop-WithError([string]$Message) {
    [Console]::Error.WriteLine("op-run: $Message")
    exit 1
}

function Show-Usage {
    Get-Content -LiteralPath $PSCommandPath | Where-Object { $_ -like '#   *' } |
        ForEach-Object { [Console]::Error.WriteLine($_.Substring(4)) }
    exit 2
}

# ops_ followed by base64url JSON. A token pasted twice has ops_eyJ twice.
function Test-Token([string]$Token) {
    return $Token -cmatch '^ops_eyJ[A-Za-z0-9_-]+=*$' -and -not $Token.Substring(4).Contains('ops_eyJ')
}

function Set-Token {
    $recipient = & git config --global user.signingkey
    if (-not $recipient) { Stop-WithError 'git user.signingkey is not set (it is the GPG recipient)' }
    $secure = Read-Host -AsSecureString 'Service account token (not shown; paste it once, then Enter)'
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
        Stop-WithError "no token: $TokenFile (store one with op-run --set-token)"
    }
    $token = ((& gpg --quiet --decrypt $TokenFile) -join '').Trim()
    if ($LASTEXITCODE -ne 0 -or -not $token) { Stop-WithError "could not decrypt the token: $TokenFile" }
    if (-not (Test-Token $token)) { Stop-WithError "the stored token is malformed: $TokenFile (store it again with op-run --set-token)" }
    return $token
}

# The token goes to op only, and is removed again before the command runs
function Invoke-Op([string]$Token, [string[]]$Arguments) {
    $env:OP_SERVICE_ACCOUNT_TOKEN = $Token
    try {
        $output = (& op @Arguments --format json) -join "`n"
        if ($LASTEXITCODE -ne 0) { Stop-WithError "op $($Arguments -join ' ') failed" }
    } finally {
        Remove-Item Env:OP_SERVICE_ACCOUNT_TOKEN -ErrorAction SilentlyContinue
    }
    return $output | ConvertFrom-Json
}

function Get-VaultSecret([string]$Token, [string]$Name) {
    $vaults = @(Invoke-Op $Token @('vault', 'list') | ForEach-Object { $_ } | Where-Object { $_.name -ceq $Name })
    if ($vaults.Count -ne 1) {
        Stop-WithError "found $($vaults.Count) vaults named $Name (the token must see exactly one)"
    }
    $vaultId = $vaults[0].id
    $items = @(Invoke-Op $Token @('item', 'list', '--vault', $vaultId) | ForEach-Object { $_ })
    $secrets = @(foreach ($listed in $items) {
        $item = Invoke-Op $Token @('item', 'get', $listed.id, '--vault', $vaultId, '--reveal')
        $values = @($item.fields | Where-Object { $_.type -eq 'CONCEALED' -and [string]$_.value -ne '' } | ForEach-Object { [string]$_.value })
        [pscustomobject]@{ key = [string]$item.title; values = $values }
    })
    $bad = @($secrets | Where-Object { $_.values.Count -ne 1 } | ForEach-Object { $_.key })
    if ($bad.Count -gt 0) { Stop-WithError "items without exactly one concealed field: $($bad -join ' ')" }
    $bad = @($secrets | Where-Object { $_.key -cnotmatch '^[A-Za-z_][A-Za-z0-9_]*$' } | ForEach-Object { $_.key })
    if ($bad.Count -gt 0) { Stop-WithError "names that cannot be environment variables: $($bad -join ' ')" }
    # Windows does not tell environment variables apart by case, so neither does this check
    if (@($secrets | ForEach-Object { $_.key } | Sort-Object -Unique).Count -ne $secrets.Count) {
        Stop-WithError 'more than one item has the same name'
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
    Get-VaultSecret $token $args[1] | ForEach-Object { $_.key } | Sort-Object
    exit 0
}
if ($args[0] -like '-*') { Show-Usage }

$vault = $args[0]
$rest = @($args | Select-Object -Skip 1)
if ($rest.Count -gt 0 -and $rest[0] -eq '--') { $rest = @($rest | Select-Object -Skip 1) }
if ($rest.Count -eq 0) { Show-Usage }

$token = Read-Token
$secrets = Get-VaultSecret $token $vault
Remove-Variable token
# A token the caller already had is not passed on either
Remove-Item Env:OP_SERVICE_ACCOUNT_TOKEN -ErrorAction SilentlyContinue
foreach ($secret in $secrets) {
    [Environment]::SetEnvironmentVariable($secret.key, $secret.values[0], 'Process')
}
$command = $rest[0]
$commandArgs = @($rest | Select-Object -Skip 1)
& $command @commandArgs
exit $LASTEXITCODE
