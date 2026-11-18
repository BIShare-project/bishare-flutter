$ErrorActionPreference = 'Stop'
$toolsDir = "$(Split-Path -parent $MyInvocation.MyCommand.Definition)"

$packageArgs = @{
  packageName    = 'bishare'
  unzipLocation  = $toolsDir
  url64bit       = 'https://github.com/BIShare-project/bishare-flutter/releases/download/v2.9.3/BIShare-2.9.3-windows-x64.zip'
  checksum64     = '0f6d2fa1421b0277bfd9a33547193fd49ad5b5f86d95957e981b5764bc62ebcb'
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
