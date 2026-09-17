param([ValidateSet('x64', 'arm64')][string]$Architecture = 'x64')
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$directory = Join-Path $root "dist/windows/$Architecture"
$exe = Join-Path $directory 'WachModus.exe'
if (-not (Test-Path $exe)) {
    if ($env:GITHUB_REF -eq 'refs/heads/main') { throw 'Die direkt startbare EXE fehlt auf main.' }
    Write-Host 'Erstprüfung: Die EXE wird nach erfolgreichen Tests in main aufgenommen.'
    exit 0
}
$manifest = Get-Content (Join-Path $directory 'build-info.json') -Raw | ConvertFrom-Json
if ((Get-FileHash $exe -Algorithm SHA256).Hash.ToLowerInvariant() -ne $manifest.sha256) { throw 'EXE-Prüfsumme stimmt nicht mit dem Build-Protokoll überein.' }
$isolated = Join-Path $root "artifacts/standalone-$Architecture"
New-Item -ItemType Directory -Force $isolated | Out-Null
Copy-Item $exe (Join-Path $isolated 'WachModus.exe') -Force
$report = Join-Path $isolated 'checkout-exe.json'
# Only the EXE is copied; neither development output nor an installed .NET runtime is used.
$env:DOTNET_ROOT = Join-Path $isolated 'no-runtime'
$env:DOTNET_MULTILEVEL_LOOKUP = '0'
$process = Start-Process -FilePath (Join-Path $isolated 'WachModus.exe') -ArgumentList @('--selftest', '--report', ('"{0}"' -f $report)) -PassThru
if (-not $process.WaitForExit(120000)) { $process.Kill(); throw 'Die ausgecheckte EXE reagiert nicht.' }
$process.Refresh()
if ($process.ExitCode -ne 0) { if (Test-Path $report) { Get-Content $report }; throw 'Die ausgecheckte EXE besteht den Selbsttest nicht.' }
if (-not ((Get-Content $report -Raw | ConvertFrom-Json).passed)) { throw 'EXE-Prüfungen fehlgeschlagen.' }
& "$PSScriptRoot/test-app-startup.ps1" -Executable (Join-Path $isolated 'WachModus.exe') -Report (Join-Path $isolated 'checkout-startup.json')
Write-Host 'Die direkt ausgecheckte EXE funktioniert eigenständig.'
