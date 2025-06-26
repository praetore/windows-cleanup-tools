<#
.SYNOPSIS
    Genereert een CSV-bestand met bestanden en hun bestemmingen op basis van bestandsextensies.

.DESCRIPTION
    Leest een tekstbestand met bestandspaden (één per regel) en bepaalt voor elk bestand in welke submap
    het terecht zou moeten komen binnen een opgegeven doelmap, op basis van de bestandsextensie en de
    configuratie in config.json. Het script verplaatst de bestanden niet daadwerkelijk, maar genereert
    alleen een CSV-bestand met de kolommen 'Bestand' en 'Bestemming'.

.PARAMETER File
    Pad naar een tekstbestand met één bestandspad per regel.

.PARAMETER Out
    Doelmap waarin bestanden geplaatst zouden worden (gebruikt om bestemmingspaden te construeren).

.PARAMETER Config
    Optioneel pad naar een JSON-configuratiebestand. Indien niet opgegeven, wordt "config.json" in dezelfde map als het script gebruikt.

.PARAMETER OutFile
    Optioneel pad naar het CSV-uitvoerbestand. Indien niet opgegeven, wordt automatisch verplaatslijst-[timestamp].csv aangemaakt.

.EXAMPLE
    .\VerplaatsingBepalen.ps1 -File "te_verplaatsen.txt" -Out "C:\Doel"
    # Genereert een CSV-bestand met bestanden uit te_verplaatsen.txt en hun bestemmingen in C:\Doel

.EXAMPLE
    .\VerplaatsingBepalen.ps1 -File "te_verplaatsen.txt" -Out "C:\Doel" -OutFile "verplaatslijst.csv"
    # Genereert een CSV-bestand met de naam verplaatslijst.csv

.EXAMPLE
    .\VerplaatsingBepalen.ps1 -File "te_verplaatsen.txt" -Out "C:\Doel" -Config "mijn-config.json"
    # Gebruikt een aangepast configuratiebestand
#>

param (
    [Parameter(Mandatory = $true)]
    [string]$File,

    [Parameter(Mandatory = $true)]
    [string]$Out,

    [string]$OutFile,

    [string]$Config = "config.json"
)

# Import shared module
$modulePath = Join-Path $PSScriptRoot "SharedModule"
Import-Module $modulePath -Force

# Controleer of het invoerbestand bestaat
if (-not (Test-Path $File)) {
    Write-Error "❌ Bestand niet gevonden: $File"
    exit 1
}

# Laad configuratie uit JSON bestand
$configData = Get-Configuration -ConfigPath $Config
$config = $configData.Config
$categorieMap = $configData.CategorieMap
$systeemExts = $configData.SysteemExts

# Normaliseer doelmap
$doelRoot = Get-NormalizedPath -Path $Out

# Output CSV instellen
if ($OutFile) {
    if (Test-Path $OutFile) {
        Write-Error "❌ Outputbestand bestaat al: $OutFile"
        exit 1
    }
    $csvPath = $OutFile
} else {
    $base = Join-Path $PSScriptRoot ("verplaatslijst-{0:yyyyMMdd-HHmmss}" -f (Get-Date))
    $i = 0
    do {
        $csvPath = if ($i -eq 0) { "$base.csv" } else { "$base-$i.csv" }
        $i++
    } while (Test-Path $csvPath)
}

# Lees bestandspaden uit tekstbestand
$bestandsPaden = Get-Content -Path $File -ErrorAction Stop | Where-Object { $_ -and (-not $_.StartsWith("#")) }
$bestanden = $bestandsPaden | Where-Object { Test-Path $_ } | ForEach-Object {
    Get-Item $_
}

# Genereer verplaatslijst
$verplaatslijst = @()

foreach ($bestand in $bestanden) {
    $ext = $bestand.Extension
    $categorie = Get-Categorie -Extension $ext -CategorieMap $categorieMap -Config $config

    # Bepaal de doelmap op basis van de categorie
    $doelBasis = Join-Path $doelRoot $categorie

    # Bepaal de definitieve doelmap (inclusief eventuele submap)
    $bovenMap = Split-Path $bestand.DirectoryName -Leaf
    $subfolder = if ($bovenMap -ieq "Desktop") { "" } else { $bovenMap }
    $definitieveDoelMap = if ($subfolder) { Join-Path $doelBasis $subfolder } else { $doelBasis }

    # Bepaal het volledige doelpad
    $doelBestand = Join-Path $definitieveDoelMap $bestand.Name

    # Voeg toe aan verplaatslijst
    $verplaatslijst += [PSCustomObject]@{
        Bestand = $bestand.FullName
        Bestemming = $doelBestand
    }

    Write-Host "Toegevoegd: $($bestand.Name) → $categorie\$subfolder"
}

# Schrijf verplaatslijst naar CSV
$verplaatslijst | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
Write-Host "`n✅ Verplaatslijst opgeslagen in: $csvPath"
