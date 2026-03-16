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