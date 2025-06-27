# 🛠️ Opschoon- en Organisatiescripts

Een verzameling PowerShell-scripts om bestanden te ordenen, classificeren, verplaatsen, herstellen en verwijderen.

## ↺ Inhoud

| Script                             | Doel                                                                                      |
|------------------------------------|-------------------------------------------------------------------------------------------|
| `SorteerOpDatum.ps1`               | Sorteert bestanden in jaar/maand submappen op basis van laatste wijzigingsdatum.          |
| `BestandenVerplaatsen.ps1`         | Verplaatst of kopieert bestanden uit map of lijst naar doelmap      |
| `VerplaatsingBepalen.ps1`          | Genereert een CSV met bestemmingen voor bestanden op basis van extensie.                  |
| `HerstelVerplaatsteBestanden.ps1`  | Zet bestanden terug naar hun originele locatie op basis van gegenereerde log-CSV.         |
| `ClassificeerBestanden.ps1`        | Classificeert bestanden als gebruikers- of systeembestand o.b.v. extensie, naam en pad.   |
| `VerwijderOngewensteBestanden.ps1` | Verwijdert bestanden uit een tekst- of csv-bestand met paden.                             |
| `VerwijderLegeMappen.ps1`          | Verwijdert lege mappen én mappen met alleen restanten zoals `desktop.ini` of `Thumbs.db`. |
| `config.json`                      | Configuratiebestand met extensies en keywords voor classificatie en categorisatie.        |
| `SharedModule`                     | PowerShell module met gedeelde functies voor alle scripts.                                |
| `LlmModule`                        | PowerShell module voor interactie met lokale LLM-modellen (LMStudio of Ollama).           |

## 🧰 Beschrijving per script

### `SorteerOpDatum.ps1`

Sorteert bestanden in submappen per jaar en maand op basis van de laatste wijzigingsdatum (`LastWriteTime`).

- **Parameters**:
  - `-Path`: De bronmap die je wilt ordenen (wordt recursief doorzocht naar bestanden).
  - `-Out`: De doelmap waarin bestanden worden geplaatst in structuur: \YYYY\MM\bestand.ext
  - `-LogFile`: (optioneel) Pad naar een logbestand. Indien niet opgegeven, wordt automatisch een logbestand met timestamp aangemaakt.
- **Ondersteunt**:
  - Volledige mappen met bestanden (recursief)
- **Gedrag**:
  - Bestanden worden verplaatst naar submappen gestructureerd als `Jaar\Maand` op basis van hun laatste wijzigingsdatum.
  - Als er bestandsnaamconflicten zijn, wordt automatisch een timestamp aan de bestandsnaam toegevoegd.
- **Logging**:
  - CSV met kolommen: `Origineel`, `Bestemming`, `Actie`
- **Herbruikbaar met**: `HerstelVerplaatsteBestanden.ps1` om bestanden terug te zetten naar hun originele locaties.
### `BestandenVerplaatsen.ps1`

Verplaatst of kopieert bestanden vanuit een opgegeven map of een bestand met paden naar een doelmap, of naar specifieke bestemmingen uit een CSV-bestand.

- **Parameters**:
  - `-Path`: (optioneel) Map die recursief wordt doorzocht naar bestanden om te verplaatsen of kopiëren.
  - `-File`: (optioneel) Tekstbestand met één pad per regel, of een CSV met kolom `Bestand` (en optioneel `Bestemming`).
  - `-Out`: Doelmap waarin bestanden geplaatst worden (verplicht bij gebruik van `-Path`, of bij `-File` zonder `Bestemming`-kolom).
  - `-Copy`: Voeg deze switch toe om bestanden te kopiëren i.p.v. verplaatsen.
  - `-LogFile`: Pad naar optioneel CSV-logbestand. Indien niet opgegeven, wordt een log met timestamp aangemaakt.
- **Ondersteunt**:
  - Bestanden uit een map (`-Path`)
  - Tekstbestanden met één bestandspad per regel (`-File`)
  - CSV-bestanden met kolom `Bestand` (en eventueel `Bestemming`)
- **Gedrag**:
  - Als `Bestemming`-kolom aanwezig is: die paden worden als doel gebruikt.
  - Als alleen `-Out` wordt opgegeven: bestanden worden daarheen verplaatst of gekopieerd.
  - Standaard worden bestanden verplaatst, tenzij `-Copy` is opgegeven of automatisch ingeschakeld bij CSV-bestemmingen.
- **Logging**:
  - Alle acties worden gelogd in een CSV met kolommen: `Origineel`, `Bestemming`, `Actie`.
- **Herbruikbaar met**: `HerstelVerplaatsteBestanden.ps1` voor het terugzetten van bestanden.
### `VerplaatsingBepalen.ps1`

Genereert een CSV-bestand met voorgestelde bestemmingen voor bestanden op basis van extensiecategorieën uit `config.json`.

- **Parameters**:
  - `-File`: Tekstbestand met één bestandspad per regel.
  - `-Out`: Doelmap waarin bestanden uiteindelijk zouden worden geplaatst (deze wordt alleen voor padopbouw gebruikt).
  - `-OutFile`: Pad naar het CSV-bestand dat gegenereerd wordt met de voorgestelde verplaatsingen.
  - `-Config`: Pad naar een `config.json` bestand met categorisatieregels (indien niet opgegeven wordt de standaard gebruikt).
  - `-LogFile`: (optioneel) Pad naar een extra logbestand met verwerkingsdetails.
- **Ondersteunt**:
  - TXT-bestanden met bestandsnamen
- **Gedrag**:
  - Bepaalt bestemmingen op basis van extensies en categorieën in de configuratie.
- **Output**:
  - CSV met kolommen: `Bestand`, `Bestemming`
- **Herbruikbaar met**: `BestandenVerplaatsen.ps1` (via `-File`) om de verplaatsing uit te voeren.
### `HerstelVerplaatsteBestanden.ps1`

Zet bestanden terug naar hun oorspronkelijke locatie op basis van een CSV-logbestand.

- **Parameters**:
  - `-File`: CSV-bestand met kolommen `Origineel` en `Bestemming`.
- **Ondersteunt**:
  - Logbestanden gegenereerd door `BestandenVerplaatsen.ps1` of `SorteerOpDatum.ps1`.
- **Gedrag**:
  - Verwisselt kolommen `Origineel` en `Bestemming` en verplaatst bestanden terug naar hun oorspronkelijke locatie.
- **Logging**:
  - Geen extra logging; logbestand dient als invoer en verslag.
- **Herbruikbaar met**:
  - `BestandenVerplaatsen.ps1`, `SorteerOpDatum.ps1`, en andere scripts die verplaatslogs genereren.
### `ClassificeerBestanden.ps1`

Classificeert bestanden als systeem- of gebruikersbestand op basis van extensie, pad en bestandsnaam.

- **Parameters**:
  - `-Path`: De map waarin bestanden geanalyseerd worden.
  - `-Config`: (optioneel) Pad naar een `config.json` bestand met classificatieregels.
- **Ondersteunt**:
  - Recursieve mappenstructuren met diverse bestandstypes
- **Gedrag**:
  - Gebruikt heuristieken op basis van extensie, mapnamen en bestandsnamen om bestanden te classificeren als:
    - `Waarschijnlijk gebruikersbestand`
    - `Waarschijnlijk systeembestand`
    - `Onbeslist`
- **Output**:
  - CSV-rapport met kolommen: `Bestand`, `Categorie`, `Score`, `Classificatie`
  - Rapport wordt automatisch opgeslagen in `classificatie-<timestamp>\...`
- **Herbruikbaar met**:
  - Andere scripts voor filtering, verplaatsing of verwijdering.
### `VerwijderOngewensteBestanden.ps1`

Verwijdert bestanden op basis van een lijst in een `.txt` of `.csv`-bestand.

- **Parameters**:
  - `-File`: Tekstbestand met één pad per regel, of CSV-bestand met kolom `Origineel`.
- **Ondersteunt**:
  - Zowel eenvoudige padlijsten als CSV-logs
- **Gedrag**:
  - Verwijdert bestanden en toont waarschuwingen bij ontbrekende of vergrendelde bestanden.
- **Logging**:
  - Geen aparte log; verwijderde bestanden zijn in te zien via de oorspronkelijke invoerlijst.
### `VerwijderLegeMappen.ps1`

Zoekt en verwijdert lege mappen en systeemrestanten uit een opgegeven pad.

- **Parameters**:
  - `-Path`: De hoofdmap waarin gezocht wordt.
  - `-Config`: (optioneel) JSON-bestand met instellingen voor uitzonderingen (`ignore.directories`, `ignore.extensions`).
- **Ondersteunt**:
  - Recursieve opschoning, inclusief lege mappen met alleen bestanden als `Thumbs.db`, `desktop.ini`, `.DS_Store`, etc.
- **Gedrag**:
  - Verwijdert mappen die volledig leeg zijn óf enkel bekende 'rommel' bevatten.
- **Logging**:
  - Console-uitvoer van verwijderde mappen.
### `config.json`

Configuratiebestand met extensies en keywords voor classificatie en categorisatie.

- **Structuur**:
	- `user`: Bevat gebruikersgerelateerde configuratie
		- `extensions`: Extensies voor gebruikersbestanden, georganiseerd per categorie (Afbeeldingen, Documenten, etc.)
		- `directories`: Keywords in paden die wijzen op gebruikerslocaties (documents, downloads, etc.)
	- `system`: Bevat systeemgerelateerde configuratie
		- `extensions`: Extensies voor systeembestanden (.dll, .exe, etc.)
		- `directories`: Keywords in paden die wijzen op systeemlocaties (windows, program files, etc.)
		- `files`: Keywords in bestandsnamen die wijzen op systeembestanden (setup, autorun, etc.)
	- `ignore`: Bevat configuratie voor bestanden en mappen die genegeerd of verwijderd moeten worden
		- `extensions`: Extensies van bestanden die genegeerd moeten worden (.ds_store, thumbs.db, etc.)
		- `directories`: Namen van mappen die genegeerd moeten worden (__macosx, system volume information, etc.)

---