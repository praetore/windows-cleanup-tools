<#
.SYNOPSIS
    Classificeert individuele bestanden o.b.v. extensie, naam, pad, afbeeldingsresolutie en bestandsgrootte.

.DESCRIPTION
    Doorzoekt een pad recursief en bepaalt per bestand de categorie, scores en classificatie.
    Kleine afbeeldingen (<= 256x256 px) óf een afbeeldingsbestand <= 50KB krijgen extra verdacht-score.

    Classificaties:
        - Waarschijnlijk gebruikersbestand
        - Waarschijnlijk systeembestand
        - Onbeslist

.OUTPUT
    CSV-bestanden in classificatie-<timestamp> map + overzicht.html

.OUTPUT VOORBEELD
    Bestand,Categorie,GrootteKB,Score,Classificatie
    C:\data\setup.exe,Onbekend,148,V:2 / G:0,Waarschijnlijk systeembestand
    C:\data\boeken\jaar.pdf,Documenten,383,V:0 / G:2,Waarschijnlijk gebruikersbestand
    C:\icons\gear.png,Afbeeldingen,13,V:2 / G:1,Waarschijnlijk systeembestand

.PARAMETER Path
    Het pad dat recursief doorzocht moet worden voor bestanden om te classificeren.

.PARAMETER Config
    Optioneel pad naar een JSON-configuratiebestand. Indien niet opgegeven, wordt "config.json" in dezelfde map als het script gebruikt.

.EXAMPLE
    .\ClassificeerBestanden.ps1 -Path "C:\Data\TeClassificeren"

    .\ClassificeerBestanden.ps1 -Path "C:\Data\TeClassificeren" -Config "mijn-config.json"
#>

param (
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [string]$Config = "config.json"
)

Add-Type -AssemblyName System.Drawing

# --- Laad configuratie uit JSON bestand ---
$configPath = if ([System.IO.Path]::IsPathRooted($Config)) {
    $Config
} else {
    Join-Path $PSScriptRoot $Config
}
if (Test-Path $configPath) {
    try {
        $config = Get-Content -Path $configPath -Raw | ConvertFrom-Json

        # Converteer JSON arrays naar PowerShell arrays/hashtables
        $categorieMap = @{}
        foreach ($property in $config.user.extensions.PSObject.Properties) {
            $categorieMap[$property.Name] = $property.Value
        }

        $systeemExts = $config.system.extensions
        $verdachteNaamKeywords = $config.system.files
        $systeemMapKeywords = $config.system.directories
        $gebruikersMapKeywords = $config.user.directories

        Write-Host "✅ Configuratie geladen uit $configPath"
    }
    catch {
        Write-Error "❌ Fout bij laden van configuratie: $_"
        exit 1
    }
}
else {
    Write-Error "❌ Configuratiebestand niet gevonden: $configPath"
    exit 1
}

function Get-Categorie($ext) {
    foreach ($key in $categorieMap.Keys) {
        if ($categorieMap[$key] -contains $ext.ToLower()) {
            return $key
        }
    }
    return "Onbekend"
}

# --- Padvalidatie ---
$volledigPad = Resolve-Path $Path
if (-not (Test-Path $volledigPad)) {
    Write-Error "❌ Pad bestaat niet: $volledigPad"
    exit 1
}

# --- Outputmap ---
$ts = Get-Date -Format "yyyyMMdd-HHmmss"
$outputMap = Join-Path $PSScriptRoot "classificatie-$ts"
New-Item -Path $outputMap -ItemType Directory -Force | Out-Null

# --- Analyse ---
$alleBestanden = Get-ChildItem -Path $volledigPad -Recurse -File -Force -ErrorAction SilentlyContinue
$regels = @()

foreach ($bestand in $alleBestanden) {
    $ext = $bestand.Extension.ToLower()
    $naam = $bestand.Name.ToLower()
    $pad = $bestand.FullName.ToLower()
    $cat = Get-Categorie $ext

    $scoreV = 0
    $scoreG = 0

    if ($systeemExts -contains $ext) { $scoreV++ }
    if ($cat -ne "Onbekend") { $scoreG++ }

    $scoreV += ($verdachteNaamKeywords | Where-Object { $naam -like "*$_*" }).Count
    $scoreV += ($systeemMapKeywords   | Where-Object { $pad -like "*\$_\*" }).Count
    $scoreG += ($gebruikersMapKeywords | Where-Object { $pad -like "*\$_\*" }).Count

    if ($cat -eq "Afbeeldingen") {
        try {
            $img = [System.Drawing.Image]::FromFile($bestand.FullName)
            if ($img.Width -le 256 -and $img.Height -le 256) { $scoreV++ }
            if ($bestand.Length -lt 51200) { $scoreV++ }  # onder 50KB
            $img.Dispose()
        } catch {}
    }

    $classificatie = "Onbeslist"
    if ($scoreV -ge 2 -and $scoreG -lt 2) {
        $classificatie = "Waarschijnlijk systeembestand"
    } elseif ($scoreG -ge 2 -and $scoreV -lt 2) {
        $classificatie = "Waarschijnlijk gebruikersbestand"
    }

    $regels += [PSCustomObject]@{
        Bestand = $bestand.FullName
        Categorie = $cat
        GrootteKB = [int]($bestand.Length / 1KB)
        Score = "V:$scoreV / G:$scoreG"
        Classificatie = $classificatie
    }
}

# --- Output ---
$regels | Where-Object { $_.Classificatie -eq "Waarschijnlijk systeembestand" } |
    Export-Csv "$outputMap\systeem.csv" -NoTypeInformation -Encoding UTF8

$regels | Where-Object { $_.Classificatie -eq "Waarschijnlijk gebruikersbestand" } |
    Export-Csv "$outputMap\gebruikers.csv" -NoTypeInformation -Encoding UTF8

$regels | Where-Object { $_.Classificatie -eq "Onbeslist" } |
    Export-Csv "$outputMap\onbekend.csv" -NoTypeInformation -Encoding UTF8

$regels | Sort-Object Classificatie |
    ConvertTo-Html -Title "Bestandsclassificatie" -Property Bestand, Categorie, GrootteKB, Score, Classificatie |
    Out-File "$outputMap\overzicht.html"

Write-Host "✅ Classificatie voltooid: $outputMap"
