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
    # Converting the HashTable to PSCustomObject fo ConvertTo-Csv
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