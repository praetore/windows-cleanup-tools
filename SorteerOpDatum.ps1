<#
.SYNOPSIS
    Ordent bestanden uit een opgegeven map in jaar/maand-submappen op basis van laatste wijzigingsdatum.

.DESCRIPTION
    Doorzoekt een opgegeven map (-Path) recursief naar bestanden en verplaatst elk bestand naar een submap
    in de doelmap (-Out) gebaseerd op het jaar en de maand van de laatste wijziging (LastWriteTime).

    Als een bestand met dezelfde naam al bestaat in de doelmap, wordt er een timestamp aan de bestandsnaam toegevoegd
    om naamconflicten te voorkomen.

    Het pad vóór en na verwerking wordt gelogd in een CSV-bestand, wat later gebruikt kan worden om bestanden
    terug te zetten naar hun originele locatie met het HerstelVerplaatsteBestanden.ps1 script.

.PARAMETER Path
    De bronmap die je wilt ordenen (wordt recursief doorzocht naar bestanden).

.PARAMETER Out
    De doelmap waarin de bestanden geordend worden in submappen zoals: \2024\06\bestand.pdf

.PARAMETER LogFile
    Optioneel pad naar een CSV-logbestand. Indien niet opgegeven, wordt automatisch orden-[timestamp].csv aangemaakt.

.EXAMPLE
    .\SorteerOpDatum.ps1 -Path "C:\Data\MijnBestanden" -Out "C:\Data\Geordend"
    → Verplaatst alle bestanden uit MijnBestanden naar Geordend\[Jaar]\[Maand]\...

.EXAMPLE
    .\SorteerOpDatum.ps1 -Path "C:\Data\MijnBestanden" -Out "C:\Data\Geordend" -LogFile "C:\Logs\mijn-orden-log.csv"
    → Verplaatst bestanden en slaat het log op in het opgegeven bestand

.NOTES
    - Bestanden worden fysiek verplaatst, niet gekopieerd.
    - Submappen worden automatisch aangemaakt indien nodig.
    - Bij dubbele bestandsnamen wordt een timestamp toegevoegd om conflicten te vermijden.
    - Het logbestand kan gebruikt worden om bestanden terug te zetten met HerstelVerplaatsteBestanden.ps1.
#>


param (
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [Parameter(Mandatory = $true)]
    [string]$Out,

    [string]$LogFile
)

# Normalizeer en valideer paden
$bronMap = Convert-Path -LiteralPath $Path
$doelMap = Resolve-Path -Path $Out -ErrorAction SilentlyContinue

if (-not $doelMap) {
    $doelMap = Join-Path -Path (Get-Location) -ChildPath $Out
    New-Item -Path $doelMap -ItemType Directory -Force | Out-Null
}
$doelMap = $doelMap.Path

if (-not (Test-Path $bronMap)) {
    Write-Error "❌ Bronmap bestaat niet: $bronMap"
    exit
}

# Output CSV instellen
if ($LogFile) {
    if (Test-Path $LogFile) {
        Write-Error "❌ Outputbestand bestaat al: $LogFile"
        exit
    }
    $csvPath = $LogFile
} else {
    $base = Join-Path $PSScriptRoot ("ordenen-{0:yyyyMMdd-HHmmss}" -f (Get-Date))
    $i = 0
    do {
        $csvPath = if ($i -eq 0) { "$base.csv" } else { "$base-$i.csv" }
        $i++
    } while (Test-Path $csvPath)
}

# 📦 Haal ALLE bestanden op, inclusief submappen
$bestanden = Get-ChildItem -Path $bronMap -File -Recurse -Force

# Initialiseer log array
$log = @()

foreach ($bestand in $bestanden) {
    $jaar = $bestand.LastWriteTime.ToString("yyyy")
    $maand = $bestand.LastWriteTime.ToString("MM")
    $submap = Join-Path $doelMap "$jaar\$maand"

    if (-not (Test-Path $submap)) {
        New-Item -Path $submap -ItemType Directory -Force | Out-Null
    }

    # Vermijd conflict
    $doelBestand = Join-Path $submap $bestand.Name
    if (Test-Path $doelBestand) {
        $naamZonderExt = [System.IO.Path]::GetFileNameWithoutExtension($bestand.Name)
        $ext = $bestand.Extension
        $timestamp = $bestand.LastWriteTime.ToString("yyyyMMdd_HHmmss")
        $doelBestand = Join-Path $submap "$naamZonderExt`_$timestamp$ext"
    }

    try {
        Move-Item -Path $bestand.FullName -Destination $doelBestand -Force

        $log += [PSCustomObject]@{
            Origineel   = $bestand.FullName
            Bestemming = $doelBestand
            Actie      = "Verplaatst"
        }

        Write-Host "Verplaatst: $($bestand.FullName) → $doelBestand"
    } catch {
        Write-Warning "Kon niet verplaatsen: $($bestand.FullName) - $_"
    }
}

# Schrijf log
$log | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
Write-Host "`n✅ Log opgeslagen in: $csvPath"
