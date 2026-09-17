# WachModus ☕

WachModus hält deinen Mac oder Windows-PC während einer Sitzung wach. Mit kompakter blauer Oberfläche, mitwachsender Schrift und Bedienung, Pause/Fortsetzen, Timer und Zugriff über Menüleiste bzw. Infobereich.

## Windows: auschecken und EXE starten

```powershell
git clone https://github.com/andershow88/awakemodus.git
cd awakemodus
.\dist\windows\x64\WachModus.exe
```

Oder im Explorer **`dist/windows/x64/WachModus.exe` doppelklicken**. Die EXE enthält ihre .NET-Laufzeit. Kein Installer, kein zusätzliches .NET und keine Administratorrechte erforderlich. Du kannst die EXE auch alleine in einen anderen Ordner kopieren.

- **Intel-/AMD-PC mit 64-Bit-Windows:** [x64-EXE](dist/windows/x64/WachModus.exe)
- **Windows-PC mit ARM-Prozessor:** [ARM64-EXE](dist/windows/arm64/WachModus.exe)
- Unterstützt werden Windows 10/11 (64 Bit); die ARM64-Version wird auf Windows 11 ARM getestet.

Die EXEs sind nicht mit einem kommerziellen Windows-Code-Signing-Zertifikat signiert. Windows kann deshalb beim ersten Start einen Hinweis auf einen unbekannten Herausgeber anzeigen. Die SHA-256-Prüfsumme und der Quell-Commit jeder EXE stehen in der jeweiligen `build-info.json`.

Die Laufzeit entpackt beim ersten Start benötigte native Komponenten in den benutzereigenen temporären .NET-Ordner. Einstellungen liegen unter `%LOCALAPPDATA%\WachModus\settings.json`, nicht im ausgecheckten Projekt.

## macOS: starten

Ab macOS 13. `WachModus.app` im Finder doppelklicken oder:

```sh
open WachModus.app
```

Das mitgelieferte App-Bundle ist für Apple Silicon gebaut. Auf einem Intel-Mac mit Xcode Command Line Tools erzeugt `./build.sh` ein passendes Intel-Bundle.

## Bedienung auf beiden Plattformen

- Beim Öffnen startet der Wachmodus automatisch mit der zuletzt gewählten Laufzeit.
- **Unbegrenzt, 30 Minuten, 1 Stunde oder 2 Stunden.** Eine andere Laufzeit zählt ab Auswahl; die bisherige aktive Zeit bleibt erhalten.
- **Pause/Fortsetzen** pausiert auch den Timer. Tastenkürzel: macOS **⌘P**, Windows **Strg+P**.
- Nach Timerablauf endet die Wachhalte-Funktion automatisch. Das Fenster zeigt den Abschluss.
- **Zurücksetzen** stoppt die Sitzung und setzt die aktive Zeit auf null.
- Minimieren lässt die Sitzung weiterlaufen. Das Kaffee-Symbol in der Menüleiste bzw. im Windows-Infobereich bietet Status und Steuerung.
- **Fenster schließen** beendet App und Wachmodus. Außerdem macOS **⌘Q**, Windows **Strg+Q** oder **Alt+F4**.

Das Fenster startet kompakt mit etwa 540 × 460 Punkten Inhalt. Beim Großziehen wachsen Schrift, Symbole, Abstände und Buttons proportional mit. Die normale Titelleiste bleibt zum Verschieben frei. Die Farbpalette stammt aus ChatGBuetti: `#2563EB` in Hell und `#6EA8FF` als Akzent in Dunkel.

## Einstellungen

Das Einstellungen-Symbol öffnet **System/Hell/Dunkel** und den optionalen **F15-Tastaturimpuls**. F15 ist standardmäßig ausgeschaltet und kann belegte Tastenkürzel auslösen.

- macOS: F15 benötigt gegebenenfalls die Freigabe unter Bedienungshilfen. Die App zeigt bei fehlender Freigabe einen Link an.
- Windows: F15 wird mit `SendInput` gesendet; Windows kann Eingaben an Programme mit höheren Rechten blockieren. Für die normale Wachhalte-Funktion sind keine Administratorrechte nötig.

Manuelles Sperren, Zuklappen und erzwungene Unternehmensrichtlinien werden nicht aufgehoben. WachModus garantiert keine Umgehung von Bildschirmschoner- oder Sicherheitssperren.

## Funktionsweise

**macOS:** IOKit-Assertions gegen automatischen Bildschirm- und System-Ruhezustand, eine `ProcessInfo`-Aktivität gegen App Nap sowie alle 25 Sekunden ein Nutzersignal. Die Assertion-ID wird wiederverwendet. Pause, Timerablauf und Beenden geben die Aktivitäten frei.

**Windows:** `SetThreadExecutionState` hält Bildschirm und System während der Sitzung aktiv. Start, Impulse und Freigabe laufen auf demselben UI-Thread. Pause, Timerablauf und Schließen löschen die Anforderungen. Es werden keine Energiepläne oder Sicherheitseinstellungen geändert.

Beide Timer verwenden monotone Zeitmessung, zählen Pausen nicht mit und prüfen beim Aufwachen zuerst das Sitzungsende. Abgelaufene Sitzungen senden keinen weiteren Impuls.

Referenzen: [Apple-Nutzeraktivität](https://developer.apple.com/documentation/iokit/1557127-iopmassertiondeclareuseractivity), [Windows-Wachhalte-API](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-setthreadexecutionstate), [.NET als einzelne EXE](https://learn.microsoft.com/en-us/dotnet/core/deploying/single-file/overview).

## Selbst bauen

### macOS

Voraussetzung: Xcode Command Line Tools mit Swift 5.7 oder neuer.

```sh
./build.sh
./build/WachModus --selftest --system
```

Der Build führt zunächst die Logiktests aus, prüft und signiert das Bundle lokal und ersetzt erst danach die bisherige App.

### Windows

Voraussetzung **nur zum Bauen**: .NET 10 SDK und PowerShell 7.

```powershell
pwsh ./windows/build.ps1 -Runtime win-x64
# Auf einem Windows-ARM-PC:
pwsh ./windows/build.ps1 -Runtime win-arm64
```

Das Skript führt die Logiktests aus, veröffentlicht eine eigenständige EXE, startet deren native Selbsttests und schreibt erst nach erfolgreicher Prüfung `build-info.json`. Standardausgabe: `dist/windows/x64/` bzw. `dist/windows/arm64/`.

Die plattformunabhängige Windows-Sitzungslogik lässt sich auch auf macOS/Linux testen:

```sh
dotnet test windows/WachModus.Tests/WachModus.Tests.csproj -c Release
```

## Tests und Build-Nachweise

[GitHub Actions](https://github.com/andershow88/awakemodus/actions/workflows/test.yml) prüft:

- macOS: Kompilierung, Logiktests und echte IOKit-Systemaufrufe inklusive vollständiger Freigabe.
- Windows x64 **und** ARM64: alle xUnit-Tests, Veröffentlichung mit eingebauter Laufzeit und native Selbsttests aus der fertigen EXE.
- Die echten WPF-Fenster und Buttons: Start, Pause, Fortsetzen, Laufzeiten, Timerablauf, Zurücksetzen, Minimieren und Schließen.
- Normaler EXE-Start, Tray-Icon, Schutz vor mehreren Instanzen und sauberes Beenden über das Fenster.
- Darstellung und Klickflächen bei kompakter, großer, kleiner, breiter und hoher Fenstergröße. Hell-/Dunkel-Screenshots liegen in den Test-Artefakten.
- Zusätzlich die **bereits im Repository enthaltene EXE**, in einen leeren Ordner kopiert und ohne Verweis auf eine installierte .NET-Laufzeit ausgeführt.

Die Selbsttests verändern keine Benutzereinstellungen und senden kein F15. Der native Systemtest setzt kurz echte Wachhalte-Anforderungen und entfernt sie wieder. Testberichte und Screenshots werden als Actions-Artefakte aufbewahrt.

Eine einzelne EXE lässt sich unter Windows auch direkt prüfen:

```powershell
$p = Start-Process .\dist\windows\x64\WachModus.exe -ArgumentList '--selftest --report selftest-results.json' -PassThru -Wait
$p.ExitCode  # 0 = alle Prüfungen erfolgreich
Get-Content selftest-results.json
```

## Projektstruktur

| Pfad | Inhalt |
| --- | --- |
| `main.swift`, `Dashboard.swift`, `KeepAwake.swift` | Native macOS-App |
| `SelfTest.swift`, `build.sh` | macOS-Tests und Build |
| `makeicon.swift`, `WachModus.iconset/` | Gemeinsames Kaffee-Icon |
| `WachModus.app/` | Fertige macOS-App für Apple Silicon |
| `windows/WachModus.Core/` | Windows-Sitzungslogik, Einstellungen und Skalierung |
| `windows/WachModus/` | Native WPF-Oberfläche, Infobereich, Systemaufrufe und EXE-Selbsttest |
| `windows/WachModus.Tests/` | xUnit-Tests |
| `windows/build.ps1` | Windows-Build mit Tests und Prüfsumme |
| `dist/windows/` | Direkt startbare EXEs und Build-Nachweise |
| `.github/workflows/test.yml` | Tests für macOS und beide Windows-Architekturen |
