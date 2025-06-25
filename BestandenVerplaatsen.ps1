<#
.SYNOPSIS
    Verplaatst of kopieert bestanden naar een gestructureerde doelmap op basis van bestandscategorieën, vanaf een opgegeven pad of een CSV-bestand.

.DESCRIPTION
    Doorzoekt recursief een map (-Path) of leest een CSV (-CsvInput) met bestandsnamen. Op basis van extensie bepaalt het de categorie
    (zoals Afbeeldingen, Documenten, Backups, Boeken, Adobe) en verplaatst of kopieert het bestand naar een doelmap (-Out), gestructureerd per categorie/submap.
    Het pad vóór en na verwerking wordt gelogd in een CSV-bestand.

.PARAMETER Path
    Bronmap die moet worden doorzocht (optioneel als -CsvInput is opgegeven).

.PARAMETER CsvInput
    Pad naar een CSV-bestand met een kolom 'Bestand' waarin absolute paden staan van bestanden die verwerkt moeten worden.

.PARAMETER Out
    Doelmap waarin bestanden geplaatst worden.

.PARAMETER Copy
    Voeg deze switch toe als je bestanden wilt kopiëren in plaats van verplaatsen.

.PARAMETER File
    Optioneel pad naar een CSV-logbestand. Indien niet opgegeven, wordt automatisch move-[timestamp].csv aangemaakt.

.EXAMPLE
    .\VerwerkBestanden.ps1 -Path "C:\Backup" -Out "C:\Resultaat"

    .\VerwerkBestanden.ps1 -CsvInput "systeembestanden.csv" -Out "C:\Doel" -Copy
#>

param (
    [string]$Path,
    [string]$CsvInput,

    [Parameter(Mandatory = $true)]
    [string]$Out,

    [switch]$Copy,

    [string]$File
)

if (-not $Path -and -not $CsvInput) {
    Write-Error "❌ Geef óf -Path óf -CsvInput op."
    exit 1
}

# Extensie-categorie mapping
$categorieMap = @{
    "Afbeeldingen" = @(".jpg", ".jpeg", ".png", ".gif", ".bmp", ".tiff", ".webp")
    "Documenten"   = @(".doc", ".docx", ".pdf", ".txt", ".odt", ".rtf", ".xls", ".xlsx", ".ppt", ".pptx")
    "Muziek"       = @(".mp3", ".wav", ".flac", ".m4a", ".aac")
    "Video's"      = @(".mp4", ".avi", ".mov", ".wmv", ".mkv")
    "Adobe"        = @(".psd", ".indd", ".ai", ".ait", ".idml", ".inx")
    "Backups"      = @(".dbk", ".bak", ".zip", ".7z", ".rar", ".tar", ".gz", ".iso", ".dbb")
    "Boeken"       = @(".epub", ".mobi", ".azw3", ".cbr", ".cbz")
}

function Get-Categorie {
    param($ext)
    foreach ($key in $categorieMap.Keys) {
        if ($categorieMap[$key] -contains $ext.ToLower()) {
            return $key
        }
    }
    return "Overig"
}

# Outputmap normaliseren
$doelRoot = Resolve-Path -Path $Out -ErrorAction SilentlyContinue
if (-not $doelRoot) {
    $doelRoot = Join-Path -Path (Get-Location) -ChildPath $Out
    New-Item -Path $doelRoot -ItemType Directory -Force | Out-Null
}
$doelRoot = $doelRoot.Path

# Output CSV instellen
if ($File) {
    if (Test-Path $File) {
        Write-Error "❌ Outputbestand bestaat al: $File"
        exit
    }
    $csvPath = $File
} else {
    $base = Join-Path $PSScriptRoot ("move-{0:yyyyMMdd-HHmmss}" -f (Get-Date))
    $i = 0
    do {
        $csvPath = if ($i -eq 0) { "$base.csv" } else { "$base-$i.csv" }
        $i++
    } while (Test-Path $csvPath)
}

# Verzamel bestanden
$bestanden = @()
if ($Path) {
    $bronMap = Convert-Path -LiteralPath $Path
    $bestanden = Get-ChildItem -Path $bronMap -Recurse -File
} elseif ($CsvInput) {
    if (-not (Test-Path $CsvInput)) {
        Write-Error "❌ CSV-bestand niet gevonden: $CsvInput"
        exit 1
    }
    $bestanden = Import-Csv -Path $CsvInput | Where-Object { Test-Path $_.Bestand } | ForEach-Object {
        Get-Item $_.Bestand
    }
}

$log = @()

foreach ($bestand in $bestanden) {
    $ext = $bestand.Extension
    $categorie = Get-Categorie $ext

    $bovenMap = Split-Path $bestand.DirectoryName -Leaf
    $subfolder = if ($bovenMap -ieq "Desktop") { "" } else { $bovenMap }

    $doelBasis = Join-Path $doelRoot $categorie
    $definitieveDoelMap = if ($subfolder) { Join-Path $doelBasis $subfolder } else { $doelBasis }

    if (-not (Test-Path $definitieveDoelMap)) {
        New-Item -Path $definitieveDoelMap -ItemType Directory -Force | Out-Null
    }

    $doelBestand = Join-Path $definitieveDoelMap $bestand.Name

    try {
        if ($Copy) {
            Copy-Item -Path $bestand.FullName -Destination $doelBestand -Force
        } else {
            Move-Item -Path $bestand.FullName -Destination $doelBestand -Force
        }

        $log += [PSCustomObject]@{
            Origineel   = $bestand.FullName
            Bestemming = $doelBestand
            Actie      = if ($Copy) { "Gekopieerd" } else { "Verplaatst" }
        }

        Write-Host "$($log[-1].Actie): $($bestand.Name) → $categorie\$subfolder"
    } catch {
        Write-Warning "⚠️  Kon niet verwerken: $($bestand.FullName) - $_"
    }
}

# Schrijf log
$log | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
Write-Host "`n✅ Log opgeslagen in: $csvPath"
