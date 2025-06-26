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
    Tekstbestanden met volledige bestandspaden in classificatie-<timestamp> map + overzicht.html

.OUTPUT VOORBEELD
    Tekstbestanden (systeem.txt, gebruikers.txt, onbekend.txt):
    C:\data\setup.exe
    C:\icons\gear.png

    HTML-bestand (overzicht.html) bevat alle details:
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

# Import shared module
$modulePath = Join-Path $PSScriptRoot "SharedModule"
Import-Module $modulePath -Force

Add-Type -AssemblyName System.Drawing

# --- Laad configuratie uit JSON bestand ---
$configData = Get-Configuration -ConfigPath $Config
$config = $configData.Config
$categorieMap = $configData.CategorieMap
$systeemExts = $configData.SysteemExts
$verdachteNaamKeywords = $configData.VerdachteNaamKeywords
$systeemMapKeywords = $configData.SysteemMapKeywords
$gebruikersMapKeywords = $configData.GebruikersMapKeywords

# --- Padvalidatie ---
$volledigPad = Get-NormalizedPath -Path $Path
if (-not (Test-Path $volledigPad)) {
    Write-Error "❌ Pad bestaat niet: $volledigPad"
    exit 1
}

# --- Uitvoermap ---
$ts = Get-Date -Format "yyyyMMdd-HHmmss"
$uitvoerMap = Join-Path $PSScriptRoot "classificatie-$ts"
New-Item -Path $uitvoerMap -ItemType Directory -Force | Out-Null

# --- Analyse ---
$alleBestanden = Get-ChildItem -Path $volledigPad -Recurse -File -Force -ErrorAction SilentlyContinue
$regels = @()

foreach ($bestand in $alleBestanden) {
    $ext = $bestand.Extension.ToLower()
    $naam = $bestand.Name.ToLower()
    $pad = $bestand.FullName.ToLower()
    $cat = Get-Categorie -Extension $ext -CategorieMap $categorieMap -Config $config

    $scoreV = 0
    $scoreG = 0

    if ($systeemExts -contains $ext) { $scoreV++ }
    if ($categorieMap.Keys -contains $cat) { $scoreG++ }

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
    Select-Object -ExpandProperty Bestand |
    Out-File "$uitvoerMap\systeem.txt" -Encoding UTF8

$regels | Where-Object { $_.Classificatie -eq "Waarschijnlijk gebruikersbestand" } |
    Select-Object -ExpandProperty Bestand |
    Out-File "$uitvoerMap\gebruikers.txt" -Encoding UTF8

$regels | Where-Object { $_.Classificatie -eq "Onbeslist" } |
    Select-Object -ExpandProperty Bestand |
    Out-File "$uitvoerMap\onbekend.txt" -Encoding UTF8

$regels | Sort-Object Classificatie |
    ConvertTo-Html -Title "Bestandsclassificatie" -Property Bestand, Categorie, GrootteKB, Score, Classificatie |
    Out-File "$uitvoerMap\overzicht.html"

Write-Host "✅ Classificatie voltooid: $uitvoerMap"
