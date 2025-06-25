<#
.SYNOPSIS
    Ordent bestanden uit een opgegeven map in jaar/maand-submappen op basis van laatste wijzigingsdatum.

.DESCRIPTION
    Doorzoekt een opgegeven map (-Path) recursief naar bestanden en verplaatst elk bestand naar een submap
    in de doelmap (-Out) gebaseerd op het jaar en de maand van de laatste wijziging (LastWriteTime).
    
    Als een bestand met dezelfde naam al bestaat in de doelmap, wordt er een timestamp aan de bestandsnaam toegevoegd
    om naamconflicten te voorkomen.

.PARAMETER Path
    De bronmap die je wilt ordenen (wordt recursief doorzocht naar bestanden).

.PARAMETER Out
    De doelmap waarin de bestanden geordend worden in submappen zoals: \2024\06\bestand.pdf

.EXAMPLE
    .\OrdenOpDatum.ps1 -Path "C:\Data\MijnBestanden" -Out "C:\Data\Geordend"
    → Verplaatst alle bestanden uit MijnBestanden naar Geordend\[Jaar]\[Maand]\...

.NOTES
    - Bestanden worden fysiek verplaatst, niet gekopieerd.
    - Submappen worden automatisch aangemaakt indien nodig.
    - Bij dubbele bestandsnamen wordt een timestamp toegevoegd om conflicten te vermijden.
#>


param (
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [Parameter(Mandatory = $true)]
    [string]$Out
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

# 📦 Haal ALLE bestanden op, inclusief submappen
$bestanden = Get-ChildItem -Path $bronMap -File -Recurse -Force

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
        Write-Host "Verplaatst: $($bestand.FullName) → $doelBestand"
    } catch {
        Write-Warning "Kon niet verplaatsen: $($bestand.FullName) - $_"
    }
}
