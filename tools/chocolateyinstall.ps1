$ErrorActionPreference = 'Stop'

$toolsPath   = Split-Path $MyInvocation.MyCommand.Definition

$packageArgs = @{
  PackageName     = $env:ChocolateyPackageName
  FileFullPath64  = gi $toolsPath\*_win64_*.zip
  Destination     = $toolsPath
}

Remove-Item $ENV:ChocolateyInstall\bin\superslicer*.exe # delete old shims
Remove-Item -Path $toolsPath\SuperSlicer_* -Exclude "*_win64_*.zip" -Recurse -Force # deleted old versions kept by upgrade

Get-ChocolateyUnzip @packageArgs

$files = Get-ChildItem $toolsPath -Include *.exe -Recurse

foreach ($file in $files) {
  if (!($file.Name.Equals("superslicer.exe"))) {
    #generate an ignore file
    New-Item "$file.ignore" -type file -Force | Out-Null
  }
  else {
    New-Item "$file.gui" -type file -Force | Out-Null
  }
}

$desktopPath = [Environment]::GetFolderPath("Desktop")
Install-ChocolateyShortcut `
  -ShortcutFilePath "$desktopPath\SuperSlicer.lnk" `
  -TargetPath "$env:ChocolateyInstall\bin\superslicer.exe"

#Don't need installer zips anymore
rm $toolsPath\*.zip -ea 0 -force
