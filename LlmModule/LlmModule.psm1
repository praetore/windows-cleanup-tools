# LlmModule.psm1
# Contains functions for interacting with local LLM models (LMStudio or Ollama)

# Generic function to process files in batches with LLM
function Invoke-LlmBatchProcessing {
    param (
        [Parameter(Mandatory = $true)]
        [array]$Files,

        [Parameter(Mandatory = $false)]
        [int]$BatchSize = 10,

        [Parameter(Mandatory = $true)]
        [string]$PromptTemplate,

        [Parameter(Mandatory = $true)]
        [string]$SystemPrompt,

        [Parameter(Mandatory = $false)]
        [string]$DefaultValue = "",

        [Parameter(Mandatory = $false)]
        [scriptblock]$ProcessResponse = { 
            param($line, $fileName) 
            if ($line -match "(?i)$([regex]::Escape($fileName)).*?:\s*(.+)") {
                return $matches[1].Trim()
            }
            return $null
        },

        [Parameter(Mandatory = $false)]
        [scriptblock]$GetFallbackValue = {
            param($fileInfo)
            $parentDir = Split-Path (Split-Path $fileInfo.FilePath -Parent) -Leaf
            return if ($parentDir -ieq "Desktop") { "" } else { $parentDir }
        }
    )

    # Group files by category and extension for more efficient batching
    $groupedFiles = $Files | Group-Object -Property { "$($_.Category)|$($_.Extension)" }
    $results = @{}

    foreach ($group in $groupedFiles) {
        $categoryExt = $group.Name.Split('|')
        $category = $categoryExt[0]
        $extension = $categoryExt[1]

        Write-Host "`n📊 Verwerken van batch voor categorie: $category, extensie: $extension ($($group.Count) bestanden)"

        # Process files in batches
        $batch = @()
        $batchCount = 0

        foreach ($fileInfo in $group.Group) {
            $batch += $fileInfo
            $batchCount++

            # Process batch when it reaches the batch size or at the end of the group
            if ($batchCount -ge $BatchSize -or $fileInfo -eq $group.Group[-1]) {
                Write-Host "🔄 Verwerken van batch met $($batch.Count) bestanden..."

                # Create a batch prompt for the LLM
                $fileDescriptions = $batch | ForEach-Object {
                    $fileName = Split-Path $_.FilePath -Leaf
                    $parentDir = Split-Path (Split-Path $_.FilePath -Parent) -Leaf
                    $lastWriteTime = (Get-Item $_.FilePath).LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
                    "- Bestandsnaam: $fileName, Huidige map: $parentDir, Wijzigingsdatum: $lastWriteTime"
                } | Out-String

                # Replace placeholders in the prompt template
                $batchPrompt = $PromptTemplate -replace '\$extension', $extension -replace '\$category', $category -replace '\$fileDescriptions', $fileDescriptions

                # Try Ollama first
                $ollamaUrl = "http://localhost:11434/api/generate"
                $ollamaBody = @{
                    model = "llama3"
                    prompt = $batchPrompt
                    stream = $false
                } | ConvertTo-Json

                $batchSuggestions = $null

                try {
                    $response = Invoke-RestMethod -Uri $ollamaUrl -Method Post -Body $ollamaBody -ContentType "application/json" -TimeoutSec 20
                    if ($response.response) {
                        $batchSuggestions = $response.response.Trim()
                        Write-Host "🤖 Ollama LLM batch resultaten ontvangen"
                    }
                }
                catch {
                    Write-Host "⚠️ Ollama niet beschikbaar voor batch verwerking, probeer LMStudio..."
                }

                # If Ollama fails, try LMStudio
                if (-not $batchSuggestions) {
                    $lmStudioUrl = "http://localhost:1234/v1/chat/completions"
                    $lmStudioBody = @{
                        messages = @(
                            @{
                                role = "system"
                                content = $SystemPrompt
                            },
                            @{
                                role = "user"
                                content = $batchPrompt
                            }
                        )
                        model = "local-model"
                        temperature = 0.7
                        max_tokens = 500
                    } | ConvertTo-Json

                    try {
                        $response = Invoke-RestMethod -Uri $lmStudioUrl -Method Post -Body $lmStudioBody -ContentType "application/json" -TimeoutSec 20
                        if ($response.choices -and $response.choices.Count -gt 0) {
                            $batchSuggestions = $response.choices[0].message.content.Trim()
                            Write-Host "🤖 LMStudio LLM batch resultaten ontvangen"
                        }
                    }
                    catch {
                        Write-Host "❌ LMStudio niet beschikbaar voor batch verwerking. Fout: $_"
                    }
                }

                # Process batch suggestions
                if ($batchSuggestions) {
                    # Parse the response to extract results for each file
                    $lines = $batchSuggestions -split "`n"

                    foreach ($fileInfo in $batch) {
                        $fileName = Split-Path $fileInfo.FilePath -Leaf
                        $result = $null

                        # Look for the file in the response using the provided processing function
                        foreach ($line in $lines) {
                            $result = & $ProcessResponse $line $fileName
                            if ($result) {
                                break
                            }
                        }

                        # If no specific match found, use fallback
                        if (-not $result -or $result -eq "Geen") {
                            $result = & $GetFallbackValue $fileInfo
                            if (-not $result) {
                                $result = $DefaultValue
                            }
                            Write-Host "📄 Standaard waarde gebruikt voor $fileName"
                        }
                        else {
                            Write-Host "📄 LLM resultaat gebruikt voor $fileName"
                        }

                        # Store the result
                        $results[$fileInfo.FilePath] = $result
                    }
                }
                else {
                    # If LLM failed, use default logic for all files in batch
                    foreach ($fileInfo in $batch) {
                        $fileName = Split-Path $fileInfo.FilePath -Leaf
                        $result = & $GetFallbackValue $fileInfo
                        if (-not $result) {
                            $result = $DefaultValue
                        }

                        Write-Host "📄 Standaard waarde gebruikt voor $fileName"
                        $results[$fileInfo.FilePath] = $result
                    }
                }

                # Reset batch for next iteration
                $batch = @()
                $batchCount = 0
            }
        }
    }

    return $results
}

# Function to process files in batches for LLM suggestions
function Get-BatchLlmSuggestions {
    param (
        [Parameter(Mandatory = $true)]
        [array]$Files,

        [Parameter(Mandatory = $false)]
        [int]$BatchSize = 10
    )

    $promptTemplate = @"
Je bent een bestandsorganisatie-assistent. Geef suggesties voor geschikte submappen voor deze bestanden:

Bestandsextensie: `$extension
Hoofdcategorie: `$category

Bestanden:
`$fileDescriptions

BELANGRIJK: Zoek naar patronen en relaties tussen bestanden. Probeer bestanden te clusteren in logische groepen.
- Groepeer bestanden die bij dezelfde entiteit horen (bijv. "Familie Jansen", "Project Alpha")
- Groepeer bestanden van dezelfde gebeurtenis of activiteit (bijv. "Vakantie 2022", "Verbouwing Huis")
- Zoek naar gemeenschappelijke namen, personen of thema's in bestandsnamen
- Gebruik datums of periodes als dat logisch is (bijv. "2022-Q1", "Zomer 2023")
- Houd rekening met de wijzigingsdatum van bestanden bij het maken van suggesties

BELANGRIJK: Gebruik NIET de hoofdcategorie "`$category" (of varianten daarvan in enkelvoud of meervoud) in de naam van de submap.

Geef voor elk bestand een suggestie in het volgende formaat:
[Bestandsnaam]: [Submap]

Als er geen specifieke submap nodig is, gebruik dan "Geen" als submap.
"@

    $systemPrompt = "Je bent een bestandsorganisatie-assistent die korte, directe antwoorden geeft. Je zoekt naar patronen tussen bestanden en groepeert ze in logische clusters op basis van entiteiten, namen, gebeurtenissen of thema's. Je streeft naar consistente mapnamen voor gerelateerde bestanden. Gebruik NIET de hoofdcategorie (of varianten daarvan in enkelvoud of meervoud) in de naam van de submap. Houd rekening met de wijzigingsdatum van bestanden bij het maken van suggesties."

    $processResponse = {
        param($line, $fileName)
        if ($line -match "(?i)$([regex]::Escape($fileName)).*?:\s*(.+)") {
            return $matches[1].Trim()
        }
        return $null
    }

    $getFallbackValue = {
        param($fileInfo)
        $parentDir = Split-Path (Split-Path $fileInfo.FilePath -Parent) -Leaf
        return if ($parentDir -ieq "Desktop") { "" } else { $parentDir }
    }

    return Invoke-LlmBatchProcessing -Files $Files -BatchSize $BatchSize -PromptTemplate $promptTemplate -SystemPrompt $systemPrompt -ProcessResponse $processResponse -GetFallbackValue $getFallbackValue
}

# Function to classify files as system or user files using LLM
function Get-LlmFileClassification {
    param (
        [Parameter(Mandatory = $true)]
        [array]$Files,

        [Parameter(Mandatory = $false)]
        [int]$BatchSize = 100
    )

    $promptTemplate = @"
Je bent een bestandsclassificatie-assistent. Bepaal voor elk bestand of het waarschijnlijk een systeembestand of een gebruikersbestand is.

Bestandsextensie: `$extension
Categorie: `$category

Bestanden:
`$fileDescriptions

Classificeer elk bestand als een van de volgende:
- "Waarschijnlijk systeembestand": Bestanden die bij het besturingssysteem of geïnstalleerde software horen
- "Waarschijnlijk gebruikersbestand": Bestanden die door de gebruiker zijn gemaakt of bewerkt

BELANGRIJK: Geef voor elk bestand een classificatie in het volgende formaat:
[Bestandsnaam]: [Classificatie]

Als je niet zeker bent, kies dan de meest waarschijnlijke classificatie op basis van de bestandsnaam, extensie en map.
"@

    $systemPrompt = "Je bent een bestandsclassificatie-assistent die bestanden classificeert als 'Waarschijnlijk systeembestand' of 'Waarschijnlijk gebruikersbestand'. Geef korte, directe antwoorden in het formaat [Bestandsnaam]: [Classificatie]."

    $processResponse = {
        param($line, $fileName)
        if ($line -match "(?i)$([regex]::Escape($fileName)).*?:\s*(.+)") {
            return $matches[1].Trim()
        }
        return $null
    }

    $getFallbackValue = {
        param($fileInfo)
        return "Onbeslist"
    }

    return Invoke-LlmBatchProcessing -Files $Files -BatchSize $BatchSize -PromptTemplate $promptTemplate -SystemPrompt $systemPrompt -DefaultValue "Onbeslist" -ProcessResponse $processResponse -GetFallbackValue $getFallbackValue
}

# Export functions
Export-ModuleMember -Function Get-BatchLlmSuggestions, Get-LlmFileClassification, Invoke-LlmBatchProcessing
