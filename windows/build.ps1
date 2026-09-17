param(
    [ValidateSet('win-x64', 'win-arm64')][string]$Runtime = 'win-x64',
    [string]$Output = '',
    [string]$SourceCommit = ''
)
$ErrorActionPreference = 'Stop'
$env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'
$env:DOTNET_GENERATE_ASPNET_CERTIFICATE = 'false'
$root = Split-Path $PSScriptRoot -Parent
if (-not $Output) { $Output = Join-Path $root "dist/windows/$($Runtime.Substring(4))" }
$Output = [IO.Path]::GetFullPath($Output)
New-Item -ItemType Directory -Force $Output | Out-Null
$testResults = Join-Path $root "artifacts/tests-$Runtime"

dotnet test "$PSScriptRoot/WachModus.Tests/WachModus.Tests.csproj" -c Release --logger 'trx;LogFileName=core.trx' --results-directory $testResults
if ($LASTEXITCODE -ne 0) { throw 'Die Logiktests sind fehlgeschlagen.' }

dotnet publish "$PSScriptRoot/WachModus/WachModus.csproj" -c Release -r $Runtime --self-contained true -o $Output
if ($LASTEXITCODE -ne 0) { throw 'Der Windows-Build ist fehlgeschlagen.' }

$exe = Join-Path $Output 'WachModus.exe'
if (-not (Test-Path $exe)) { throw 'Die EXE fehlt.' }
if ((Get-Item $exe).Length -ge 100MB) { throw 'Die EXE überschreitet das GitHub-Dateilimit.' }
$dependencies = Get-ChildItem $Output -File | Where-Object { $_.Extension -in '.dll', '.pdb', '.config' -or $_.Name -like '*.runtimeconfig.json' }
if ($dependencies) { throw "Die Veröffentlichung enthält unerwartete externe Dateien: $($dependencies.Name -join ', ')" }

$report = Join-Path $testResults 'published-exe.json'
$snapshots = Join-Path $testResults 'screenshots'
New-Item -ItemType Directory -Force $testResults | Out-Null
$process = Start-Process -FilePath $exe -ArgumentList @('--selftest', '--report', ('"{0}"' -f $report), '--snapshots', ('"{0}"' -f $snapshots)) -PassThru
if (-not $process.WaitForExit(120000)) { $process.Kill(); throw 'Zeitüberschreitung beim EXE-Selbsttest.' }
$process.Refresh()
if ($process.ExitCode -ne 0) { if (Test-Path $report) { Get-Content $report }; throw "EXE-Selbsttest fehlgeschlagen ($($process.ExitCode))." }
$result = Get-Content $report -Raw | ConvertFrom-Json
if (-not $result.passed) { throw 'Die EXE hat nicht alle Prüfungen bestanden.' }
& "$PSScriptRoot/test-app-startup.ps1" -Executable $exe -Report (Join-Path $testResults 'startup.json')

if (-not $SourceCommit) { $SourceCommit = git -C $root rev-parse HEAD 2>$null }
$manifest = [ordered]@{
    version = '2.2.0'
    runtime = $Runtime
    sourceCommit = $SourceCommit
    executable = 'WachModus.exe'
    sha256 = (Get-FileHash $exe -Algorithm SHA256).Hash.ToLowerInvariant()
    bytes = (Get-Item $exe).Length
    nativeChecks = $result.checks.Count
    startupChecks = 3
    allTestsPassed = $true
}
$manifest | ConvertTo-Json | Set-Content (Join-Path $Output 'build-info.json') -Encoding utf8NoBOM
Write-Host "Fertig: $exe ($($result.checks.Count) native Prüfungen erfolgreich)"
