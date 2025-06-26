<#
.SYNOPSIS
    Verplaatst of kopieert bestanden naar een gestructureerde doelmap op basis van bestandscategorieën, vanaf een opgegeven pad of een bestand met bestandspaden.

.DESCRIPTION
    Doorzoekt recursief een map (-Path) of leest een bestand (-File) met bestandsnamen. Op basis van extensie bepaalt het de categorie
    (zoals Afbeeldingen, Documenten, Backups, Boeken, Adobe) en verplaatst of kopieert het bestand naar een doelmap (-Out), gestructureerd per categorie/submap.
    Het pad vóór en na verwerking wordt gelogd in een CSV-bestand.

.PARAMETER Path
    Bronmap die moet worden doorzocht (optioneel als -File is opgegeven).

.PARAMETER File
    Pad naar een bestand met te verwerken bestanden. Dit kan een CSV-bestand zijn met een kolom 'Bestand' of een tekstbestand met één bestandspad per regel.

.PARAMETER Out
    Doelmap waarin bestanden geplaatst worden.

.PARAMETER Copy
    Voeg deze switch toe als je bestanden wilt kopiëren in plaats van verplaatsen.

.PARAMETER LogFile
    Optioneel pad naar een CSV-logbestand. Indien niet opgegeven, wordt automatisch move-[timestamp].csv aangemaakt.

.PARAMETER Config
    Optioneel pad naar een JSON-configuratiebestand. Indien niet opgegeven, wordt "config.json" in dezelfde map als het script gebruikt.

.EXAMPLE
    .\BestandenVerplaatsen.ps1 -Path "C:\Backup" -Out "C:\Resultaat"
    # Verplaatst alle bestanden uit de map C:\Backup naar C:\Resultaat, georganiseerd per categorie

    .\BestandenVerplaatsen.ps1 -File "systeembestanden.csv" -Out "C:\Doel" -Copy
    # Kopieert bestanden uit een CSV-bestand met een 'Bestand' kolom naar C:\Doel

    .\BestandenVerplaatsen.ps1 -File "te_verplaatsen.txt" -Out "C:\Doel"
    # Verplaatst bestanden uit een tekstbestand met één bestandspad per regel naar C:\Doel

    .\BestandenVerplaatsen.ps1 -Path "C:\Backup" -Out "C:\Resultaat" -Config "mijn-config.json"
    # Gebruikt een aangepast configuratiebestand
#>

param (
    [string]$Path,
    [string]$File,

    [Parameter(Mandatory = $true)]
    [string]$Out,

    [switch]$Copy,

    [string]$LogFile,

    [string]$Config = "config.json"
)

if (-not $Path -and -not $File) {
    Write-Error "❌ Geef óf -Path óf -File op."
    exit 1
}

# Laad configuratie uit JSON bestand
$configPath = if ([System.IO.Path]::IsPathRooted($Config)) {
    $Config
} else {
    Join-Path $PSScriptRoot $Config
}
if (Test-Path $configPath) {
    try {
        $config = Get-Content -Path $configPath -Raw | ConvertFrom-Json

        # Converteer JSON arrays naar PowerShell hashtable
        $categorieMap = @{}
        foreach ($property in $config.user.extensions.PSObject.Properties) {
            $categorieMap[$property.Name] = $property.Value
        }

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
if ($LogFile) {
    if (Test-Path $LogFile) {
        Write-Error "❌ Outputbestand bestaat al: $LogFile"
        exit
    }
    $csvPath = $LogFile
} else {
    $base = Join-Path $PSScriptRoot ("verplaatsen-{0:yyyyMMdd-HHmmss}" -f (Get-Date))
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
} elseif ($File) {
    if (-not (Test-Path $File)) {
        Write-Error "❌ Bestand niet gevonden: $File"
        exit 1
    }

    # Bepaal of het een CSV of tekstbestand is
    $fileContent = Get-Content -Path $File -TotalCount 1 -ErrorAction Stop
    $isCSV = $fileContent -match ","

    if ($isCSV) {
        # Verwerk als CSV
        $csv = Import-Csv -Path $File -ErrorAction Stop
        if (-not $csv[0].PSObject.Properties["Bestand"]) {
            Write-Error "❌ CSV mist kolom 'Bestand'"
            exit 1
        }
        $bestanden = $csv | Where-Object { Test-Path $_.Bestand } | ForEach-Object {
            Get-Item $_.Bestand
        }
    } else {
        # Verwerk als tekstbestand met één pad per regel
        $bestandsPaden = Get-Content -Path $File -ErrorAction Stop | Where-Object { $_ -and (-not $_.StartsWith("#")) }
        $bestanden = $bestandsPaden | Where-Object { Test-Path $_ } | ForEach-Object {
            Get-Item $_
        }
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
