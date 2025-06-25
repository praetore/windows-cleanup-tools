<#
.SYNOPSIS
    Verwijdert recursief lege mappen en opschoonbestanden zoals .DS_Store, Thumbs.db en __MACOSX.

.DESCRIPTION
    Doorzoekt alle mappen vanaf het opgegeven pad en verwijdert:
    - Ongewenste restanten zoals systeemcachebestanden en overbodige Mac/Windows artifacts.
    - Lege mappen (na opschoning).

.PARAMETER Path
    Hoofdpad waar de opschoning moet starten.
#>

param (
    [Parameter(Mandatory = $true)]
    [string]$Path
)

# Ongewenste bestandspatronen
$ongewensteBestandsnamen = @(
    ".ds_store", "thumbs.db", "desktop.ini", "icon\r", "autorun.inf"
)
$ongewensteMapnamen = @(
    "__macosx", "$recycle.bin", "system volume information"
)

# Normaliseer pad
$rootMap = Convert-Path -LiteralPath $Path
$verwijderd = $true
$bezochteMappen = @{}

while ($verwijderd) {
    $verwijderd = $false

    Get-ChildItem -Path $rootMap -Directory -Recurse -Force |
    Sort-Object FullName -Descending |
    ForEach-Object {
        $pad = $_.FullName.ToLower()

        if ($bezochteMappen.ContainsKey($pad)) {
            return
        }
        $bezochteMappen[$pad] = $true

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
            }
        } catch {
            Write-Warning "❌ Kon map niet verwijderen: $($_.FullName) - $_"
        }
    }
}
