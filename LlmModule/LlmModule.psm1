# LlmModule.psm1
# Contains functions for interacting with local LLM models (LMStudio or Ollama)

# Function to process files in batches for LLM suggestions
function Get-BatchLlmSuggestions {
    param (
        [Parameter(Mandatory = $true)]
        [array]$Files,

        [Parameter(Mandatory = $false)]
        [int]$BatchSize = 10
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
                    "- Bestandsnaam: $fileName, Huidige map: $parentDir"
                } | Out-String

                $batchPrompt = @"
Je bent een bestandsorganisatie-assistent. Geef suggesties voor geschikte submappen voor deze bestanden:

Bestandsextensie: $extension
Hoofdcategorie: $category

Bestanden:
$fileDescriptions

BELANGRIJK: Zoek naar patronen en relaties tussen bestanden. Probeer bestanden te clusteren in logische groepen.
- Groepeer bestanden die bij dezelfde entiteit horen (bijv. "Familie Jansen", "Project Alpha")
- Groepeer bestanden van dezelfde gebeurtenis of activiteit (bijv. "Vakantie 2022", "Verbouwing Huis")
- Zoek naar gemeenschappelijke namen, personen of thema's in bestandsnamen
- Gebruik datums of periodes als dat logisch is (bijv. "2022-Q1", "Zomer 2023")

Geef voor elk bestand een suggestie in het volgende formaat:
[Bestandsnaam]: [Submap]

Als er geen specifieke submap nodig is, gebruik dan "Geen" als submap.
"@

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
                        Write-Host "🤖 Ollama LLM batch suggesties ontvangen"
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
                                content = "Je bent een bestandsorganisatie-assistent die korte, directe antwoorden geeft. Je zoekt naar patronen tussen bestanden en groepeert ze in logische clusters op basis van entiteiten, namen, gebeurtenissen of thema's. Je streeft naar consistente mapnamen voor gerelateerde bestanden."
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
                            Write-Host "🤖 LMStudio LLM batch suggesties ontvangen"
                        }
                    }
                    catch {
                        Write-Host "❌ LMStudio niet beschikbaar voor batch verwerking. Fout: $_"
                    }
                }

                # Process batch suggestions
                if ($batchSuggestions) {
                    # Parse the response to extract suggestions for each file
                    $lines = $batchSuggestions -split "`n"

                    foreach ($fileInfo in $batch) {
                        $fileName = Split-Path $fileInfo.FilePath -Leaf
                        $suggestion = $null

                        # Look for the file in the response
                        foreach ($line in $lines) {
                            if ($line -match "(?i)$([regex]::Escape($fileName)).*?:\s*(.+)") {
                                $suggestion = $matches[1].Trim()
                                break
                            }
                        }

                        # If no specific match found, use fallback
                        if (-not $suggestion -or $suggestion -eq "Geen") {
                            $parentDir = Split-Path (Split-Path $fileInfo.FilePath -Parent) -Leaf
                            $suggestion = if ($parentDir -ieq "Desktop") { "" } else { $parentDir }
                            Write-Host "📁 Standaard mapindeling gebruikt voor $fileName"
                        }
                        else {
                            Write-Host "📁 LLM suggestie gebruikt voor $fileName"
                        }

                        # Store the result
                        $results[$fileInfo.FilePath] = $suggestion
                    }
                }
                else {
                    # If LLM failed, use default logic for all files in batch
                    foreach ($fileInfo in $batch) {
                        $fileName = Split-Path $fileInfo.FilePath -Leaf
                        $parentDir = Split-Path (Split-Path $fileInfo.FilePath -Parent) -Leaf
                        $suggestion = if ($parentDir -ieq "Desktop") { "" } else { $parentDir }

                        Write-Host "📁 Standaard mapindeling gebruikt voor $fileName"
                        $results[$fileInfo.FilePath] = $suggestion
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

# Export functions
Export-ModuleMember -Function Get-BatchLlmSuggestions
