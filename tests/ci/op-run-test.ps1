# Tests op-run.ps1 and op-run.cmd (home/dot_local/bin) with fake gpg and op. No network, no keys.
# Keep this file ASCII: Windows PowerShell 5.1 misreads UTF-8 without a BOM.
#
#   pwsh -File tests\ci\op-run-test.ps1
$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).ProviderPath
$script = Join-Path $root 'home\dot_local\bin\op-run.ps1'
$shim = Join-Path $root 'home\dot_local\bin\op-run.cmd'
$work = Join-Path ([System.IO.Path]::GetTempPath()) "op-run-test-$PID"
$bin = Join-Path $work 'bin'
New-Item -ItemType Directory -Force -Path $bin | Out-Null
$failures = 0

function Pass([string]$Name) { Write-Host "PASS $Name" }
function Fail([string]$Name) { Write-Host "FAIL $Name"; $script:failures++ }
function Check([string]$Name, [bool]$Ok) { if ($Ok) { Pass $Name } else { Fail $Name } }

$token = "ops_eyJzaWduSW5BZGRyZXNzIjoibXkuMXBhc3N3b3JkLmNvbSJ9-_$PID"
Set-Content -LiteralPath (Join-Path $work 'token.gpg') -Value 'encrypted'
# Decrypting returns the token, or FAKE_TOKEN when it is set
Set-Content -LiteralPath (Join-Path $bin 'gpg.cmd') -Encoding Ascii -Value "@if defined FAKE_TOKEN (echo %FAKE_TOKEN%) else (echo $token)"
# Fails when the token is wrong. Each vault id has a directory of items; records the vault it was asked for.
Set-Content -LiteralPath (Join-Path $bin 'op.cmd') -Encoding Ascii -Value @"
@echo off
if not "%OP_SERVICE_ACCOUNT_TOKEN%"=="$token" exit /b 1
if "%1 %2"=="vault list" type "%FAKE_VAULTS%" & exit /b 0
if "%1 %2"=="item list" (
  >"$work\requested-vault" echo %4
  type "$work\items\%4\list.json"
  exit /b 0
)
if "%1 %2"=="item get" if "%3"=="broken" exit /b 1
if "%1 %2"=="item get" type "$work\items\%5\%3.json" & exit /b 0
exit /b 4
"@
function Write-Json([string]$Path, $Value) {
    ConvertTo-Json -InputObject $Value -Depth 4 | Set-Content -LiteralPath $Path -Encoding Ascii
    return $Path
}
# Each item is @(title, concealed values...)
function Write-Item([string]$VaultId, [object[]]$Items) {
    $dir = Join-Path $work "items\$VaultId"
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $list = @()
    for ($i = 0; $i -lt $Items.Count; $i++) {
        $title = $Items[$i][0]
        $fields = @(@{ id = 'username'; type = 'STRING'; value = 'someone' }) +
            @($Items[$i] | Select-Object -Skip 1 | ForEach-Object { @{ type = 'CONCEALED'; value = $_ } })
        Write-Json (Join-Path $dir "i$i.json") @{ id = "i$i"; title = $title; fields = $fields } | Out-Null
        $list += @{ id = "i$i"; title = $title }
    }
    Write-Json (Join-Path $dir 'list.json') $list | Out-Null
}
$vaults = Write-Json (Join-Path $work 'vaults.json') @(@{ id = 'v-noodlemap'; name = 'noodlemap' }, @{ id = 'v-lattice'; name = 'lattice' },
    @{ id = 'v-bad'; name = 'bad' }, @{ id = 'v-dupkey'; name = 'dupkey' }, @{ id = 'v-none'; name = 'none' }, @{ id = 'v-two'; name = 'two' },
    @{ id = 'v-broken'; name = 'broken' })
$vaultsDup = Write-Json (Join-Path $work 'vaults-dup.json') @(@{ id = 'v-a'; name = 'dup' }, @{ id = 'v-b'; name = 'dup' })
Write-Item 'v-noodlemap' @(@('CLOUDFLARE_API_TOKEN', 'cf value'), @('MULTI', 'a b = c'), @('EMPTY_EXTRA', 'kept', ''))
Write-Item 'v-bad' @(, @('BAD=NAME', 'x'))
Write-Item 'v-dupkey' @(@('A', '1'), @('a', '2'))
Write-Item 'v-none' @(, @('NOTHING'))
Write-Item 'v-two' @(, @('TWO', 'a', 'b'))
# The fake op fails to get the item with the id broken
Write-Item 'v-broken' @(, @('GOOD', 'g'))
Write-Json (Join-Path $work 'items\v-broken\list.json') @(@{ id = 'i0'; title = 'GOOD' }, @{ id = 'broken'; title = 'BROKEN' }) | Out-Null
$printEnv = Join-Path $work 'printenv.ps1'
Set-Content -LiteralPath $printEnv -Value @'
$caller = if ($null -eq $env:OP_SERVICE_ACCOUNT_TOKEN) { 'unset' } else { $env:OP_SERVICE_ACCOUNT_TOKEN }
Write-Output "$env:CLOUDFLARE_API_TOKEN|$env:MULTI|$env:EMPTY_EXTRA|$caller|$($args -join ',')"
'@
$marker = Join-Path $work 'ran'
$touch = @('pwsh', '-NoProfile', '-Command', "New-Item -ItemType File -Path '$marker' | Out-Null")

$savedPath = $env:Path
$env:Path = "$bin;$env:Path"
$env:OP_RUN_TOKEN_FILE = Join-Path $work 'token.gpg'
$env:FAKE_VAULTS = $vaults

function Invoke-OpRun([string[]]$Arguments) {
    $output = & pwsh -NoProfile -ExecutionPolicy Bypass -File $script @Arguments 2>$null
    return @{ Code = $LASTEXITCODE; Output = ($output -join "`n") }
}
# Runs the command with the given vault, and reports whether it failed without running the command
function Test-FailsWithoutRunning([string]$Vault) {
    Remove-Item -LiteralPath $marker -ErrorAction SilentlyContinue
    $r = Invoke-OpRun (@($Vault, '--') + $touch)
    return ($r.Code -ne 0 -and -not (Test-Path -LiteralPath $marker))
}

try {
    $r = Invoke-OpRun @('noodlemap', '--', 'pwsh', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $printEnv, 'x y', 'z')
    Check 'concealed values reach the command, empty ones are not counted, arguments stay intact' ($r.Output -ceq 'cf value|a b = c|kept|unset|x y,z')
    Check 'the vault name is resolved to its id' ((Get-Content -LiteralPath (Join-Path $work 'requested-vault')).Trim() -eq 'v-noodlemap')

    $env:OP_SERVICE_ACCOUNT_TOKEN = 'caller-token'
    $r = Invoke-OpRun @('noodlemap', 'pwsh', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $printEnv)
    Remove-Item Env:OP_SERVICE_ACCOUNT_TOKEN
    Check 'works without --' ($r.Output -like 'cf value|*')
    Check 'neither the token nor the caller token reaches the command' ($r.Output -like '*|unset|*' -and $r.Output -notlike "*$token*")

    $r = Invoke-OpRun @('noodlemap', '--', 'pwsh', '-NoProfile', '-Command', 'exit 7')
    Check 'the exit code of the command is returned' ($r.Code -eq 7)

    # From PowerShell, op-run.ps1 runs in the caller's own process
    $env:OP_SERVICE_ACCOUNT_TOKEN = 'caller-token'
    $env:MULTI = 'caller multi'
    & $script noodlemap -- pwsh -NoProfile -Command 'exit 0' 2>$null
    Check 'run in the caller process, the secrets are gone and the caller variables are back afterwards' (
        -not (Test-Path Env:CLOUDFLARE_API_TOKEN) -and $env:MULTI -ceq 'caller multi' -and $env:OP_SERVICE_ACCOUNT_TOKEN -ceq 'caller-token')
    & $script --list noodlemap 2>$null | Out-Null
    Check 'run in the caller process, --list leaves the caller token in place' ($env:OP_SERVICE_ACCOUNT_TOKEN -ceq 'caller-token')
    Remove-Item Env:OP_SERVICE_ACCOUNT_TOKEN, Env:MULTI, Env:CLOUDFLARE_API_TOKEN, Env:EMPTY_EXTRA -ErrorAction SilentlyContinue
    & $script broken -- pwsh -NoProfile -Command 'exit 0' 2>$null
    Check 'run in the caller process, a failing op leaves no token behind' (-not (Test-Path Env:OP_SERVICE_ACCOUNT_TOKEN))

    $r = Invoke-OpRun @('--list', 'noodlemap')
    Check '--list prints only the names' ($r.Output -ceq "CLOUDFLARE_API_TOKEN`nEMPTY_EXTRA`nMULTI")

    $shimOutput = (& cmd /c "`"$shim`" noodlemap -- pwsh -NoProfile -ExecutionPolicy Bypass -File `"$printEnv`" `"x y`" z" 2>$null) -join "`n"
    Check 'op-run.cmd passes -- and quoted arguments through cmd' ($shimOutput -ceq 'cf value|a b = c|kept|unset|x y,z')
    & cmd /c "`"$shim`" noodlemap -- pwsh -NoProfile -Command `"exit 7`"" 2>$null | Out-Null
    Check 'op-run.cmd returns the exit code of the command' ($LASTEXITCODE -eq 7)

    Check 'an unknown vault fails' ((Invoke-OpRun @('nope', '--', 'pwsh', '-NoProfile', '-Command', 'exit 0')).Code -ne 0)

    $env:FAKE_VAULTS = $vaultsDup
    Check 'two vaults with the same name fail, and the command does not run' (Test-FailsWithoutRunning 'dup')
    $env:FAKE_VAULTS = $vaults

    Check 'a name that cannot be an environment variable fails, and the command does not run' (Test-FailsWithoutRunning 'bad')
    Check 'two items with the same name (ignoring case) fail, and the command does not run' (Test-FailsWithoutRunning 'dupkey')
    Check 'an item without a concealed field fails, and the command does not run' (Test-FailsWithoutRunning 'none')
    Check 'an item with two concealed fields fails, and the command does not run' (Test-FailsWithoutRunning 'two')
    Check 'an item that op cannot get fails, and the command does not run' (Test-FailsWithoutRunning 'broken')

    $env:OP_RUN_TOKEN_FILE = Join-Path $work 'missing.gpg'
    Check 'a missing token file fails' ((Invoke-OpRun @('noodlemap', '--', 'pwsh', '-NoProfile', '-Command', 'exit 0')).Code -ne 0)
    $env:OP_RUN_TOKEN_FILE = Join-Path $work 'token.gpg'

    Check 'a missing command fails' ((Invoke-OpRun @('noodlemap', '--')).Code -ne 0)

    Remove-Item -LiteralPath $marker -ErrorAction SilentlyContinue
    $env:FAKE_TOKEN = "$token$token"
    $err = (& pwsh -NoProfile -ExecutionPolicy Bypass -File $script @(@('noodlemap', '--') + $touch) 2>&1) -join "`n"
    $code = $LASTEXITCODE
    Remove-Item Env:FAKE_TOKEN
    Check 'a malformed stored token fails with that reason, and the command does not run' ($code -ne 0 -and $err -like '*token is malformed*' -and -not (Test-Path -LiteralPath $marker))
} finally {
    $env:Path = $savedPath
    Remove-Item Env:OP_RUN_TOKEN_FILE, Env:FAKE_VAULTS, Env:FAKE_TOKEN -ErrorAction SilentlyContinue
    Remove-Item -Recurse -Force -LiteralPath $work -ErrorAction SilentlyContinue
}

if ($failures -gt 0) {
    Write-Host "$failures problem(s) found"
    exit 1
}
Write-Host 'No problems found'
exit 0
