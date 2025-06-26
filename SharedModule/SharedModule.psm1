# SharedModule.psm1
# Contains shared functions used across multiple scripts

# Function to load configuration from JSON file
function Get-Configuration {
    param (
        [string]$ConfigPath = "config.json"
    )

    # Normalize config path
    $configPath = if ([System.IO.Path]::IsPathRooted($ConfigPath)) {
        $ConfigPath
    } else {
        Join-Path $PSScriptRoot $ConfigPath
    }

    if (Test-Path $configPath) {
        try {
            $config = Get-Content -Path $configPath -Raw | ConvertFrom-Json

            # Convert JSON arrays to PowerShell hashtable for user extensions
            $categorieMap = @{}
            foreach ($property in $config.user.extensions.PSObject.Properties) {
                $categorieMap[$property.Name] = $property.Value
            }

            # Flatten system extensions from all categories
            $systeemExts = @()
            foreach ($property in $config.system.extensions.PSObject.Properties) {
                $systeemExts += $property.Value
            }

            # Create a result object with all the configuration data
            $result = [PSCustomObject]@{
                Config = $config
                CategorieMap = $categorieMap
                SysteemExts = $systeemExts
                VerdachteNaamKeywords = $config.system.files
                SysteemMapKeywords = $config.system.directories
                GebruikersMapKeywords = $config.user.directories
                OngewensteBestandsnamen = $config.ignore.extensions
                OngewensteMapnamen = $config.ignore.directories
            }

            Write-Host "✅ Configuratie geladen uit $configPath"
            return $result
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
}

# Function to determine the category of a file based on its extension
function Get-Categorie {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Extension,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$CategorieMap,
        
        [Parameter(Mandatory = $false)]
        [PSCustomObject]$Config
    )

    # Remove leading dot if present
    $ext = $Extension.ToLower()
    if ($ext.StartsWith('.')) {
        $ext = $ext.Substring(1)
    } else {
        $ext = $ext
    }

    # Check user extensions first
    foreach ($key in $CategorieMap.Keys) {
        if ($CategorieMap[$key] -contains $ext) {
            return $key
        }
    }

    # Check system extensions if Config is provided
    if ($Config) {
        foreach ($key in $Config.system.extensions.PSObject.Properties.Name) {
            if ($Config.system.extensions.$key -contains $ext) {
                return $key
            }
        }
    }

    return "Overig"
}

# Function to normalize a path
function Get-NormalizedPath {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path,
        
        [switch]$CreateIfNotExists
    )

    $normalizedPath = Resolve-Path -Path $Path -ErrorAction SilentlyContinue
    
    if (-not $normalizedPath) {
        $normalizedPath = Join-Path -Path (Get-Location) -ChildPath $Path
        
        if ($CreateIfNotExists -and -not (Test-Path $normalizedPath)) {
            New-Item -Path $normalizedPath -ItemType Directory -Force | Out-Null
        }
    }
    
    return if ($normalizedPath -is [string]) { $normalizedPath } else { $normalizedPath.Path }
}

# Export functions
Export-ModuleMember -Function Get-Configuration, Get-Categorie, Get-NormalizedPath