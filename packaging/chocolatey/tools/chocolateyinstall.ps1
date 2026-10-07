$ErrorActionPreference = 'Stop'
$toolsDir = "$(Split-Path -parent $MyInvocation.MyCommand.Definition)"

$packageArgs = @{
  packageName    = 'bishare'
  unzipLocation  = $toolsDir
  url64bit       = 'https://github.com/BIShare-project/bishare-flutter/releases/download/v2.6.0/BIShare-2.6.0-windows-x64.zip'
  checksum64     = 'e6ea979cd7dc6becb848762cbf3f7bad04f5c3cb05cd308b9c4bebbfae9e7873'
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
