$ErrorActionPreference = 'Stop'
$toolsDir = "$(Split-Path -parent $MyInvocation.MyCommand.Definition)"

$packageArgs = @{
  packageName    = 'bishare'
  unzipLocation  = $toolsDir
  url64bit       = 'https://github.com/BIShare-project/bishare-flutter/releases/download/v2.6.3/BIShare-2.6.3-windows-x64.zip'
  checksum64     = '7826ab5b240002362af8b9fdc6d41ef5e1a6805a0668f1670b4c4654a3f9d514'
  checksumType64 = 'sha256'
}
Install-ChocolateyZipPackage @packageArgs

# bishare.exe is a GUI app: the .gui marker makes Chocolatey's shim launch it
# without attaching a console window.
$exe = Join-Path $toolsDir 'bishare.exe'
New-Item -ItemType File -Path "$exe.gui" -Force | Out-Null

Install-ChocolateyShortcut `
  -ShortcutFilePath (Join-Path ([Environment]::GetFolderPath('Programs')) 'BIShare.lnk') `
  -TargetPath $exe `
  -WorkingDirectory $toolsDir
