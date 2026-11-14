# Tests lab.ps1 run against a fake wsl.exe that prints what it receives. No WSL, no keys.
# lab.ps1 runs under both Windows PowerShell 5.1 and PowerShell 7, which pass arguments to an
# exe differently. Keep this file ASCII: Windows PowerShell 5.1 misreads UTF-8 without a BOM.
#
#   pwsh -File tests\ci\lab-run-test.ps1
$ErrorActionPreference = 'Stop'
# Windows PowerShell 5.1 would drop the double quotes of a -Prompt before lab.ps1 sees them
if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'Run this with pwsh' }

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).ProviderPath
$lab = Join-Path $root 'lab\lab.ps1'
$work = Join-Path ([System.IO.Path]::GetTempPath()) "lab-run-test-$PID"
New-Item -ItemType Directory -Force -Path $work | Out-Null
$failures = 0

function Check([string]$Name, [bool]$Ok, $Result) {
    if ($Ok) {
        Write-Host "PASS $Name"
    } else {
        Write-Host "FAIL $Name (exit $($Result.Code), args $($Result.Args -join '|'))"
        $script:failures++
    }
}

# PowerShell calls wsl.exe by its full name, so the fake has to be a real exe
Set-Content -LiteralPath (Join-Path $work 'wsl.cs') -Encoding Ascii -Value @'
using System;
class P { static int Main(string[] a) {
  for (int i = 0; i < a.Length; i++) Console.WriteLine("ARG=[" + a[i] + "]");
  if (Console.IsInputRedirected) Console.WriteLine("STDIN_LEN=" + Console.In.ReadToEnd().Length);
  string e = Environment.GetEnvironmentVariable("FAKE_WSL_EXIT");
  return string.IsNullOrEmpty(e) ? 0 : int.Parse(e);
}}
'@
& "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe" /nologo /out:"$work\wsl.exe" "$work\wsl.cs" | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'could not build the fake wsl.exe' }
$env:PATH = "$work;$env:PATH"
$env:ANTHROPIC_API_KEY = 'dummy'

function Invoke-Run([string]$Shell, [string[]]$Arguments, [string]$Exit = '') {
    $env:FAKE_WSL_EXIT = $Exit
    # Windows PowerShell 5.1 turns the stderr of an exe into errors, which Stop would throw
    $ErrorActionPreference = 'Continue'
    $out = 'piped' | & $Shell -NoProfile -ExecutionPolicy Bypass -File $lab run research-x @Arguments 2>&1 | Out-String
    return @{
        Code = $LASTEXITCODE
        Out = $out
        Args = @(($out -split "`r?`n") | Where-Object { $_ -like 'ARG=*' } | ForEach-Object { $_ -replace '^ARG=\[(.*)\]$', '$1' })
    }
}

try {
    $call = '-d|research-x|-u|research|--cd|{0}|-e|/usr/local/bin/research-claude'
    foreach ($shell in 'powershell', 'pwsh') {
        $r = Invoke-Run $shell @()
        Check "${shell}: the default path is ~/work, interactive, with stdin passed on" ((($r.Args -join '|') -eq ($call -f '~/work')) -and $r.Out -match 'STDIN_LEN=[1-9]') $r
        $r = Invoke-Run $shell @('-Path', 'work/run')
        Check "${shell}: a relative path is taken from the home" (($r.Args -join '|') -eq ($call -f '~/work/run')) $r
        # A literal ~/... cannot be tested here: this script's own PowerShell 7 expands it when
        # calling the shell, as bws-run does. The default ~/work above covers a leading ~.
        $r = Invoke-Run $shell @('-Path', '/home/research/x')
        Check "${shell}: an absolute path is passed as it is" (($r.Args -join '|') -eq ($call -f '/home/research/x')) $r
        foreach ($path in 'C:\x', 'C:/x', 'C:\Users\u/work', 'work\run', 'wo"rk') {
            $r = Invoke-Run $shell @('-Path', $path)
            Check "${shell}: $path fails, and wsl.exe is not called" ($r.Code -eq 1 -and $r.Args.Count -eq 0 -and $r.Out -like '*-Path must be a path inside the instance*') $r
        }
        $r = Invoke-Run $shell @('-Path', 'work', '-Prompt', 'one two')
        Check "${shell}: -Prompt goes after -p as one argument, with an empty stdin" ((($r.Args -join '|') -eq (($call -f '~/work') + '|-p|one two')) -and $r.Out -match 'STDIN_LEN=0') $r
        foreach ($prompt in 'say "hi" now', 'dir x\') {
            $r = Invoke-Run $shell @('-Prompt', $prompt)
            Check "${shell}: -Prompt '$prompt' fails, and wsl.exe is not called" ($r.Code -eq 1 -and $r.Args.Count -eq 0 -and $r.Out -like '*-Prompt cannot contain*') $r
        }
        $r = Invoke-Run $shell @('-Prompt', 'x') '3'
        Check "${shell}: -Prompt returns the exit code of wsl.exe" ($r.Code -eq 3) $r
        $r = Invoke-Run $shell @() '4'
        Check "${shell}: the interactive run returns the exit code of wsl.exe" ($r.Code -eq 4) $r
    }
} finally {
    Remove-Item -Recurse -Force -LiteralPath $work -ErrorAction SilentlyContinue
}

if ($failures -gt 0) {
    Write-Host "$failures failed"
    exit 1
}
Write-Host 'All passed'
# The last case leaves LASTEXITCODE at 4, and the pwsh step of GitHub Actions exits with it
exit 0
