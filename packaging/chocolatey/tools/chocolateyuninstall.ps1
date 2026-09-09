$ErrorActionPreference = 'Stop'
$shortcut = Join-Path ([Environment]::GetFolderPath('Programs')) 'BIShare.lnk'
if (Test-Path $shortcut) { Remove-Item $shortcut -Force }
# Extracted files under tools\ are removed by Chocolatey itself.
