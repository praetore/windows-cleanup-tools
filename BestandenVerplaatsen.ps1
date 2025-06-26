<#
.SYNOPSIS
    Verplaatst of kopieert bestanden naar een doelmap vanaf een opgegeven pad of een bestand met bestandspaden.

.DESCRIPTION
    Doorzoekt recursief een map (-Path) of leest een bestand (-File) met bestandsnamen en verplaatst of kopieert de bestanden naar een doelmap (-Out).
    Bij gebruik van een CSV-bestand met 'Bestand' en 'Bestemming' kolommen worden de bestanden naar de opgegeven bestemmingen verplaatst of gekopieerd.
    Het pad vóór en na verwerking wordt gelogd in een CSV-bestand.

.PARAMETER Path
    Bronmap die moet worden doorzocht (optioneel als -File is opgegeven).

.PARAMETER File
    Pad naar een bestand met te verwerken bestanden. Dit kan een CSV-bestand zijn met een kolom 'Bestand' of een tekstbestand met één bestandspad per regel.

.PARAMETER Out
    Doelmap waarin bestanden geplaatst worden.

.PARAMETER Copy
    Voeg deze switch toe als je bestanden wilt kopiëren in plaats van verplaatsen.

.PARAMETER LogFile
    Optioneel pad naar een CSV-logbestand. Indien niet opgegeven, wordt automatisch move-[timestamp].csv aangemaakt.


.EXAMPLE
    .\BestandenVerplaatsen.ps1 -Path "C:\Backup" -Out "C:\Resultaat"
    # Verplaatst alle bestanden uit de map C:\Backup naar C:\Resultaat

    .\BestandenVerplaatsen.ps1 -File "systeembestanden.csv" -Out "C:\Doel" -Copy
    # Kopieert bestanden uit een CSV-bestand met een 'Bestand' kolom naar C:\Doel

    .\BestandenVerplaatsen.ps1 -File "gebruikersbestanden.csv"
    # Kopieert bestanden uit een CSV-bestand met 'Bestand' en 'Bestemming' kolommen naar de opgegeven bestemmingen

    .\BestandenVerplaatsen.ps1 -File "te_verplaatsen.txt" -Out "C:\Doel"
    # Verplaatst bestanden uit een tekstbestand met één bestandspad per regel naar C:\Doel
#>

param (
    [string]$Path,
    [string]$File,

    [Parameter(Mandatory = $false)]
    [string]$Out,

    [switch]$Copy,

    [string]$LogFile
)

# Import shared module
$modulePath = Join-Path $PSScriptRoot "SharedModule"
Import-Module $modulePath -Force

if (-not $Path -and -not $File) {
    Write-Error "❌ Geef óf -Path óf -File op."
    exit 1
}

if ($Path -and -not $Out) {
    Write-Error "❌ Bij gebruik van -Path is -Out verplicht."
    exit 1
}


# Outputmap normaliseren als -Out is opgegeven
if ($Out) {
    $doelRoot = Get-NormalizedPath -Path $Out -CreateIfNotExists
}

# Output CSV instellen
if ($LogFile) {
    if (Test-Path $LogFile) {
        Write-Error "❌ Outputbestand bestaat al: $LogFile"
        exit
    }
    $csvPath = $LogFile
} else {
    $base = Join-Path $PSScriptRoot ("herstel-verplaatsen-{0:yyyyMMdd-HHmmss}" -f (Get-Date))
    $i = 0
    do {
        $csvPath = if ($i -eq 0) { "$base.csv" } else { "$base-$i.csv" }
        $i++
    } while (Test-Path $csvPath)
}

# Verzamel bestanden
$bestanden = @()
if ($Path) {
    $bronMap = Get-NormalizedPath -Path $Path
    $bestanden = Get-ChildItem -Path $bronMap -Recurse -File
} elseif ($File) {
    if (-not (Test-Path $File)) {
        Write-Error "❌ Bestand niet gevonden: $File"
        exit 1
    }

    # Bepaal of het een CSV of tekstbestand is
    $fileContent = Get-Content -Path $File -TotalCount 1 -ErrorAction Stop
    $isCSV = $fileContent -match ","

    if ($isCSV) {
        # Verwerk als CSV
        $csv = Import-Csv -Path $File -ErrorAction Stop
        if (-not $csv[0].PSObject.Properties["Bestand"]) {
            Write-Error "❌ CSV mist kolom 'Bestand'"
            exit 1
        }

        # Controleer of er een 'Bestemming' kolom is
        $heeftBestemming = $csv[0].PSObject.Properties["Bestemming"] -ne $null

        if ($heeftBestemming -and -not $Out) {
            # Gebruik bestemmingen uit CSV
            $gebruikCsvBestemming = $true
            # Standaard kopiëren bij gebruik van CSV-bestemmingen, tenzij expliciet anders aangegeven
            if (-not $PSBoundParameters.ContainsKey('Copy')) {
                $Copy = $true
                Write-Host "✅ Bestanden worden standaard gekopieerd bij gebruik van CSV-bestemmingen"
            }
            Write-Host "✅ Bestemmingen worden uit CSV-kolom 'Bestemming' gehaald"
        } elseif (-not $heeftBestemming -and -not $Out) {
            Write-Error "❌ CSV heeft geen 'Bestemming' kolom en -Out is niet opgegeven"
            exit 1
        }

        # Bewaar CSV data voor later gebruik
        $csvData = $csv

        # Haal bestandsobjecten op met koppeling naar originele CSV-rij
        $bestandenMetCsv = @()
        foreach ($rij in $csv) {
            if (Test-Path $rij.Bestand) {
                $bestandsObject = Get-Item $rij.Bestand
                $bestandenMetCsv += [PSCustomObject]@{
                    BestandsObject = $bestandsObject
                    CsvRij = $rij
                }
            }
        }

        if ($gebruikCsvBestemming) {
            # Gebruik de gecombineerde array voor verwerking
            $bestanden = $bestandenMetCsv
        } else {
            # Gebruik alleen de bestandsobjecten voor verwerking
            $bestanden = $bestandenMetCsv | ForEach-Object { $_.BestandsObject }
        }
    } else {
        # Verwerk als tekstbestand met één pad per regel
        if (-not $Out) {
            Write-Error "❌ Bij gebruik van een tekstbestand is -Out verplicht"
            exit 1
        }

        $bestandsPaden = Get-Content -Path $File -ErrorAction Stop | Where-Object { $_ -and (-not $_.StartsWith("#")) }
        $bestanden = $bestandsPaden | Where-Object { Test-Path $_ } | ForEach-Object {
            Get-Item $_
        }
    }
}

$log = @()

foreach ($item in $bestanden) {
    # Bepaal of we met een gecombineerd object of direct bestandsobject werken
    $bestand = if ($gebruikCsvBestemming) { $item.BestandsObject } else { $item }
    $csvRij = if ($gebruikCsvBestemming) { $item.CsvRij } else { $null }

    if ($gebruikCsvBestemming) {
        # Gebruik bestemming uit CSV
        $doelBestand = $csvRij.Bestemming
        $doelMap = Split-Path -Path $doelBestand -Parent

        # Zorg dat de doelmap bestaat
        if (-not (Test-Path $doelMap)) {
            New-Item -Path $doelMap -ItemType Directory -Force | Out-Null
        }
    } else {
        # Gebruik -Out parameter zonder categorisatie
        # Plaats bestanden direct in de doelmap of behoud de originele mapstructuur
        $doelBestand = Join-Path $doelRoot $bestand.Name

        # Zorg dat de doelmap bestaat
        if (-not (Test-Path $doelRoot)) {
            New-Item -Path $doelRoot -ItemType Directory -Force | Out-Null
        }
    }

    try {
        if ($Copy) {
            Copy-Item -Path $bestand.FullName -Destination $doelBestand -Force
        } else {
            Move-Item -Path $bestand.FullName -Destination $doelBestand -Force
        }

        $log += [PSCustomObject]@{
            Origineel   = $bestand.FullName
            Bestemming = $doelBestand
            Actie      = if ($Copy) { "Gekopieerd" } else { "Verplaatst" }
        }

        # Toon actie en bestemming
        Write-Host "$($log[-1].Actie): $($bestand.Name) → $doelBestand"
    } catch {
        Write-Warning "⚠️  Kon niet verwerken: $($bestand.FullName) - $_"
    }
}

# Schrijf log
$log | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
Write-Host "`n✅ Log opgeslagen in: $csvPath"
