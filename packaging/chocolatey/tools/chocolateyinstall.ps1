$ErrorActionPreference = 'Stop'
$toolsDir = "$(Split-Path -parent $MyInvocation.MyCommand.Definition)"

$packageArgs = @{
  packageName    = 'bishare'
  unzipLocation  = $toolsDir
  url64bit       = 'https://github.com/BIShare-project/bishare-flutter/releases/download/v2.4.5/BIShare-2.4.5-windows-x64.zip'
  checksum64     = '8a0b20095a630ebde5ec5be02adc97d11034c02f0cb35f40eb0f68ea5a73c700'
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
