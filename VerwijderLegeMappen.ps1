<#
.SYNOPSIS
    Verwijdert recursief lege mappen en opschoonbestanden zoals .DS_Store, Thumbs.db en __MACOSX.

.DESCRIPTION
    Doorzoekt alle mappen vanaf het opgegeven pad en verwijdert:
    - Ongewenste restanten zoals systeemcachebestanden en overbodige Mac/Windows artifacts.
    - Lege mappen (na opschoning).

.PARAMETER Path
    Hoofdpad waar de opschoning moet starten.

.PARAMETER Config
    Optioneel pad naar een JSON-configuratiebestand. Indien niet opgegeven, wordt "config.json" in dezelfde map als het script gebruikt.
    Het configuratiebestand moet een "ignore" sectie bevatten met "extensions" en "directories" arrays.
    Let op: "$recycle.bin" wordt altijd toegevoegd aan de lijst met ongewenste mappen, ongeacht de configuratie.

.EXAMPLE
    .\VerwijderLegeMappen.ps1 -Path "C:\Data\OpTeSchonen"

    .\VerwijderLegeMappen.ps1 -Path "C:\Data\OpTeSchonen" -Config "mijn-config.json"
#>

param (
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [string]$Config = "config.json"
)

# Import shared module
$modulePath = Join-Path $PSScriptRoot "SharedModule"
Import-Module $modulePath -Force

# Laad configuratie uit JSON bestand
$configData = Get-Configuration -ConfigPath $Config
$config = $configData.Config
$ongewensteBestandsnamen = $configData.OngewensteBestandsnamen
$ongewensteMapnamen = $configData.OngewensteMapnamen

# Voeg $recycle.bin toe aan de lijst met ongewenste mappen
$ongewensteMapnamen += "$recycle.bin"

# Normaliseer pad
$rootMap = Get-NormalizedPath -Path $Path
$verwijderd = $true
$verwijderPogingMappen = @{}

while ($verwijderd) {
    $verwijderd = $false

    Get-ChildItem -Path $rootMap -Directory -Recurse -Force |
    Sort-Object FullName -Descending |
    ForEach-Object {
        $pad = $_.FullName.ToLower()

        if ($verwijderPogingMappen.ContainsKey($pad)) {
            return
        }

        try {
            # Verwijder ongewenste bestanden in deze map
            Get-ChildItem -Path $_.FullName -File -Force -ErrorAction SilentlyContinue |
            Where-Object {
                $ongewensteBestandsnamen -contains $_.Name.ToLower()
            } | ForEach-Object {
                try {
                    Remove-Item -Path $_.FullName -Force -ErrorAction Stop
                    Write-Host "🗑️  Verwijderd bestand: $($_.FullName)"
                } catch {
                    Write-Warning "❌ Kon bestand niet verwijderen: $($_.FullName) - $_"
                }
            }

            # Verwijder de map zelf als hij leeg is of een bekende ongewenste naam heeft
            $isOngewensteMap = $ongewensteMapnamen | Where-Object { $pad -like "*\$_" }

            $inhoud = Get-ChildItem -Path $_.FullName -Force -ErrorAction SilentlyContinue |
                      Where-Object { -not $_.PSIsContainer -and -not $_.Attributes.ToString().Contains("System") }

            if (-not $inhoud -or $isOngewensteMap) {
                Remove-Item -Path $_.FullName -Force -Recurse -ErrorAction Stop
                Write-Host "🗑️  Verwijderd map: $($_.FullName)"
                $verwijderd = $true
                $verwijderPogingMappen[$pad] = $true
            }
        } catch {
            Write-Warning "❌ Kon map niet verwijderen: $($_.FullName) - $_"
            $verwijderPogingMappen[$pad] = $true
        }
    }
}
