﻿<# FUNCTIONS #>

function Init {
    #Var
    $Script:WorkingDir = $PSScriptRoot

    #Log Header
    $Log = "##################################################`n#     CHECK FOR APP UPDATES - $(Get-Date -Format 'dd/MM/yyyy')`n##################################################"
    $Log | Write-host
    try{
        #Logs initialisation
	[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
        $LogPath = "$WorkingDir\logs"
        if (!(Test-Path $LogPath)){
            New-Item -ItemType Directory -Force -Path $LogPath
        }
        #Log file
        $Script:LogFile = "$LogPath\updates.log"
        $Log | out-file -filepath $LogFile -Append
    }
    catch{
        #Logs initialisation
        $LogPath = "$env:LOCALAPPDATA\DA-AppUpdater\logs"
        if (!(Test-Path $LogPath)){
            New-Item -ItemType Directory -Force -Path $LogPath
        }
        $Script:LogFile = "$LogPath\updates.log"
        $Log | out-file -filepath $LogFile -Append
    }

    #Get locale file for Notification
    #Default en-GB
    $DefaultLocale = "$WorkingDir\locale\en-GB.xml"
    #Get OS locale
    $Locale = Get-WinSystemLocale
    #Test if OS locale config file exists
    $LocaleFile = "$WorkingDir\locale\$($locale.Name).xml"
    if(Test-Path $LocaleFile){
        [xml]$Script:NotifLocale = Get-Content $LocaleFile -Encoding UTF8 -ErrorAction SilentlyContinue
        $LocaleNotif = "Notification Langugage : $($locale.Name)"
    }
    else{
        [xml]$Script:NotifLocale = Get-Content $DefaultLocale -Encoding UTF8 -ErrorAction SilentlyContinue
        $LocaleNotif = "Notification Langugage : en-GB"
    }
    Write-Log $LocaleNotif "Cyan"
}

function Write-Log ($LogMsg,$LogColor = "White") {
    #Get log
    $Log = "$(Get-Date -UFormat "%T") - $LogMsg"
    #Echo log
    $Log | Write-host -ForegroundColor $LogColor
    #Write log to file
    $Log | Out-File -filepath $LogFile -Append
}

function Start-NotifTask ($Title,$Message,$MessageType,$Balise) {

#Add XML variables
[xml]$ToastTemplate = @"
<toast launch="ms-get-started://redirect?id=apps_action">
    <visual>
        <binding template="ToastImageAndText03">
            <text id="1">$Title</text>
            <text id="2">$Message</text>
            <image id="1" src="$WorkingDir\icons\$MessageType.png" />
        </binding>
    </visual>
    <tag>$Balise</tag>
</toast>
"@

    #Check if running account is system or interactive logon
    $currentPrincipal = [bool](([System.Security.Principal.WindowsIdentity]::GetCurrent()).groups -match "S-1-5-4")
    #if not "Interactive" user, run as system
    if ($currentPrincipal -eq $false){
        #Save XML to File
        $ToastTemplateLocation = "$env:ProgramData\DA-AppUpdater\"
        if (!(Test-Path $ToastTemplateLocation)){
            New-Item -ItemType Directory -Force -Path $ToastTemplateLocation
        }
        $ToastTemplate.Save("$ToastTemplateLocation\notif.xml")

        #Run Notify scheduled task to notify conneted users
        Get-ScheduledTask -TaskName "DA-AppUpdater-Notify" -ErrorAction SilentlyContinue | Start-ScheduledTask -ErrorAction SilentlyContinue
    }
    #else, run as connected user
    else{
        #Load Assemblies
        [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
        [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null

        #Prepare XML
        $ToastXml = [Windows.Data.Xml.Dom.XmlDocument]::New()
        $ToastXml.LoadXml($ToastTemplate.OuterXml)

        #Specify Launcher App ID
        $LauncherID = "Windows.SystemToast.DAAU.Notification"
        
        #Prepare and Create Toast
        $ToastMessage = [Windows.UI.Notifications.ToastNotification]::New($ToastXml)
        $ToastMessage.Tag = $ToastTemplate.toast.tag
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($LauncherID).Show($ToastMessage)
    }

    #Wait for notification to display
    Start-Sleep 3
}

function Test-Network {
    #init
    $timeout = 0
    $ping = $false

    #test connectivity during 30 min then timeout
    Write-Log "Checking internet connection..." "Yellow"
    while (!$ping -and $timeout -lt 1800){
        try{
            Invoke-RestMethod -Uri "https://api.github.com/zen"
            Write-Log "Connected !" "Green"
            return $true
        }
        catch{
            Start-Sleep 10
            $timeout += 10
            Write-Log "Checking internet connection. $($timeout)s." "Yellow"
            #Send Notif if no connection for 5 min
            if ($timeout -eq 300){
                Write-Log "Notify 'No connection'" "Yellow"
                $Title = $NotifLocale.local.outputs.output[0].title
                $Message = $NotifLocale.local.outputs.output[0].message
                $MessageType = "warning"
                $Balise = "connection"
                Start-NotifTask $Title $Message $MessageType $Balise
            }
        }
    }
    Write-Log "Timeout. No internet connection !" "Red"
    #Send Notif if no connection for 30 min
    $Title = $NotifLocale.local.outputs.output[1].title
    $Message = $NotifLocale.local.outputs.output[1].message
    $MessageType = "error"
    $Balise = "connection"
    Start-NotifTask $Title $Message $MessageType $Balise
    return $ping
}

function Get-WingetOutdated {
    class Software {
        [string]$Name
        [string]$Id
        [string]$Version
        [string]$AvailableVersion
    }

    #Get WinGet Location
    $WingetCmd = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($WingetCmd){
        $script:upgradecmd = $WingetCmd.Source
    }
    elseif (Test-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\AppInstallerCLI.exe"){
        #WinGet < 1.17
        $script:upgradecmd = Resolve-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\AppInstallerCLI.exe" | Select-Object -ExpandProperty Path
    }
    elseif (Test-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe"){
        #WinGet > 1.17
        $script:upgradecmd = Resolve-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe" | Select-Object -ExpandProperty Path
    }
    else{
        Write-Log "Winget not installed !"
        return
    }

    #Run winget to list apps and accept source agrements (necessary on first run)
    & $upgradecmd list --accept-source-agreements | Out-Null

    #Get list of available upgrades on winget format
    $upgradeResult = & $upgradecmd upgrade | Out-String

    #Start Convertion of winget format to an array. Check if "-----" exists
    if (!($upgradeResult -match "-----")){
        return
    }

    #Split winget output to lines
    $lines = $upgradeResult.Split([Environment]::NewLine).Replace("¦ ","")

    # Find the line that starts with "------"
    $fl = 0
    while (-not $lines[$fl].StartsWith("-----")){
        $fl++
    }
    
    #Get header line
    $fl = $fl - 2

    #Get header titles
    $index = $lines[$fl] -split '\s+'

    # Line $i has the header, we can find char where we find ID and Version
    $idStart = $lines[$fl].IndexOf($index[1])
    $versionStart = $lines[$fl].IndexOf($index[2])
    $availableStart = $lines[$fl].IndexOf($index[3])
    $sourceStart = $lines[$fl].IndexOf($index[4])

    # Now cycle in real package and split accordingly
    $upgradeList = @()
    For ($i = $fl + 2; $i -le $lines.Length; $i++){
        $line = $lines[$i]
        if ($line.Length -gt ($sourceStart+5) -and -not $line.StartsWith('-')){
            $software = [Software]::new()
            $software.Name = $line.Substring(0, $idStart).TrimEnd()
            $software.Id = $line.Substring($idStart, $versionStart - $idStart).TrimEnd()
            $software.Version = $line.Substring($versionStart, $availableStart - $versionStart).TrimEnd()
            $software.AvailableVersion = $line.Substring($availableStart, $sourceStart - $availableStart).TrimEnd()
            #add formated soft to list
            $upgradeList += $software
        }
    }

    return $upgradeList
}

function Get-ExcludedApps{
    if (Test-Path "$WorkingDir\excluded_apps.txt"){
        return Get-Content -Path "$WorkingDir\excluded_apps.txt"
    }
}

function Start-WAUUpdateCheck{
    #Get AutoUpdate status
    [xml]$UpdateStatus = Get-Content "$WorkingDir\config\config.xml" -Encoding UTF8 -ErrorAction SilentlyContinue
    $AutoUpdateStatus = $UpdateStatus.app.WAUautoupdate
    
    #Check if AutoUpdate is enabled
    if ($AutoUpdateStatus -eq $false){
        Write-Log "WAU Current version: $CurrentVersion. AutoUpdate is disabled." "Cyan"
        return $false
    }
    #If enabled, check online available version
    else{
        #Get Github latest version
        $WAUurl = 'https://api.github.com/repos/DohertyAssociates/DA-AppUpdater/releases/latest'
        $LatestVersion = (Invoke-WebRequest $WAUurl | ConvertFrom-Json)[0].tag_name
        [version]$AvailableVersion = $LatestVersion.Replace("v","")

        #Get current installed version
        [xml]$About = Get-Content "$WorkingDir\config\about.xml" -Encoding UTF8 -ErrorAction SilentlyContinue
        [version]$CurrentVersion = $About.app.version

        #If newer version is avalable, return $True
        if ($AvailableVersion -gt $CurrentVersion){
            Write-Log "DAAU Current version: $CurrentVersion. Version $AvailableVersion is available." "Yellow"
            return $true
        }
        else{
            Write-Log "DAAU Current version: $CurrentVersion. Up to date." "Green"
            return $false
        }
    }
}

function Update-WAU{
    #Get WAU Github latest version
    $WAUurl = 'https://api.github.com/repos/DohertyAssociates/DA-AppUpdater/releases/latest'
    $LatestVersion = (Invoke-WebRequest $WAUurl | ConvertFrom-Json)[0].tag_name

    #Send available update notification
    $Title = $NotifLocale.local.outputs.output[2].title -f "DA-AppUpdater"
    $Message = $NotifLocale.local.outputs.output[2].message -f $CurrentVersion, $LatestVersion.Replace("v","")
    $MessageType = "info"
    $Balise = "DA-AppUpdater"
    Start-NotifTask $Title $Message $MessageType $Balise

    #Run WAU update
    try{
        #Force to create a zip file 
        $ZipFile = "$WorkingDir\DAAU_update.zip"
        New-Item $ZipFile -ItemType File -Force | Out-Null

        #Download the zip 
        $RepoURL="https://github.com/DohertyAssociates/DA-AppUpdater/archive/refs/tags/$($LatestVersion).zip"
        Write-Log "Starting downloading from GitHub Repo"
        $Client = New-Object System.Net.WebClient
        $Client.DownloadFile($RepoURL, $ZipFile)
        Write-Log 'Download finished'

        #Extract Zip File
        Write-Log "Unzipping the DAAU GitHub Repo Zip"
        $location = "$WorkingDir\DAAU_update"
        Expand-Archive -Path $ZipFile -DestinationPath $location -Force
        Get-ChildItem -Path $location -Recurse | Unblock-File
        Write-Log "Unzip finished"
        $TempPath = (Resolve-Path "$location\DohertyAssociates-DA-AppUpdater*\DA-AppUpdater\").Path
        Copy-Item -Path "$TempPath\*" -Destination "$WorkingDir\" -Recurse -Force
        
        #Remove update zip file
        Write-Log "Cleaning temp files"
        Remove-Item -Path $ZipFile -Force -ErrorAction SilentlyContinue
        #Remove update folder
        Remove-Item -Path $location -Recurse -Force -ErrorAction SilentlyContinue

        #Set new version to conf.xml
        [xml]$XMLconf = Get-content "$WorkingDir\config\about.xml" -Encoding UTF8 -ErrorAction SilentlyContinue
        $XMLconf.app.version = $LatestVersion.Replace("v","")
        $XMLconf.Save("$WorkingDir\config\about.xml")

        #Send success Notif
        $Title = $NotifLocale.local.outputs.output[3].title -f "DA-AppUpdater"
        $Message = $NotifLocale.local.outputs.output[3].message -f $LatestVersion
        $MessageType = "success"
        $Balise = "DA-AppUpdater"
        Start-NotifTask $Title $Message $MessageType $Balise

        #Rerun with newer version
        Get-ScheduledTask -TaskName "DA-AppUpdater" -ErrorAction SilentlyContinue | Start-ScheduledTask -ErrorAction SilentlyContinue
        exit
    }
    catch{
        #Send Error Notif
        $Title = $NotifLocale.local.outputs.output[4].title -f "DA-AppUpdater"
        $Message = $NotifLocale.local.outputs.output[4].message
        $MessageType = "error"
        $Balise = "DA-AppUpdater"
        Start-NotifTask $Title $Message $MessageType $Balise
        Write-Log "DAAU Update failed"
    }
}

<# MAIN #>

#Run initialisation
Init

#Check network connectivity
if (Test-Network){
    #Check if WAU is up to date
    $CheckDAAUupdate = Start-WAUUpdateCheck
    #If AutoUpdate is enabled and Update is avalaible, then run WAU update
    if ($CheckDAAUupdate){
        Update-DAAU
    }

    #Get exclude apps list
    $toSkip = Get-ExcludedApps

    #Get outdated Winget packages
    Write-Log "Checking available updates..." "yellow"
    $outdated = Get-WingetOutdated

    #Log list of app to update
    foreach ($app in $outdated){
        #List available updates
        $Log = "Available update : $($app.Name). Current version : $($app.Version). Available version : $($app.AvailableVersion)."
        $Log | Write-host
        $Log | out-file -filepath $LogFile -Append
    }
    
    #Count good update installs
    $InstallOK = 0

    #For each app, notify and update
    foreach ($app in $outdated){

        if (-not ($toSkip -contains $app.Id) -and $($app.Version) -ne "Unknown"){

            #Send available update notification
            Write-Log "Updating $($app.Name) from $($app.Version) to $($app.AvailableVersion)..." "Cyan"
            $Title = $NotifLocale.local.outputs.output[2].title -f $($app.Name)
            $Message = $NotifLocale.local.outputs.output[2].message -f $($app.Version), $($app.AvailableVersion)
            $MessageType = "info"
            $Balise = $($app.Name)
            Start-NotifTask $Title $Message $MessageType $Balise

            #Winget upgrade
            Write-Log "##########   WINGET UPGRADE PROCESS STARTS FOR APPLICATION ID '$($App.Id)'   ##########" "Gray"
                #Run Winget Upgrade command
                & $UpgradeCmd upgrade --id $($app.Id) --all --accept-package-agreements --accept-source-agreements -h | Tee-Object -file $LogFile -Append
                
                #Check if application updated properly
                $CheckOutdated = Get-WingetOutdated
                $FailedToUpgrade = $false
                foreach ($CheckApp in $CheckOutdated){
                    if ($($CheckApp.Id) -eq $($app.Id)) {
                        #If app failed to upgrade, run Install command
                        & $upgradecmd install --id $($app.Id) --accept-package-agreements --accept-source-agreements -h | Tee-Object -file $LogFile -Append
                        #Check if application installed properly
                        $CheckOutdated2 = Get-WingetOutdated
                        foreach ($CheckApp2 in $CheckOutdated2){
                            if ($($CheckApp2.Id) -eq $($app.Id)) {
                                $FailedToUpgrade = $true
                            }      
                        }
                    }
                }
            Write-Log "##########   WINGET UPGRADE PROCESS FINISHED FOR APPLICATION ID '$($App.Id)'   ##########" "Gray"   

            #Notify installation
            if ($FailedToUpgrade -eq $false){   
                #Send success updated app notification
                Write-Log "$($app.Name) updated to $($app.AvailableVersion) !" "Green"
                
                #Send Notif
                $Title = $NotifLocale.local.outputs.output[3].title -f $($app.Name)
                $Message = $NotifLocale.local.outputs.output[3].message -f $($app.AvailableVersion)
                $MessageType = "success"
                $Balise = $($app.Name)
                Start-NotifTask $Title $Message $MessageType $Balise

                $InstallOK += 1
            }
            else {
                #Send failed updated app notification
                Write-Log "$($app.Name) update failed." "Red"
                
                #Send Notif
                $Title = $NotifLocale.local.outputs.output[4].title -f $($app.Name)
                $Message = $NotifLocale.local.outputs.output[4].message
                $MessageType = "error"
                $Balise = $($app.Name)
                Start-NotifTask $Title $Message $MessageType $Balise
            }
		}
        #if current app version is unknown
        elseif($($app.Version) -eq "Unknown"){
            Write-Log "$($app.Name) : Skipped upgrade because current version is 'Unknown'" "Gray"
        }
        #if app is in "excluded list"
        else{
            Write-Log "$($app.Name) : Skipped upgrade because it is in the excluded app list" "Gray"
        }
    }

    if ($InstallOK -gt 0){
        Write-Log "$InstallOK apps updated ! No more update." "Green"
    }
    if ($InstallOK -eq 0){
        Write-Log "No new update." "Green"
    }
}

#End
Write-Log "End of process!" "Cyan"
Start-Sleep 3
