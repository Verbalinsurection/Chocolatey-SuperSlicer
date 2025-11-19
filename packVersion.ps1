param (
  [Alias('f')]
    [switch]$force = $false,
  [Alias('d')]
    [switch]$debug = $false,
  [Alias('np')]
    [switch]$noPrompt = $false,
  [Alias('v')]
    [string]$fversion = [string]::Empty,
  [Alias('beta')]
    [switch]$preRelease = $false
)
if ($Debug) { $DebugPreference = 'Continue' }

function getNormVerion {
  param (
    [string]$version,
    [bool]$preRelease
  )
  $numericVersion = $version
  if ($version -match '^([0-9.]+)') {
    $numericVersion = $matches[1]
  }
  
  if ($numericVersion.length -lt 3) {
    $nver = [Version]::new($numericVersion, 0, 0, 0)
  } else {
    $nver = [Version] $numericVersion
    if($nver.Minor -eq -1) {$nver = [Version]::new($nver.Major, 0, 0, 0)}
    if($nver.Build -eq -1) {$nver = [Version]::new($nver.Major, $nver.Minor, 0, 0)}
    if($nver.Revision -eq -1) {$nver = [Version]::new($nver.Major, $nver.Minor, $nver.Build, 0)}
  }
  $ver = "$($nver.Major).$($nver.Minor).$($nver.Build).$($nver.Revision)"
  if(-not $preRelease) {
    return $ver
  } else {
    return "$ver-beta"
  }
}

function ReplaceInFile {
  param (
    [string]$FilePath,
    [string[]]$SrcText,
    [string[]]$TargetText
  )

  $utf8 = New-Object System.Text.UTF8Encoding $false
  $RawData = Get-Content $FilePath -Raw
  for ($index = 0; $index -lt $SrcText.count; $index++) {
      $RawData = $RawData.replace($SrcText[$index], $TargetText[$index])
  }
  Set-Content -Value $utf8.GetBytes($RawData) -Encoding Byte -Path $FilePath
}

function GetGithubInfos {
  param (
    [string]$repo,
    [bool]$preRelease
  )

  if ($fversion -eq [string]::Empty) {
    Write-Debug "Get Github infos: https://api.github.com/repos/$repo/releases?per_page=5"
    $releasePage = (Invoke-WebRequest "https://api.github.com/repos/$repo/releases?per_page=5" | ConvertFrom-Json)
    $matchPrerelease = if ($preRelease) { "True" } else { "False" }
    $releaseFiltered = ($releasePage | Select-Object tag_name, prerelease, html_url, assets | Where-Object {$_.prerelease -match $matchPrerelease})[0]
  } else {
    Write-Debug "Get Github infos: https://api.github.com/repos/$repo/releases for version $fversion"
    $releasePage = (Invoke-WebRequest "https://api.github.com/repos/$repo/releases" | ConvertFrom-Json)
    $releaseFiltered = ($releasePage | Select-Object tag_name, prerelease, html_url, assets | Where-Object {$_.tag_name -match $fversion})[0]
  }
  Write-Debug $releaseFiltered
  $winAsset64 = $releaseFiltered.assets | Select-Object id, name, browser_download_url | Where-Object {$_.name -match "win64.*\.zip"}

  Write-Debug "  Find asset x86_64: $($winAsset64.name)"

  Remove-Item -Path tools\SuperSlicer_*
  Invoke-WebRequest -Uri $winAsset64.browser_download_url -OutFile "tools/$($winAsset64.name)"

  $FileHash64 = Get-FileHash ("tools/$($winAsset64.name)")
  Write-Debug "  FileHash x86_64: $($FileHash64.Hash)"
  $isPrerelease = $releaseFiltered.prerelease -like "True"
  Write-Debug "  IsPrerelase: $isPrerelease"
  return @{
    Version      = getNormVerion $releaseFiltered.tag_name -preRelease $isPrerelease
    ReleaseUrl   = $releaseFiltered.html_url
    URL64        = $winAsset64.browser_download_url
    SHA64        = $FileHash64.Hash
    IsPrerelease = $isPrerelease
  }
}

function GetActual {
  param (
    [string]$packageId,
    [bool]$preRelease
  )

  Write-Debug "Get Chocolatey infos: $packageId"
  $chocoSearch = "choco search $packageId --by-id-only --exact --limit-output"
  if($preRelease) {
    $chocoSearch += " --pre"
  }
  $chocoVersion = Invoke-Expression $chocoSearch

  if(!$chocoVersion) {
    Write-Error "Unable to find package on Chocolatey"
    return '0.0.0.0'
  }
  Write-Debug " Find Chocolatey infos: $chocoVersion"
  return $chocoVersion.split('|')[1]
}

function BackupFiles {
  param (
    [string[]]$FilesToBackup
  )

  Write-Debug "Backup $($FilesToBackup.Count) files"
  $backupedFiles = New-Object System.Collections.Generic.List[System.Object]
  New-Item -Name "bck" -ItemType "directory" | out-null

  for ($index = 0; $index -lt $FilesToBackup.count; $index++) {
    $FileToBackup = $FilesToBackup[$index].Replace('/', '_')
    Write-Debug " Copy-Item $($FilesToBackup[$index]) -Destination bck/$FileToBackup"
    Copy-Item $FilesToBackup[$index] -Destination "bck/$FileToBackup"
    $backupedFiles.Add($FileToBackup)
  }
  return $backupedFiles
}

function RestoreFiles {
  param (
    [string[]]$FilesToRestore
  )

  Write-Debug "Restore $($FilesToRestore.Count) files"
  for ($index = 0; $index -lt $FilesToRestore.count; $index++) {
    $FileToRestore = $FilesToRestore[$index].Replace('_', '/')
    Write-Debug " Copy-Item bck/$($FilesToRestore[$index]) -Destination $FileToRestore -Force"
    Copy-Item "bck/$($FilesToRestore[$index])" -Destination $FileToRestore -Force
  }
  Remove-Item "bck" -Recurse
}

###############################################################################
##              Start                                                        ##
###############################################################################
Write-Host "--------------------------------------------------"
Write-Host "Packaging SuperSlicer"
Write-Host "--------------------------------------------------"

$packageId          = 'superslicer'
$githubRepo         = 'supermerill/SuperSlicer'
$filesToUpdate      = 'superslicer.nuspec', 'tools/VERIFICATION.txt'

## Get package and web version ##
$latestRelease = GetGithubInfos $githubRepo -preRelease $preRelease
$actualVersion = GetActual $packageId -preRelease $latestRelease.IsPrerelease
Write-Host "Chocolatey version  : $actualVersion"
Write-Host "Github repo version : $($latestRelease.Version)"

## Check if packaging is needed ##
if($latestRelease.Version -like $actualVersion -And !$force) {
  Write-Warning "No new version available"
  exit
}
Write-Warning "Update available !"

## Display release informations ##
Write-Host "--------------------------------------------------"
Write-Host "Url64 : $($latestRelease.URL64)"
Write-Host "Sha64 : $($latestRelease.SHA64)"
Write-Host "--------------------------------------------------"

if(!$noPrompt) {
  $confirmation = Read-Host "Start packing [Y/n]?"
  $confirmation = ('y',$confirmation)[[bool]$confirmation]
  if($confirmation -eq 'n') {exit}
}

## Backup files
$backupedFiles = BackupFiles $filesToUpdate

## Replace informations in files ##
for ($index = 0; $index -lt $filesToUpdate.count; $index++) {
  Write-Debug "Update $($filesToUpdate[$index])"
  ReplaceInFile -FilePath $filesToUpdate[$index] `
                -SrcText '#REPLACE_VERSION#', '#REPLACE_RELEASE_INFO#', '#REPLACE_URL#', '#REPLACE_CHECKSUM#' `
                -TargetText $latestRelease.Version, $latestRelease.ReleaseUrl, $latestRelease.URL64, $latestRelease.SHA64
}

## Pack choco package ##
if(!$noPrompt) {
  Read-Host -Prompt "Files updated, press any key to continue"
}
Write-Debug "Starting 'choco pack'"
choco pack

## Restore files
RestoreFiles $backupedFiles

## Push choco package ##
$confirmation = Read-Host "Push package [Y/n]?"
$confirmation = ('y',$confirmation)[[bool]$confirmation]
if($confirmation -eq 'n') {exit}

$packVersion = $latestRelease.Version
if ($packVersion -match '^(\d+\.\d+\.\d+)\.0(-.*)?$') {
  $packVersion = $matches[1] + $matches[2]
  Write-Debug "Version for filename : $packVersion"
}
$packFileName = "$packageId.$packVersion.nupkg"
Write-Debug "Package name : $packFileName"
choco push $($packFileName) --source https://push.chocolatey.org/

Read-Host "Finished"
