---
title: "File verification with PowerShell"
date: 2023-06-09T21:42:10.0395277+02:00
draft: false
toc: true
images:
tags:
  - powershell
---

## The problem

I needed a small tool for checking the consistency of a set of files.
Fortunately PowerShell can do that, however it will only work for one file at a time.

The idea was to create a SHA256 hash for a set of files and store them for checking at a later time.
PowerShell can easily convert to and from CSV format so that was an obvious choice.

So the hash calculation will go as follows:
- Get all files in the current directory recursively
- Calculate the SHA256 for each file using the `Get-FileHash` cmdlet
- Store the relative file paths and corresponding SHA256 hashes in a CSV format

The consistency check will then go as follows:
- Read the CSV file into a PowerShell object
- Iterate through each entry
- Check if the corresponding file exists or not
  - ❌ If a file doesn't exist, the consistency check fails
  - If the file exists calculate the SHA256 hash and compare it to the one stored in the CSV file
    - ❌ If the two hashes differ the consistency check fails
  - ✅ If all files exist and all hashes match the consistency check passes

I spiced the scripts up with progress indication so we can see that something is happening while we wait for it to finish.

## Gotchas

A few gotchas I bumped into along the way:
- `Get-ChildItem` returns directories as well but `Get-FileHash` will give an error on directories
  - Solution: use the `-File` switch for `Get-ChildItem`
- First I was going to export the hashes to a JSON file with `ConvertTo-Json` but then I figured a CSV file would be much smaller
  - Turns out, when converting hash tables with `ConvertTo-Csv` it gives invalid results before PowerShell `v7.2.0-preview.10` (see also the corresponding GitHub [issue](https://github.com/PowerShell/PowerShell/issues/10999))
  - I was using `v7.3.4` at the time so I didn't notice this until I tried it with Windows PowerShell (`v5.1`)
  - Solution: use `[PSCustomObject]` to convert the hash table to a `PSCustomObject`
- I had some weirdly named files in one of the directories I was testing the scripts, files that had square brackets (`[]`) in their names
  - Turns out `Get-FileHash`, `Resolve-Path` and `Test-Path` (and I suppose a lot more cmdlets) don't work correctly with such filenames, as they interpret the square brackets as wildcards
  - Solution: use the `LiteralPath` that will correctly escape wildcard characters

## Scripts

### New-HashDigest

You can download the script file from [here](./scripts/New-HashDigest.ps1).

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

You can download the script file from [here](./scripts/Test-HashDigest.ps1).

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
