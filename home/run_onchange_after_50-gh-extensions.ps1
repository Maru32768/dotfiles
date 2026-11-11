# gh extension called by the gh-stack skill (home/.chezmoidata/skills.toml). Runs again when the tag changes.
$ErrorActionPreference = 'Stop'
& mise exec gh -- gh extension install github/gh-stack --pin v0.3.0 --force
if ($LASTEXITCODE -ne 0) { throw "gh extension install failed: $LASTEXITCODE" }
