<#
.SYNOPSIS
    Classificeert individuele bestanden o.b.v. extensie, naam, pad, afbeeldingsresolutie en bestandsgrootte.

.DESCRIPTION
    Doorzoekt een pad recursief en bepaalt per bestand de categorie, scores en classificatie.
    Kleine afbeeldingen (≤ 256x256 px) óf een afbeeldingsbestand ≤ 50KB krijgen extra verdacht-score.

.OUTPUT
    CSV-bestanden in classificatie-<timestamp> map + overzicht.html

#>

param (
    [Parameter(Mandatory = $true)]
    [string]$Path
)

Add-Type -AssemblyName System.Drawing

$categorieMap = @{
    "Afbeeldingen" = @(".jpg", ".jpeg", ".png", ".gif", ".bmp", ".tiff", ".webp")
    "Documenten"   = @(".doc", ".docx", ".pdf", ".txt", ".odt", ".rtf", ".xls", ".xlsx", ".ppt", ".pptx")
    "Muziek"       = @(".mp3", ".wav", ".flac", ".m4a", ".aac")
    "Video's"      = @(".mp4", ".avi", ".mov", ".wmv", ".mkv")
    "Adobe"        = @(".psd", ".indd", ".ai", ".ait", ".idml", ".inx")
    "Backups"      = @(".dbk", ".bak", ".zip", ".7z", ".rar", ".tar", ".gz", ".iso", ".dbb")
    "Boeken"       = @(".epub", ".mobi", ".azw3", ".cbr", ".cbz")
}

$systeemExts = @(".dll", ".sys", ".exe", ".msi", ".drv", ".ini", ".reg", ".bat", ".cmd", ".vbs", ".ps1", ".log", ".tmp", ".inf", ".dat", ".gadget", ".manifest", ".ico")

function Get-Categorie($ext) {
    foreach ($key in $categorieMap.Keys) {
        if ($categorieMap[$key] -contains $ext.ToLower()) {
            return $key
        }
    }
    return "Onbekend"
}

$verdachteNaamKeywords = @("setup", "autorun", "token", "config", "install", "background", "log", "temp", "patch", "uninstall", "driver", "license", "readme", "support", "windows")
$systeemMapKeywords = @("windows", "program files", "programdata", "drivers", "system32", "intel", "nvidia")
$gebruikersMapKeywords = @("documents", "downloads", "pictures", "photos", "music", "videos", "desktop", "boeken", "documenten", "afbeeldingen")

$volledigPad = Resolve-Path $Path
if (-not (Test-Path $volledigPad)) {
    Write-Error "❌ Pad bestaat niet: $volledigPad"
    exit 1
}

$ts = Get-Date -Format "yyyyMMdd-HHmmss"
$outputMap = Join-Path $PSScriptRoot "classificatie-$ts"
New-Item -Path $outputMap -ItemType Directory -Force | Out-Null

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

    # Kleine afbeelding check
    if ($cat -eq "Afbeeldingen") {
        try {
            $img = [System.Drawing.Image]::FromFile($bestand.FullName)
            if ($img.Width -le 256 -and $img.Height -le 256) {
                $scoreV++
            }
            if ($bestand.Length -lt 51200) {
                $scoreV++
            }
            $img.Dispose()
        } catch {
            # Niet leesbaar als afbeelding, negeer
        }
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
