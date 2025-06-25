# 🛠️ Opschoon- en Organisatiescripts

Een verzameling PowerShell-scripts om bestanden te ordenen, classificeren, verplaatsen, herstellen en verwijderen.

## ↺ Inhoud

| Script                              | Doel                                                                                     |
|-------------------------------------|------------------------------------------------------------------------------------------|
| `Ordenen.ps1`                       | Sorteert bestanden in jaar/maand submappen op basis van laatste wijzigingsdatum.         |
| `BestandenVerplaatsen.ps1`          | Categoriseert bestanden naar type (documenten, afbeeldingen, backups, boeken, etc.).     |
| `HerstelVerplaatsteBestanden.ps1`   | Zet bestanden terug naar hun originele locatie op basis van gegenereerde log-CSV.        |
| `ClassificeerBestanden.ps1`         | Classificeert bestanden als gebruikers- of systeembestand o.b.v. extensie, naam en pad.  |
| `VerwijderOngewensteBestanden.ps1`  | Verwijdert bestanden uit een tekst- of csv-bestand met paden.                            |
| `VerwijderLegeMappen.ps1`           | Verwijdert lege mappen én mappen met alleen restanten zoals `desktop.ini` of `Thumbs.db`. |

## 📄 Algemene richtlijnen

- Scripts gebruiken parameters zoals `-Path`, `-Out`, `-Copy`, `-File`.
- Bestandscategorieën zijn: "Afbeeldingen", "Documenten", "Muziek", "Video's", "Backups", "Boeken", "Adobe", "Overig".
- Classificatiescripts leveren CSV-uitvoer met kolommen zoals Score, Classificatie, Bestandspad.
- De hersteltool leest deze logs in en zet bestanden terug naar de oorspronkelijke locatie.

## 🧰 Beschrijving per script

### `Ordenen.ps1`
Sorteert bestanden in jaar/maand mappen op basis van de laatste wijzigingsdatum.
- **Parameters**: `-Path`, `-Out`
- **Voorbeeld outputstructuur**: `2024\06\bestand.jpg`

---

### `BestandenVerplaatsen.ps1`
Verplaatst of kopieert bestanden op basis van extensie en categoriseert ze in doelmappen per type.
- **Parameters**: `-Path`, `-Out`, `-Copy`, `-File`
- **Optioneel**: logbestand (CSV) met kolommen: `Origineel`, `Bestemming`, `Actie`
- **Herbruikbaar met**: `HerstelVerplaatsteBestanden.ps1`

---

### `HerstelVerplaatsteBestanden.ps1`
Leest een CSV-log en zet bestanden terug naar hun oorspronkelijke pad.
- **Parameters**: `-File`
- **Input CSV**: vereist kolommen `Origineel` en `Bestemming`

---

### `ClassificeerBestanden.ps1`
Berekent voor elk bestand een score o.b.v. extensie, bestandsnaam en padinhoud, en classificeert deze:
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
- **Parameters**: `-Path`
- **Verwijdert**: ook mappen die enkel `Thumbs.db`, `desktop.ini` of `.ds_store` bevatten

## 🔄 Voorbeelden

```powershell
# 📂 Verplaats bestanden op basis van type en submap
.\BestandenVerplaatsen.ps1 -Path "C:\Users\jhaag\Downloads" -Out "C:\Gesorteerd" -Copy

# 📊 Classificeer bestanden op verdacht/gebruiker
.\ClassificeerBestanden.ps1 -Path "C:\Backup"

# ↩️ Herstel bestanden naar originele locaties
.\HerstelVerplaatsteBestanden.ps1 -File "move-20240620-131011.csv"

# 🗑️ Verwijder lege/vervuilde mappen
.\VerwijderLegeMappen.ps1 -Path "C:\Gesorteerd"

# ❌ Verwijder specifieke bestanden uit lijst
.\VerwijderOngewensteBestanden.ps1 -File "verwijderlijst.csv"
```

Scripts zijn bedoeld om herbruikbaar en combineerbaar te zijn, zodat grootschalige opruimacties overzichtelijk en controleerbaar blijven.

