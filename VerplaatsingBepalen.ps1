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

.PARAMETER Llm
    Optionele switch om een lokaal LLM (Language Model) te gebruiken voor het bepalen van de submap. 
    Gebruikt LMStudio of Ollama om te suggereren waar bestanden geplaatst moeten worden op basis van pad, categorie en extensie.
    Bestanden worden in batches verwerkt voor efficiëntere LLM-verwerking, gegroepeerd op categorie en extensie.
    Het LLM zal proberen bestanden te clusteren in logische groepen, zoals bestanden die bij dezelfde entiteit, persoon of gebeurtenis horen
    (bijv. "Vakantie 2022" of "Familie Jansen"), om een betere mapstructuur te creëren.

.PARAMETER BatchSize
    Optionele parameter om de grootte van de batches te bepalen bij het gebruik van LLM. 
    Standaard is dit 100 bestanden per batch. Alleen van toepassing als -Llm is opgegeven.

.EXAMPLE
    .\VerplaatsingBepalen.ps1 -File "te_verplaatsen.txt" -Out "C:\Doel"
    # Genereert een CSV-bestand met bestanden uit te_verplaatsen.txt en hun bestemmingen in C:\Doel

.EXAMPLE
    .\VerplaatsingBepalen.ps1 -File "te_verplaatsen.txt" -Out "C:\Doel" -OutFile "verplaatslijst.csv"
    # Genereert een CSV-bestand met de naam verplaatslijst.csv

.EXAMPLE
    .\VerplaatsingBepalen.ps1 -File "te_verplaatsen.txt" -Out "C:\Doel" -Config "mijn-config.json"
    # Gebruikt een aangepast configuratiebestand

.EXAMPLE
    .\VerplaatsingBepalen.ps1 -File "te_verplaatsen.txt" -Out "C:\Doel" -Llm
    # Gebruikt een lokaal LLM om de submap te bepalen

.EXAMPLE
    .\VerplaatsingBepalen.ps1 -File "te_verplaatsen.txt" -Out "C:\Doel" -Llm -BatchSize 50
    # Gebruikt een lokaal LLM om de submap te bepalen met een batchgrootte van 50 bestanden
#>

param (
    [Parameter(Mandatory = $true)]
    [string]$File,

    [Parameter(Mandatory = $true)]
    [string]$Out,

    [string]$OutFile,

    [string]$Config = "config.json",

    [switch]$Llm,

    [int]$BatchSize = 100
)

# Import shared module
$modulePath = Join-Path $PSScriptRoot "SharedModule"
Import-Module $modulePath -Force

# Import LLM module
$llmModulePath = Join-Path $PSScriptRoot "LlmModule"
Import-Module $llmModulePath -Force

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

# Bereid bestanden voor op verwerking
if ($Llm) {
    Write-Host "`n🔄 Bestanden voorbereiden voor batch verwerking met LLM..."

    # Bereid bestanden voor op batch verwerking
    $filesForBatch = @()

    foreach ($bestand in $bestanden) {
        $ext = $bestand.Extension
        $categorie = Get-Categorie -Extension $ext -CategorieMap $categorieMap -Config $config

        $filesForBatch += [PSCustomObject]@{
            FilePath = $bestand.FullName
            FileName = $bestand.Name
            Extension = $ext
            Category = $categorie
            ParentDir = Split-Path $bestand.DirectoryName -Leaf
        }
    }

    # Verwerk bestanden in batches
    Write-Host "`n🚀 Verwerken van bestanden in batches (batchgrootte: $BatchSize)..."
    $batchResults = Get-BatchLlmSuggestions -Files $filesForBatch -BatchSize $BatchSize
}

# Verwerk de resultaten
foreach ($bestand in $bestanden) {
    $ext = $bestand.Extension
    $categorie = Get-Categorie -Extension $ext -CategorieMap $categorieMap -Config $config
    $bovenMap = Split-Path $bestand.DirectoryName -Leaf

    # Bepaal de doelmap op basis van de categorie
    $doelBasis = Join-Path $doelRoot $categorie

    # Bepaal de subfolder op basis van LLM of standaard logica
    if ($Llm) {
        # Gebruik het resultaat van de batch verwerking
        if ($batchResults.ContainsKey($bestand.FullName)) {
            $subfolder = $batchResults[$bestand.FullName]
        } else {
            # Fallback naar standaard logica als er geen resultaat is
            $subfolder = if ($bovenMap -ieq "Desktop") { "" } else { $bovenMap }
            Write-Host "⚠️ Geen batch resultaat voor $($bestand.Name), standaard mapindeling gebruikt"
        }
    } else {
        # Standaard verwerking zonder LLM
        $subfolder = if ($bovenMap -ieq "Desktop") { "" } else { $bovenMap }
    }

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

# Toon resultaat
if ($Llm) {
    Write-Host "`n✅ Verplaatslijst opgeslagen in: $csvPath (met LLM suggesties)"
} else {
    Write-Host "`n✅ Verplaatslijst opgeslagen in: $csvPath"
}
