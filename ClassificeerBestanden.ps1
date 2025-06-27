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

.PARAMETER Llm
    Optionele switch om LLM (Language Model) te gebruiken voor classificatie van onbesliste bestanden.
    Indien opgegeven, worden bestanden die niet duidelijk als systeem- of gebruikersbestand geclassificeerd kunnen worden,
    alsnog geclassificeerd met behulp van een lokaal LLM-model (Ollama of LMStudio).

.PARAMETER BatchSize
    Optionele parameter om de grootte van de batches voor LLM-verwerking in te stellen. Standaard is 100.
    Alleen van toepassing als -Llm is opgegeven.

.EXAMPLE
    .\ClassificeerBestanden.ps1 -Path "C:\Data\TeClassificeren"

    .\ClassificeerBestanden.ps1 -Path "C:\Data\TeClassificeren" -Config "mijn-config.json"

    .\ClassificeerBestanden.ps1 -Path "C:\Data\TeClassificeren" -Llm

    .\ClassificeerBestanden.ps1 -Path "C:\Data\TeClassificeren" -Llm -BatchSize 50
#>

param (
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [string]$Config = "config.json",

    [switch]$Llm,

    [int]$BatchSize = 100
)

# Import shared module
$modulePath = Join-Path $PSScriptRoot "SharedModule"
Import-Module $modulePath -Force

# Import LlmModule if -Llm is specified
if ($Llm) {
    $llmModulePath = Join-Path $PSScriptRoot "LlmModule"
    Import-Module $llmModulePath -Force
    Write-Host "🤖 LLM-module geladen voor classificatie van onbesliste bestanden"
}

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
    $cat = Get-Categorie -Extension $ext -CategorieMap $categorieMap -Config $config -FileInfo $bestand

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

            # Check if image meets icon criteria and increment score
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

# --- LLM classificatie voor onbesliste bestanden ---
if ($Llm) {
    $onbeslisteRegels = $regels | Where-Object { $_.Classificatie -eq "Onbeslist" }

    if ($onbeslisteRegels.Count -gt 0) {
        Write-Host "🤖 Classificeren van $($onbeslisteRegels.Count) onbesliste bestanden met LLM in batches van $BatchSize..."

        # Bereid bestanden voor voor LLM verwerking
        $llmBestanden = $onbeslisteRegels | ForEach-Object {
            [PSCustomObject]@{
                FilePath = $_.Bestand
                Category = $_.Categorie
                Extension = [System.IO.Path]::GetExtension($_.Bestand).TrimStart('.')
            }
        }

        # Roep LLM aan voor classificatie via de LlmModule
        $batchResultaten = Get-LlmFileClassification -Files $llmBestanden -BatchSize $BatchSize

        # Verwerk de resultaten en update de classificaties
        foreach ($regel in $onbeslisteRegels) {
            $bestandsPad = $regel.Bestand
            $bestandsNaam = Split-Path $bestandsPad -Leaf

            if ($batchResultaten.ContainsKey($bestandsPad)) {
                $classificatie = $batchResultaten[$bestandsPad]

                # Update de classificatie
                if ($classificatie -match "systeem|system") {
                    $regel.Classificatie = "Waarschijnlijk systeembestand"
                    $regel.Score = "$($regel.Score) + LLM"
                    Write-Host "📊 LLM classificatie: $bestandsNaam -> Waarschijnlijk systeembestand"
                } 
                elseif ($classificatie -match "gebruiker|user") {
                    $regel.Classificatie = "Waarschijnlijk gebruikersbestand"
                    $regel.Score = "$($regel.Score) + LLM"
                    Write-Host "📊 LLM classificatie: $bestandsNaam -> Waarschijnlijk gebruikersbestand"
                }
            }
        }

        Write-Host "✅ LLM classificatie voltooid"
    }
    else {
        Write-Host "ℹ️ Geen onbesliste bestanden om te classificeren met LLM"
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
