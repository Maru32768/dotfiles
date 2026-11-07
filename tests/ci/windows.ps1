# Static checks for the PowerShell scripts. Nothing here changes the machine.
# Keep this file ASCII: Windows PowerShell 5.1 misreads UTF-8 without a BOM.
#
#   powershell -ExecutionPolicy Bypass -File tests\ci\windows.ps1          (syntax)
#   pwsh -File tests\ci\windows.ps1 -Analyze                               (needs PSScriptAnalyzer)
#
# The .ps1.tmpl files are skipped: they are not PowerShell until chezmoi renders them.
[CmdletBinding()]
param([switch]$Analyze)

$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).ProviderPath
$files = Get-ChildItem -LiteralPath $root -Recurse -File -Force -Filter '*.ps1' |
    Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' }
$failures = 0

Write-Host "PowerShell $($PSVersionTable.PSVersion)"

foreach ($file in $files) {
    $errors = $null
    $tokens = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
    if ($errors) {
        Write-Host "FAIL syntax: $($file.FullName)"
        $errors | ForEach-Object { Write-Host "  line $($_.Extent.StartLineNumber): $($_.Message)" }
        $failures++
    } else {
        Write-Host "PASS syntax: $($file.Name)"
    }
}

if ($Analyze) {
    foreach ($file in $files) {
        $issues = @(Invoke-ScriptAnalyzer -Path $file.FullName -Severity Error)
        if ($issues.Count -gt 0) {
            Write-Host "FAIL analyzer: $($file.FullName)"
            $issues | ForEach-Object { Write-Host "  line $($_.Line): $($_.RuleName): $($_.Message)" }
            $failures++
        } else {
            Write-Host "PASS analyzer: $($file.Name)"
        }
    }
}

if ($failures -gt 0) {
    Write-Host "$failures problem(s) found"
    exit 1
}
Write-Host 'No problems found'
exit 0
