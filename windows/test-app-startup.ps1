param([Parameter(Mandatory)][string]$Executable, [Parameter(Mandatory)][string]$Report)
$ErrorActionPreference = 'Stop'
$first = $null
$second = $null
$checks = [Collections.Generic.List[object]]::new()
try {
    $first = Start-Process -FilePath $Executable -PassThru
    if (-not $first.WaitForInputIdle(20000)) { throw 'Das Hauptfenster wird nicht bereit.' }
    $deadline = [DateTime]::UtcNow.AddSeconds(20)
    do {
        $first.Refresh()
        if ($first.HasExited) { throw 'Die Anwendung beendet sich unerwartet beim Start.' }
        if ($first.MainWindowHandle -ne 0 -and $first.MainWindowTitle -eq 'WachModus') { break }
        Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $deadline)
    if ($first.MainWindowHandle -eq 0 -or $first.MainWindowTitle -ne 'WachModus') { throw 'Das WachModus-Hauptfenster fehlt.' }
    $checks.Add(@{ name = 'Normal EXE startup opens the main window'; passed = $true })

    $second = Start-Process -FilePath $Executable -PassThru
    if (-not $second.WaitForExit(15000)) { throw 'Der zweite Start erzeugt eine weitere Instanz.' }
    $second.Refresh()
    $first.Refresh()
    if ($second.ExitCode -ne 0 -or $first.HasExited) { throw 'Der Schutz vor mehreren Instanzen funktioniert nicht.' }
    $checks.Add(@{ name = 'Second launch reuses the existing instance'; passed = $true })

    if (-not $first.CloseMainWindow() -or -not $first.WaitForExit(15000)) { throw 'Das Hauptfenster lässt sich nicht sauber schließen.' }
    $first.Refresh()
    if ($first.ExitCode -ne 0) { throw 'Die Anwendung meldet einen Fehler beim Beenden.' }
    $checks.Add(@{ name = 'Closing the main window exits successfully'; passed = $true })
    @{ passed = $true; checks = $checks } | ConvertTo-Json -Depth 4 | Set-Content $Report -Encoding utf8NoBOM
} finally {
    foreach ($process in @($second, $first)) {
        if ($null -ne $process) {
            if (-not $process.HasExited) { $process.Kill(); $process.WaitForExit(5000) | Out-Null }
            $process.Dispose()
        }
    }
}
