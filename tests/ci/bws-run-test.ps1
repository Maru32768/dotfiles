# Tests bws-run.ps1 and bws-run.cmd (home/dot_local/bin) with fake gpg and bws. No network, no keys.
# Keep this file ASCII: Windows PowerShell 5.1 misreads UTF-8 without a BOM.
#
#   pwsh -File tests\ci\bws-run-test.ps1
$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).ProviderPath
$script = Join-Path $root 'home\dot_local\bin\bws-run.ps1'
$shim = Join-Path $root 'home\dot_local\bin\bws-run.cmd'
$work = Join-Path ([System.IO.Path]::GetTempPath()) "bws-run-test-$PID"
$bin = Join-Path $work 'bin'
New-Item -ItemType Directory -Force -Path $bin | Out-Null
$failures = 0

function Pass([string]$Name) { Write-Host "PASS $Name" }
function Fail([string]$Name) { Write-Host "FAIL $Name"; $script:failures++ }
function Check([string]$Name, [bool]$Ok) { if ($Ok) { Pass $Name } else { Fail $Name } }

$token = "test-token-$PID"
Set-Content -LiteralPath (Join-Path $work 'token.gpg') -Value 'encrypted'
Set-Content -LiteralPath (Join-Path $bin 'gpg.cmd') -Encoding Ascii -Value "@echo $token"
# Fails when the token is wrong. Returns secrets for any id and records the id it was asked for.
Set-Content -LiteralPath (Join-Path $bin 'bws.cmd') -Encoding Ascii -Value @"
@echo off
if not "%BWS_ACCESS_TOKEN%"=="$token" exit /b 1
if "%1 %2"=="project list" type "%FAKE_PROJECTS%" & exit /b 0
if "%1 %2"=="secret list" (
  >"$work\requested-id" echo %3
  type "%FAKE_SECRETS%"
  exit /b 0
)
exit /b 4
"@
function Write-Json([string]$Name, $Value) {
    $path = Join-Path $work $Name
    ConvertTo-Json -InputObject $Value -Depth 3 | Set-Content -LiteralPath $path -Encoding Ascii
    return $path
}
$projects = Write-Json 'projects.json' @(@{ id = 'id-noodlemap'; name = 'noodlemap' }, @{ id = 'id-lattice'; name = 'lattice' })
$projectsDup = Write-Json 'projects-dup.json' @(@{ id = 'id-a'; name = 'dup' }, @{ id = 'id-b'; name = 'dup' })
$secrets = Write-Json 'secrets.json' @(@{ key = 'CLOUDFLARE_API_TOKEN'; value = 'cf value' }, @{ key = 'MULTI'; value = "a b = c" })
$secretsBad = Write-Json 'secrets-bad.json' @(@{ key = 'BAD-NAME'; value = 'x' })
$secretsDup = Write-Json 'secrets-dup.json' @(@{ key = 'A'; value = '1' }, @{ key = 'a'; value = '2' })
$printEnv = Join-Path $work 'printenv.ps1'
Set-Content -LiteralPath $printEnv -Value @'
$caller = if ($null -eq $env:BWS_ACCESS_TOKEN) { 'unset' } else { $env:BWS_ACCESS_TOKEN }
Write-Output "$env:CLOUDFLARE_API_TOKEN|$env:MULTI|$caller|$($args -join ',')"
'@
$marker = Join-Path $work 'ran'
$touch = @('pwsh', '-NoProfile', '-Command', "New-Item -ItemType File -Path '$marker' | Out-Null")

$savedPath = $env:Path
$env:Path = "$bin;$env:Path"
$env:BWS_TOKEN_FILE = Join-Path $work 'token.gpg'
$env:FAKE_PROJECTS = $projects
$env:FAKE_SECRETS = $secrets

function Invoke-BwsRun([string[]]$Arguments) {
    $output = & pwsh -NoProfile -ExecutionPolicy Bypass -File $script @Arguments 2>$null
    return @{ Code = $LASTEXITCODE; Output = ($output -join "`n") }
}

try {
    $r = Invoke-BwsRun @('noodlemap', '--', 'pwsh', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $printEnv, 'x y', 'z')
    Check 'secrets reach the command, arguments stay intact' ($r.Output -ceq 'cf value|a b = c|unset|x y,z')
    Check 'the project name is resolved to its id' ((Get-Content -LiteralPath (Join-Path $work 'requested-id')).Trim() -eq 'id-noodlemap')

    $env:BWS_ACCESS_TOKEN = 'caller-token'
    $r = Invoke-BwsRun @('noodlemap', 'pwsh', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $printEnv)
    Remove-Item Env:BWS_ACCESS_TOKEN
    Check 'works without --' ($r.Output -like 'cf value|*')
    Check 'neither the token nor the caller token reaches the command' ($r.Output -like '*|unset|*' -and $r.Output -notlike "*$token*")

    $r = Invoke-BwsRun @('noodlemap', '--', 'pwsh', '-NoProfile', '-Command', 'exit 7')
    Check 'the exit code of the command is returned' ($r.Code -eq 7)

    $r = Invoke-BwsRun @('--list', 'noodlemap')
    Check '--list prints only the names' ($r.Output -ceq "CLOUDFLARE_API_TOKEN`nMULTI")

    $shimOutput = (& cmd /c "`"$shim`" noodlemap -- pwsh -NoProfile -ExecutionPolicy Bypass -File `"$printEnv`" `"x y`" z" 2>$null) -join "`n"
    Check 'bws-run.cmd passes -- and quoted arguments through cmd' ($shimOutput -ceq 'cf value|a b = c|unset|x y,z')

    Check 'an unknown project fails' ((Invoke-BwsRun @('nope', '--', 'pwsh', '-NoProfile', '-Command', 'exit 0')).Code -ne 0)

    $env:FAKE_PROJECTS = $projectsDup
    $r = Invoke-BwsRun (@('dup', '--') + $touch)
    $env:FAKE_PROJECTS = $projects
    Check 'two projects with the same name fail, and the command does not run' ($r.Code -ne 0 -and -not (Test-Path -LiteralPath $marker))

    Remove-Item -LiteralPath $marker -ErrorAction SilentlyContinue
    $env:FAKE_SECRETS = $secretsBad
    $r = Invoke-BwsRun (@('noodlemap', '--') + $touch)
    Check 'a name that cannot be an environment variable fails, and the command does not run' ($r.Code -ne 0 -and -not (Test-Path -LiteralPath $marker))

    $env:FAKE_SECRETS = $secretsDup
    Check 'two secrets with the same name (ignoring case) fail' ((Invoke-BwsRun @('noodlemap', '--', 'pwsh', '-NoProfile', '-Command', 'exit 0')).Code -ne 0)
    $env:FAKE_SECRETS = $secrets

    $env:BWS_TOKEN_FILE = Join-Path $work 'missing.gpg'
    Check 'a missing token file fails' ((Invoke-BwsRun @('noodlemap', '--', 'pwsh', '-NoProfile', '-Command', 'exit 0')).Code -ne 0)
    $env:BWS_TOKEN_FILE = Join-Path $work 'token.gpg'

    Check 'a missing command fails' ((Invoke-BwsRun @('noodlemap', '--')).Code -ne 0)
} finally {
    $env:Path = $savedPath
    Remove-Item Env:BWS_TOKEN_FILE, Env:FAKE_PROJECTS, Env:FAKE_SECRETS -ErrorAction SilentlyContinue
    Remove-Item -Recurse -Force -LiteralPath $work -ErrorAction SilentlyContinue
}

if ($failures -gt 0) {
    Write-Host "$failures problem(s) found"
    exit 1
}
Write-Host 'No problems found'
exit 0
