<#
.SYNOPSIS
    Classificeert individuele bestanden op basis van extensie, bestandsnaam en padstructuur in lijn met de verplaatsingslogica.

.DESCRIPTION
    Doorzoekt een pad recursief en bepaalt voor elk bestand de categorie (zoals gebruikt in BestandenVerplaatsen.ps1).
    Gebruikt dezelfde extensie-categorietoewijzing als dat script, maar weegt daarnaast ook verdachte extensies,
    bestandsnamen en padsegmenten mee voor een totale classificatie:

        - Waarschijnlijk gebruikersbestand
        - Waarschijnlijk systeembestand
        - Onbeslist

.OUTPUT
    CSV-bestanden in een classificatie-<timestamp> map, met:
      - gebruikers.csv
      - systeem.csv
      - onbekend.csv
      - overzicht.html

.OUTPUT VOORBEELD
    Bestand,Categorie,Score,Classificatie
    C:\data\setup.exe,Onbekend,V:2 / G:0,Waarschijnlijk systeembestand
    C:\data\boeken\jaar.pdf,Documenten,V:0 / G:2,Waarschijnlijk gebruikersbestand
    C:\misc\logfile.tmp,Onbekend,V:2 / G:0,Waarschijnlijk systeembestand

#>

param (
    [Parameter(Mandatory = $true)]
    [string]$Path
)

# --- Categorie extensies ---
$categorieMap = @{
    "Afbeeldingen" = @(".jpg", ".jpeg", ".png", ".gif", ".bmp", ".tiff", ".webp")
    "Documenten"   = @(".doc", ".docx", ".pdf", ".txt", ".odt", ".rtf", ".xls", ".xlsx", ".ppt", ".pptx")
    "Muziek"       = @(".mp3", ".wav", ".flac", ".m4a", ".aac")
    "Video's"      = @(".mp4", ".avi", ".mov", ".wmv", ".mkv")
    "Adobe"        = @(".psd", ".indd", ".ai", ".ait", ".idml", ".inx")
    "Backups"      = @(".dbk", ".bak", ".zip", ".7z", ".rar", ".tar", ".gz", ".iso", ".dbb")
    "Boeken"       = @(".epub", ".mobi", ".azw3", ".cbr", ".cbz")
}

$systeemExts = @(".dll", ".sys", ".exe", ".msi", ".drv", ".ini", ".reg", ".bat", ".cmd", ".vbs", ".ps1", ".log", ".tmp", ".inf", ".dat", ".gadget", ".manifest", ".ico", ".ocx", ".cpl", ".scr", ".pif", ".com", ".hlp", ".chm", ".cab", ".msp", ".msu", ".appx", ".msix", ".lnk", ".url", ".theme", ".deskthemepack", ".library-ms", ".search-ms", ".scf", ".job", ".pol", ".adm", ".admx", ".wim", ".esd", ".etl", ".evtx", ".dmp", ".mdmp", ".pdb", ".mui", ".nls")

function Get-Categorie {
    param ($ext)
    foreach ($key in $categorieMap.Keys) {
        if ($categorieMap[$key] -contains $ext.ToLower()) {
            return $key
        }
    }
    return "Onbekend"
}

# --- Scoringskeywords ---
$verdachteNaamKeywords = @("setup", "autorun", "token", "config", "install", "background", "log", "temp", "patch", "uninstall", "driver", "license", "readme", "support", "windows")
$systeemMapKeywords = @("windows", "program files", "programdata", "drivers", "intel", "nvidia", "temp", "support", "dell", "system32", "setup", "installer", "hp", "epson", "msocache")
$gebruikersMapKeywords = @("documents", "downloads", "pictures", "photos", "music", "videos", "desktop", "scans", "boeken", "boekhouding", "financien", "administratie", "documenten", "afbeeldingen", "muziek", "video's", "bureaublad")

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

# --- Bestanden ---
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
    $scoreV += ($systeemMapKeywords | Where-Object { $pad -like "*\$_\*" }).Count
    $scoreG += ($gebruikersMapKeywords | Where-Object { $pad -like "*\$_\*" }).Count

    $classificatie = "Onbeslist"
    if ($scoreV -ge 2 -and $scoreG -lt 2) {
        $classificatie = "Waarschijnlijk systeembestand"
    } elseif ($scoreG -ge 2 -and $scoreV -lt 2) {
        $classificatie = "Waarschijnlijk gebruikersbestand"
    }

    $regels += [PSCustomObject]@{
        Bestand = $bestand.FullName
        Categorie = $cat
        Score = "V:$scoreV / G:$scoreG"
        Classificatie = $classificatie
    }
}

# --- Opsplitsing ---
$regels | Where-Object { $_.Classificatie -eq "Waarschijnlijk systeembestand" } |
    Export-Csv "$outputMap\systeem.csv" -NoTypeInformation -Encoding UTF8

$regels | Where-Object { $_.Classificatie -eq "Waarschijnlijk gebruikersbestand" } |
    Export-Csv "$outputMap\gebruikers.csv" -NoTypeInformation -Encoding UTF8

$regels | Where-Object { $_.Classificatie -eq "Onbeslist" } |
    Export-Csv "$outputMap\onbekend.csv" -NoTypeInformation -Encoding UTF8

# --- HTML overzicht ---
$regels | Sort-Object Classificatie | ConvertTo-Html -Title "Bestandsclassificatie" -Property Bestand, Categorie, Score, Classificatie |
    Out-File "$outputMap\overzicht.html"

Write-Host "✅ Classificatie voltooid: $outputMap"
