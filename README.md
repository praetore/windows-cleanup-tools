# 🛠️ Opschoon- en Organisatiescripts

Een verzameling PowerShell-scripts om bestanden te ordenen, classificeren, verplaatsen, herstellen en verwijderen.

## ↺ Inhoud

| Script                              | Doel                                                                                     |
|-------------------------------------|------------------------------------------------------------------------------------------|
| `SorteerOpDatum.ps1`                | Sorteert bestanden in jaar/maand submappen op basis van laatste wijzigingsdatum.         |
| `BestandenVerplaatsen.ps1`          | Categoriseert bestanden naar type (documenten, afbeeldingen, backups, boeken, etc.).     |
| `VerplaatslijstAanmaken.ps1`        | Genereert een CSV met bestemmingen voor bestanden op basis van extensie.                 |
| `HerstelVerplaatsteBestanden.ps1`   | Zet bestanden terug naar hun originele locatie op basis van gegenereerde log-CSV.        |
| `ClassificeerBestanden.ps1`         | Classificeert bestanden als gebruikers- of systeembestand o.b.v. extensie, naam en pad.  |
| `VerwijderOngewensteBestanden.ps1`  | Verwijdert bestanden uit een tekst- of csv-bestand met paden.                            |
| `VerwijderLegeMappen.ps1`           | Verwijdert lege mappen én mappen met alleen restanten zoals `desktop.ini` of `Thumbs.db`. |
| `config.json`                       | Configuratiebestand met extensies en keywords voor classificatie en categorisatie.        |
| `SharedModule`                      | PowerShell module met gedeelde functies voor alle scripts.                                |

## 📄 Algemene richtlijnen

- Scripts gebruiken parameters zoals `-Path`, `-Out`, `-Copy`, `-File`, `-Config`, `-LogFile`.
- Bestandscategorieën en classificatieregels worden geconfigureerd in `config.json`.
- Verplaatsscripts genereren CSV-logs die gebruikt kunnen worden om bestanden terug te zetten.
- De hersteltool leest deze logs in en zet bestanden terug naar de oorspronkelijke locatie.

## 🧰 Beschrijving per script

### `SorteerOpDatum.ps1`
Sorteert bestanden in jaar/maand mappen op basis van de laatste wijzigingsdatum.
- **Parameters**: `-Path`, `-Out`, `-LogFile`
- **Voorbeeld outputstructuur**: `2024\06\bestand.jpg`
- **Logging**: Genereert een CSV-log met kolommen `Origineel`, `Bestemming`, `Actie`
- **Herbruikbaar met**: `HerstelVerplaatsteBestanden.ps1`

---

### `BestandenVerplaatsen.ps1`
Verplaatst of kopieert bestanden op basis van extensie en categoriseert ze in doelmappen per type.
- **Parameters**: `-Path`, `-Out`, `-Copy`, `-File`, `-LogFile`, `-Config`
- **Input**: Kan een map doorzoken (`-Path`) of een bestand met paden lezen (`-File`)
- **Ondersteunt**: CSV-bestanden met kolom 'Bestand' of tekstbestanden met één pad per regel
- **Logging**: Genereert een CSV-log met kolommen `Origineel`, `Bestemming`, `Actie`
- **Herbruikbaar met**: `HerstelVerplaatsteBestanden.ps1`

---

### `VerplaatslijstAanmaken.ps1`
Genereert een CSV-bestand met bestanden en hun bestemmingen op basis van bestandsextensies, zonder de bestanden daadwerkelijk te verplaatsen.
- **Parameters**: `-File`, `-Out`, `-LogFile`, `-Config`
- **Input**: Tekstbestand met één bestandspad per regel
- **Output**: CSV-bestand met kolommen `Bestand` en `Bestemming`
- **Categorisatie**: Gebruikt de `user.extensions` sectie uit config.json om bestanden te categoriseren
- **Gebruik met**: De gegenereerde CSV kan gebruikt worden met `BestandenVerplaatsen.ps1 -File "verplaatslijst.csv"`

---

### `HerstelVerplaatsteBestanden.ps1`
Leest een CSV-log en zet bestanden terug naar hun oorspronkelijke pad.
- **Parameters**: `-File`
- **Input CSV**: vereist kolommen `Origineel` en `Bestemming`

---

### `ClassificeerBestanden.ps1`
Berekent voor elk bestand een score o.b.v. extensie, bestandsnaam en padinhoud, en classificeert deze:
- **Parameters**: `-Path`, `-Config`
- **Classificaties**: `Waarschijnlijk systeembestand`, `Waarschijnlijk gebruikersbestand`, `Onbeslist`
- **Output**: CSV-rapport met kolommen: `Bestand`, `Categorie`, `Score`, `Classificatie`
- **Export**: automatisch naar map `classificatie-<timestamp>\...`

---

### `VerwijderOngewensteBestanden.ps1`
Verwijdert paden opgegeven in een `.txt` of `.csv`-bestand.
- **Parameters**: `-File`
- **Ondersteunt**: eenvoudige padlijsten (txt) of CSV-bestanden met kolom `Origineel`

---

### `VerwijderLegeMappen.ps1`
Zoekt en verwijdert lege mappen, ook wanneer ze alleen systeemrestanten bevatten.
- **Parameters**: `-Path`, `-Config`
- **Verwijdert**: ook mappen die enkel `Thumbs.db`, `desktop.ini` of `.ds_store` bevatten
- **Configuratie**: Gebruikt de `ignore` sectie uit config.json voor ongewenste bestanden en mappen

---

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

### `SharedModule`
PowerShell module met gedeelde functies voor alle scripts.
- **Functies**:
  - `Get-Configuration`: Laadt configuratie uit config.json en structureert deze voor gebruik in scripts
  - `Get-Categorie`: Bepaalt de categorie van een bestand op basis van extensie
  - `Get-NormalizedPath`: Normaliseert een pad en maakt de map aan indien nodig
- **Gebruik**: Alle scripts importeren deze module automatisch
- **Voordelen**: 
  - Centraliseert gemeenschappelijke functionaliteit
  - Vermindert code duplicatie
  - Zorgt voor consistente verwerking in alle scripts

## 🔄 Voorbeelden

```powershell
# 📂 Verplaats bestanden op basis van type en submap
.\BestandenVerplaatsen.ps1 -Path "C:\Users\jhaag\Downloads" -Out "C:\Gesorteerd" -Copy

# 📂 Verplaats bestanden uit een tekstbestand met paden
.\BestandenVerplaatsen.ps1 -File "te_verplaatsen.txt" -Out "C:\Gesorteerd" -LogFile "verplaatslog.csv"

# 📂 Gebruik een aangepast configuratiebestand
.\BestandenVerplaatsen.ps1 -Path "C:\Data" -Out "C:\Gesorteerd" -Config "mijn-config.json"

# 📅 Sorteer bestanden op datum en maak een log voor herstel
.\SorteerOpDatum.ps1 -Path "C:\Ongesorteerd" -Out "C:\Op-Datum" -LogFile "sorteerlog.csv"

# 📊 Classificeer bestanden op verdacht/gebruiker
.\ClassificeerBestanden.ps1 -Path "C:\Backup"

# 📊 Classificeer met aangepaste configuratie
.\ClassificeerBestanden.ps1 -Path "C:\Backup" -Config "mijn-config.json"

# ↩️ Herstel bestanden naar originele locaties
.\HerstelVerplaatsteBestanden.ps1 -File "verplaatslog.csv"

# 🗑️ Verwijder lege/vervuilde mappen
.\VerwijderLegeMappen.ps1 -Path "C:\Gesorteerd"

# 🗑️ Verwijder lege/vervuilde mappen met aangepaste configuratie
.\VerwijderLegeMappen.ps1 -Path "C:\Gesorteerd" -Config "mijn-config.json"

# ❌ Verwijder specifieke bestanden uit lijst
.\VerwijderOngewensteBestanden.ps1 -File "verwijderlijst.csv"

# 📋 Genereer een verplaatslijst zonder bestanden te verplaatsen
.\VerplaatslijstAanmaken.ps1 -File "te_verplaatsen.txt" -Out "C:\Doel" -OutFile "verplaatslijst.csv"
```

Scripts zijn bedoeld om herbruikbaar en combineerbaar te zijn, zodat grootschalige opruimacties overzichtelijk en controleerbaar blijven.

## ⚙️ Configuratie

Het `config.json` bestand bevat alle configuratie voor de scripts, georganiseerd in drie hoofdsecties:

1. **user**: Configuratie voor gebruikersbestanden (gebruikt door BestandenVerplaatsen.ps1, VerplaatslijstAanmaken.ps1 en ClassificeerBestanden.ps1)
   - **extensions**: Bestandsextensies per categorie (Afbeeldingen, Documenten, etc.)
   - **directories**: Mapnamen die wijzen op gebruikerslocaties

2. **system**: Configuratie voor systeembestanden (gebruikt door ClassificeerBestanden.ps1)
   - **extensions**: Extensies van systeembestanden (.dll, .exe, etc.)
   - **directories**: Mapnamen die wijzen op systeemlocaties
   - **files**: Bestandsnamen die wijzen op systeembestanden

3. **ignore**: Configuratie voor bestanden en mappen die genegeerd moeten worden (gebruikt door VerwijderLegeMappen.ps1)
   - **extensions**: Extensies van bestanden die genegeerd moeten worden (.ds_store, thumbs.db, etc.)
   - **directories**: Namen van mappen die genegeerd moeten worden (__macosx, system volume information, etc.)

Je kunt dit bestand aanpassen om de scripts aan te passen aan je specifieke behoeften. Gebruik de `-Config` parameter om een aangepast configuratiebestand te gebruiken.
