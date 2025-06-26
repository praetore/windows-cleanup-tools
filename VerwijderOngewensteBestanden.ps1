<#
.SYNOPSIS
    Verwijdert bestanden uit een lijst (.txt of .csv).

.DESCRIPTION
    Leest een lijst met bestandsnamen uit een tekstbestand (.txt) of CSV-bestand (.csv). 
    Bij een CSV-bestand wordt de kolom 'Bestand' verwacht. Elk pad dat bestaat, wordt verwijderd.

.PARAMETER File
    Het pad naar het invoerbestand (.txt of .csv). 
    - .txt: verwacht één pad per regel.
    - .csv: verwacht een kolom 'Bestand' met absolute paden.

.EXAMPLE
    .\VerwijderBestanden.ps1 -File "ongewenste_bestanden.txt"

    .\VerwijderBestanden.ps1 -File "systeem.csv"
#>

param (
    [Parameter(Mandatory = $true)]
    [string]$File
)

if (-not (Test-Path $File)) {
    Write-Error "❌ Bestand niet gevonden: $File"
    exit 1
}

$ext = [System.IO.Path]::GetExtension($File).ToLower()
$bestanden = @()

switch ($ext) {
    ".txt" {
        $bestanden = Get-Content -Path $File -ErrorAction Stop
    }
    ".csv" {
        try {
            $csv = Import-Csv -Path $File -ErrorAction Stop
            if (-not $csv[0].PSObject.Properties["Bestand"]) {
                Write-Error "❌ CSV mist kolom 'Bestand'"
                exit 1
            }
            $bestanden = $csv | ForEach-Object { $_.Bestand }
        } catch {
            Write-Error "❌ Fout bij inlezen van CSV: $_"
            exit 1
        }
    }
    default {
        Write-Error "❌ Alleen .txt en .csv worden ondersteund"
        exit 1
    }
}

foreach ($pad in $bestanden) {
    if (Test-Path -Path $pad) {
        try {
            Remove-Item -Path $pad -Force -ErrorAction Stop
            Write-Host "✅ Verwijderd: $pad"
        } catch {
            Write-Warning "❌ Kon niet verwijderen: $pad - $_"
        }
    } else {
        Write-Host "⚠️ Bestaat niet (overgeslagen): $pad"
    }
}
