$desktopPath = [Environment]::GetFolderPath("Desktop")
Remove-Item "$desktopPath\SuperSlicer.lnk" -ErrorAction SilentlyContinue -Force