---
title: "Fájl verifikáció PowerShell-el"
date: 2023-06-09T21:42:10.0395277+02:00
draft: false
toc: true
images:
tags:
  - powershell
---

## A probléma

Szükségem volt egy egyszerű kis tool-ra, amivel fájlok konzisztenciáját tudtam ellenőrizni.
Szerencsére PowerShell-el ez könnyen megtehető mindössze annyi van, hogy az alapvetően egyszerre csak egy fájlra működik.

Az ötlet az volt, hogy egy adott fájl halmaz minden fájl-jára generálok egy SHA256 hash-et, és ezeket eltárolom későbbi ellenőrzés céljából.
PowerShell-el könnyen lehet CSV formátumba és -ból konvertálni úgyhogy ez kézenfekvő választás volt a hash-ek tárolására.

A hash számítás tehát így fog kinézni:
- Végignézem az összes fájlt a jelenlegi mappából kiindulva rekurzívan
- Minden fájlra generálok egy SHA256 hash-t a `Get-FileHash` cmdlet-el
- Lementem a fájlok relatív útvonalait és a hozzájuk tartozó SHA256 hash-t egy CSV fájlba

A konzisztencia vizsgálat pedig a következő:
- Beolvasom a CSV fájlt egy PowerShell objektumba
- Végigmegyek az összes bejegyzésen
- Megnézem hogy az adott fájl létezik-e vagy sem
  - ❌ Ha a fájl nem létezik, az ellenőrzés hibát ír ki
  - Ha a fájl létezik, újra kalkulálom a SHA256 hash-ét és összehasonlítom a CSV fájlban tárolt hash értékkel
    - ❌ Ha a két hash eltér, az ellenőrzés hibát ír ki
  - ✅ Ha minden fájl létezik és minden hash érték megegyezik, a konzisztencia ellenőrzés sikeres

Tettem a script-ekbe egy progress indicator-t, hogy látszódjon hogy történik valami amíg a script fut.

## Hibák amikbe belefutottam

A következő hibákba futottam bele a script-ek írása közben:
- A `Get-ChildItem` alapból a mappákat is visszaadja, a `Get-FileHash` viszont ezekre hibát ad
  - Megoldás: a `-File` kapcsolót használva `Get-ChildItem` csak a fájlokat adja vissza
- Először úgy gondoltam, hogy JSON fájlba fogom exportálni a hash értékeket a `ConvertTo-Json` cmdlet-el, viszont rájöttem hogy egy JSON fájl jóval nagyobb lesz mint egy CSV a sok ismétlődő mezőnév miatt, ezért áttértem a CSV-re
  - Viszont kiderült hogy mikor egy PowerShell hash táblát konvertálunk a `ConvertTo-Csv` cmdlet-el az hibásan konvertálódik a `v7.2.0-preview.10`-nél korábbi verziókban (ven erről egy GitHub [issue](https://github.com/PowerShell/PowerShell/issues/10999) is)
  - Mivel én épp a `v7.3.4`-es verziót használtam ez nem is tűnt fel, amíg ki nem próbáltam Windows PowerShell-en (`v5.1`-es verzión)
  - Megoldás: a `[PSCustomObject]`-el a hash táblát `PSCustomObject`-re kell konvertálni
- A mappában, amiben teszteltem a script-et volt pár fura nevű fájl is, amiknek a nevében volt szögletes zárójel (`[]`)
  - Kiderült, hogy a `Get-FileHash`, a `Resolve-Path` és a `Test-Path` (bizonyára sok más cmdlet is) ezeket a karaktereket wildcard-ként kezeli és nem fogja megtalálni a konkrét fájlt
  - Megoldás: a `LiteralPath` kapcsolót használva az útvonalakban lévő wildcard karakterek autómatikusan escape-elve lesznek, így már megtalálja ezeket a fájlokat is

## A script-ek

### New-HashDigest

Ez a script letölthető [innen](./scripts/New-HashDigest.ps1).

```powershell
# Start progress output
Write-Progress -Activity "Calculating hashes..." -PercentComplete -1

# Get all file paths (except for sha256.csv which will contain the hashes)
# It's done separately to get the file count for the progress indicator
$files = Get-ChildItem . -Recurse -File -Exclude sha256.csv
$fileCount = $files.Length
$i = 0

# Calculate the SHA256 for all files
$files |
  Foreach-Object {
    $i++
    # Updating progress
    Write-Progress -Activity "Calculating hashes..." -PercentComplete $([int](100 * $i / $fileCount))

    $hash = Get-FileHash -Algorithm SHA256 -LiteralPath $_

    # Converting the paths to relative (check needs to be able to run from a different location)
    # Converting the HashTable to PSCustomObject for ConvertTo-Csv
    # (see also https://github.com/PowerShell/PowerShell/issues/10999)
    [PSCustomObject]@{ 
      Path = $(Resolve-Path -LiteralPath $_ -Relative)
      Hash= $hash.Hash
    }
  } |
  # Converting to CSV format
  ConvertTo-Csv |
  # Writing the SHA hashes to a CSV file
  Set-Content .\sha256.csv

Write-Host "Hash calculated for $i files..."
```

### Test-HashDigest

Ez a script letölthető [innen](./scripts/Test-HashDigest.ps1).

```powershell
# Getting the SHA hashes back from the CSV file
$hashes = Get-Content .\sha256.csv | ConvertFrom-Csv
# Get the length for the progress indicator
$hashesCount = $hashes.Length
$i = 0
$success = $true

$hashes |
  Foreach-Object {
    $i++
    # Updating progress
    Write-Progress -Activity "Checking hashes..." -PercentComplete $([int](100 * $i / $hashesCount))
    if (-not $(Test-Path -LiteralPath $_.Path))
    {
      # If a file is missing the check will fail
      $success = $false
      Write-Error "File missing $($_.Path)!"
    }
    else
    {
      $newHash = $(Get-FileHash -Algorithm SHA256 -LiteralPath $_.Path)
      if ($newHash.Hash -ne $_.Hash)
      {
        # If a file hash is different the check will fail
        $success = $false
        Write-Error "Hash check failed for file $($_.Path)!"
      }
    }
  }

if ($success)
{
  # Write something back if the check was successful
  Write-Host "Hash check successful!"
}
else
{
  # Throw an error if the check failed
  throw "Hash check failed!"
}
```
