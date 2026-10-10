$ErrorActionPreference = 'Stop'
$toolsDir = "$(Split-Path -parent $MyInvocation.MyCommand.Definition)"

$packageArgs = @{
  packageName    = 'bishare'
  unzipLocation  = $toolsDir
  url64bit       = 'https://github.com/BIShare-project/bishare-flutter/releases/download/v2.6.1/BIShare-2.6.1-windows-x64.zip'
  checksum64     = 'e2367c89eb6146d810a2500e186020e947bb08483213a4f55362d71fa17a90b8'
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
