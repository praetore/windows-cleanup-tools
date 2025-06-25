<#
.SYNOPSIS
    Zet bestanden terug naar hun originele locatie op basis van een CSV-logbestand.

.DESCRIPTION
    Leest een CSV-bestand in met kolommen 'Origineel', 'Bestemming' en 'Actie' (zoals gegenereerd door een verplaats/kopieerscript),
    en verplaatst elk bestand terug naar zijn originele locatie, mits het nog op de log-geregistreerde bestemming aanwezig is.

.PARAMETER File
    Pad naar de CSV-logfile die gebruikt moet worden voor het terugplaatsen.

#>

param (
    [Parameter(Mandatory = $true)]
    [string]$File
)

if (-not (Test-Path $File)) {
    Write-Error "❌ Bestand bestaat niet: $File"
    exit 1
}

# Lees CSV
$entries = Import-Csv -Path $File

foreach ($entry in $entries) {
    $bron = $entry.Bestemming
    $doel = $entry.Origineel

    if (-not (Test-Path $bron)) {
        Write-Warning "⚠️  Bestemming ontbreekt (overslagen): $bron"
        continue
    }

    # Zorg dat doelmap bestaat
    $doelMap = Split-Path $doel
    if (-not (Test-Path $doelMap)) {
        try {
            New-Item -Path $doelMap -ItemType Directory -Force | Out-Null
        } catch {
            Write-Warning "❌ Kon map niet aanmaken: $doelMap - $_"
            continue
        }
    }

    try {
        Move-Item -Path $bron -Destination $doel -Force
        Write-Host "⏪ Teruggezet: $($entry.Bestemming) → $($entry.Origineel)"
    } catch {
        Write-Warning "⚠️  Fout bij terugzetten: $($entry.Bestemming) - $_"
    }
}
