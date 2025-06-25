<#
.SYNOPSIS
    Classificeert individuele bestanden op basis van extensie, bestandsnaam en padstructuur.

.DESCRIPTION
    Doorzoekt een pad recursief en bepaalt voor elk bestand of het technisch (systeemgerelateerd) of gebruikersgericht is,
    op basis van bestandsextensies, verdachte keywords in bestandsnamen en bekende systeem-/gebruikersmapnamen in het pad.

    Er wordt een score toegekend aan elk bestand voor verdachte signalen (Verdacht: extensie + naam + pad) en gebruikerssignalen
    (Gebruiker: extensie + pad). Op basis hiervan wordt een classificatie toegekend.

    Output wordt opgeslagen in een unieke map "classificatie-[timestamp]", waarin CSV-bestanden worden aangemaakt per categorie
    (alleen als ze iets bevatten), plus een overzicht in HTML.

.PARAMETER Path
    Het pad naar de map die moet worden geanalyseerd.

.OUTPUT
    Map met CSV-bestanden zoals:

        classificatie-20250625T194500/
        ├─ gebruiker.csv
        ├─ systeem.csv
        ├─ onbeslist.csv
        └─ volledig-overzicht.html

    Elke CSV bevat kolommen als:

        Bestand,Technisch,Gebruiker,VerdachteNaam,VerdachtPad,BekendGebruikersPad,Score,Classificatie
        C:\data\setup.exe,1,0,1,1,0,V:3 / G:0,Waarschijnlijk systeembestand
        C:\data\boekhouding\jaar.pdf,0,1,0,0,1,V:0 / G:2,Waarschijnlijk gebruikersbestand
        C:\temp\misc\file.tmp,1,0,0,1,0,V:2 / G:0,Waarschijnlijk systeembestand

.EXAMPLE
    .\ClassificeerBestanden.ps1 -Path "C:\Backup"

    → genereert map met afzonderlijke CSV's + volledig HTML-overzicht
#>

param (
    [Parameter(Mandatory = $true)]
    [string]$Path
)

# === Configuratie ===
$systeemExts = @(".exe", ".dll", ".sys", ".inf", ".dat", ".log", ".tmp", ".bak", ".gadget", ".manifest", ".msi", ".ico")
$gebruikersExts = @(
    ".doc", ".docx", ".xls", ".xlsx", ".ppt", ".pptx", ".pdf", ".txt", ".odt", ".rtf",
    ".jpg", ".jpeg", ".png", ".gif", ".bmp", ".tiff", ".webp", ".mp3", ".wav", ".flac",
    ".m4a", ".aac", ".mp4", ".avi", ".mov", ".wmv", ".mkv", ".psd", ".indd", ".ai",
    ".ait", ".idml", ".inx", ".dbb", ".dbk", ".epub", ".mobi", ".azw3", ".cbr", ".cbz"
)
$verdachteNaamKeywords = @("setup", "autorun", "token", "config", "install", "background", "log", "temp", "patch", "uninstall", "driver", "license", "readme", "support", "windows")
$systeemMapKeywords = @("windows", "program files", "programdata", "drivers", "intel", "nvidia", "temp", "support", "dell", "system32", "setup", "installer", "hp", "epson", "msocache")
$gebruikersMapKeywords = @("documents", "downloads", "pictures", "photos", "music", "videos", "desktop", "scans", "boeken", "boekhouding", "financien", "administratie", "documenten", "afbeeldingen", "muziek", "video's", "bureaublad")

# === Padvalidering ===
$volledigPad = Resolve-Path $Path
if (-not (Test-Path $volledigPad)) {
    Write-Error "❌ Pad bestaat niet: $volledigPad"
    exit 1
}

# === Outputmap ===
$timestamp = (Get-Date).ToString("yyyyMMddTHHmmss")
$outputMap = Join-Path -Path $PSScriptRoot -ChildPath "classificatie-$timestamp"
New-Item -Path $outputMap -ItemType Directory -Force | Out-Null

# === Verwerking ===
$alleBestanden = Get-ChildItem -Path $volledigPad -Recurse -File -Force -ErrorAction SilentlyContinue
$resultaat = @()
foreach ($bestand in $alleBestanden) {
    $ext = $bestand.Extension.ToLower()
    $naam = $bestand.Name.ToLower()
    $pad = $bestand.FullName.ToLower()

    $technisch = [int]($systeemExts -contains $ext)
    $gebruiker = [int]($gebruikersExts -contains $ext)
    $verdachtNaam = [int]($verdachteNaamKeywords | Where-Object { $naam -like "*$_*" } | Measure-Object).Count
    $verdachtPad = [int]($systeemMapKeywords | Where-Object { $pad -like "*\$_\*" } | Measure-Object).Count
    $bekendGebruikersPad = [int]($gebruikersMapKeywords | Where-Object { $pad -like "*\$_\*" } | Measure-Object).Count

    $scoreVerdacht = $technisch + $verdachtNaam + $verdachtPad
    $scoreGebruiker = $gebruiker + $bekendGebruikersPad

    $classificatie = "Onbeslist"
    if ($scoreVerdacht -ge 2 -and $scoreGebruiker -lt 2) {
        $classificatie = "Waarschijnlijk systeembestand"
    } elseif ($scoreGebruiker -ge 2 -and $scoreVerdacht -lt 2) {
        $classificatie = "Waarschijnlijk gebruikersbestand"
    }

    $resultaat += [PSCustomObject]@{
        Bestand = $bestand.FullName
        Technisch = $technisch
        Gebruiker = $gebruiker
        VerdachteNaam = $verdachtNaam
        VerdachtPad = $verdachtPad
        BekendGebruikersPad = $bekendGebruikersPad
        Score = "V:$scoreVerdacht / G:$scoreGebruiker"
        Classificatie = $classificatie
    }
}

# === Opsplitsen en exporteren ===
$perClass = $resultaat | Group-Object Classificatie
foreach ($groep in $perClass) {
    if ($groep.Count -gt 0) {
        $naam = switch ($groep.Name) {
            "Waarschijnlijk systeembestand" { "systeem.csv" }
            "Waarschijnlijk gebruikersbestand" { "gebruiker.csv" }
            default { "onbeslist.csv" }
        }
        $pad = Join-Path $outputMap $naam
        $groep.Group | Export-Csv -Path $pad -NoTypeInformation -Encoding UTF8
    }
}

# === HTML overzicht ===
$htmlPad = Join-Path $outputMap "volledig-overzicht.html"
$resultaat | Sort-Object -Property Classificatie -Descending |
    ConvertTo-Html -Property Bestand, Technisch, Gebruiker, VerdachteNaam, VerdachtPad, BekendGebruikersPad, Score, Classificatie -Title "Bestandsclassificatie" |
    Out-File -FilePath $htmlPad -Encoding UTF8

Write-Host "✅ Classificatie voltooid: $outputMap"
