﻿<#
.SYNOPSIS
Configure Winget to daily update installed apps.

.DESCRIPTION
Install powershell scripts and scheduled task to daily run Winget upgrade and notify connected users.
Possible to exclude apps from auto-update by adding the winget ID to the excluded_apps.txt file.
Customised from work by https://github.com/Romanitho/Winget-AutoUpdate

.PARAMETER Silent
Install DA-AppUpdater and prerequisites silently

.PARAMETER InstallPath
Specify DA-AppUpdater installation location. Default: %ProgramData%\DA-AppUpdater\

.PARAMETER DoNotUpdate
Do not run DA-AppUpdater after installation. By default, DA-AppUpdater is run just after installation.

.PARAMETER DisableDAAUAutoUpdate
Disable DA-AppUpdater update checking. By default, DAAU will auto update if new release is available on Github.

.PARAMETER DisableDAAUPreRelease
Disable DA-AppUpdater update checking for releases marked as "pre-release". By default, DAAU will auto update to stable releases.

.PARAMETER UseWhiteList
Use White List instead of Black List. This setting will not create the "exclude_apps.txt" but instead "include_apps.txt"

.EXAMPLE
.\Install-DAAppUpdater.ps1 -Silent -DoNotUpdate

.EXAMPLE
.\winget-install-and-update.ps1 -Silent -UseWhiteList -DoNotUpdate
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$False)] [Alias('S')] [Switch] $Silent = $false,
    [Parameter(Mandatory=$False)] [Alias('Path')] [String] $DAAUPath = "$env:ProgramData\DA-AppUpdater",
    [Parameter(Mandatory=$False)] [Switch] $DoNotUpdate = $false,
    [Parameter(Mandatory=$False)] [Switch] $DisableDAAUAutoUpdate = $false,
    [Parameter(Mandatory=$False)] [Switch] $DisableDAAUPreRelease = $false,
    [Parameter(Mandatory=$False)] [Switch] $UseWhiteList = $false
)

<# FUNCTIONS #>
function Start-DALogging {
    $DALogsFolder = "$env:systemdrive\ProgramData\Doherty Associates\Logs\"
    $LogFile = "DAAppUpdater-$env:COMPUTERNAME.log"
    
    # Create DA Directories
    Write-Host "Creating Tech Directory"
    New-Item -ItemType "Directory" -Path "$env:systemdrive\Tech" -Force -ErrorAction SilentlyContinue
    Write-Host "Creating Temp Directory"
    New-Item -ItemType "Directory" -Path "$env:systemdrive\Temp" -Force -ErrorAction SilentlyContinue
    # Create ProgramData\Doherty Associates Subfolders
    Write-Host "Creating ProgramData\Doherty Associates Directory and Sub-Folders"
    New-Item -ItemType "Directory" -Path "$env:systemdrive\ProgramData\Doherty Associates\" -Force -ErrorAction SilentlyContinue
    New-Item -ItemType "Directory" -Path "$env:systemdrive\ProgramData\Doherty Associates\Logs\" -Force -ErrorAction SilentlyContinue
    New-Item -ItemType "Directory" -Path "$env:systemdrive\ProgramData\Doherty Associates\Scripts\" -Force -ErrorAction SilentlyContinue
    New-Item -ItemType "Directory" -Path "$env:systemdrive\ProgramData\Doherty Associates\Installers\" -Force -ErrorAction SilentlyContinue
    
    # Set transcript logging path
    Start-Transcript -path $DALogsFolder\$LogFile -Append
    Write-Host "Current script timestamp: $(Get-Date -f yyyy-MM-dd_HH-mm)"
}

function Confirm-VCPlusPlusPrereq {
    #Check if Visual C++ 2019 or 2022 installed
    Write-Host "Checking if Winget is installed" -ForegroundColor Yellow
    $Visual2019 = "Microsoft Visual C++ 2015-2019 Redistributable*"
    $Visual2022 = "Microsoft Visual C++ 2015-2022 Redistributable*"
    $VCPath = Get-Item HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*, HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* | Where-Object {$_.GetValue("DisplayName") -like $Visual2019 -or $_.GetValue("DisplayName") -like $Visual2022}
    
    If (!($VCPath) -and $Silent.IsPresent) {
        Try{
            Write-Host "Downloading Visual C++ Redistributbles..."
            $VCx86URL = "https://aka.ms/vs/17/release/VC_redist.x86.exe"
            $VCx64URL = "https://aka.ms/vs/17/release/VC_redist.x64.exe"
            $WebClient=New-Object System.Net.WebClient
            $WebClient.DownloadFile($VCx86URL, "$PSScriptRoot\VC_redist.x86.exe")
            $WebClient.DownloadFile($VCx64URL, "$PSScriptRoot\VC_redist.x64.exe")
            Write-Host "Installing VC_redist.x86.exe..."
            Start-Process -FilePath "$PSScriptRoot\VC_redist.x86.exe" -Args "/quiet /norestart" -Wait
            Write-Host "Installing VC_redist.x64.exe..."
            Start-Process -FilePath "$PSScriptRoot\VC_redist.x64.exe" -Args "/quiet /norestart" -Wait
            Remove-Item $VCx86Installer -ErrorAction Ignore
            Remove-Item $VCx64Installer -ErrorAction Ignore
            Write-Host "MS Visual C++ 2015-2022 installed successfully" -ForegroundColor Green
        }
        Catch {
            Write-Host "MS Visual C++ 2015-2022 installation failed" -ForegroundColor Red
            Start-Sleep 3
        }
    }
    Else {
    Write-Host "MS Visual C++ 2015-2022 already installed" -ForegroundColor Green
    }
}

function Confirm-WinGetPrereq {
    Write-Host "Checking if Winget is installed" -ForegroundColor Yellow
    $TestWinGet = Get-AppxProvisionedPackage -Online | Where-Object {$_.DisplayName -eq "Microsoft.DesktopAppInstaller"}
    
    If([Version]$TestWinGet.Version -gt "2022.213.0.0") {
        Write-Host "WinGet is Installed" -ForegroundColor Green
        Return $Script:WingetExists
    }
    Else {
        Write-Verbose "WinGet not Installed. Running installer"
        Install-WinGet
    }
}

function Install-WinGet {
        #Download WinGet MSIXBundle
        Write-Host "Downloading latest WinGet version..."
        $WinGetURL = "https://aka.ms/getwinget"
        $WebClient=New-Object System.Net.WebClient
        $WebClient.DownloadFile($WinGetURL, ".\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle")
    
        #Install WinGet MSIXBundle
        Write-Host "Installing MSIXBundle for App Installer..."
        Add-AppxProvisionedPackage -Online -PackagePath ".\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle" -SkipLicense
    
        #Check Package Install
        Write-Host "Checking Package Install"
        $TestWinGet = Get-AppxProvisionedPackage -Online | Where-Object {$_.DisplayName -eq “Microsoft.DesktopAppInstaller”}
            If ($TestWinGet.DisplayName) {
                Write-Host "WinGet Installed" -ForegroundColor Green
                Remove-Item -Path ".\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle" -Force -ErrorAction Continue
                Return $Script:WingetExists
            }
            Else {
                Write-Host "WinGet Not Installed"
                Exit 1618 #Retry
            }
}

function Invoke-MSStoreUpdate {
    Write-Host "Attempting to force a Microsoft Store Update"
    Get-CimInstance -Namespace "Root\cimv2\mdm\dmmap" -ClassName "MDM_EnterpriseModernAppManagement_AppManagement01" | Invoke-CimMethod -MethodName UpdateScanMethod
}

function Install-DAAppUpdater {
    Try{
        #Copy files to install location
        If (!(Test-Path $DAAUPath)) {
            New-Item -ItemType Directory -Force -Path $DAAUPath
        }
        Copy-Item -Path "$PSScriptRoot\DA-AppUpdater\*" -Destination $DAAUPath -Recurse -Force -ErrorAction SilentlyContinue

        #Set apps whitelist or blacklist
        If ($UseWhiteList) {
            If (Test-Path "$PSScriptRoot\included_apps.txt"){
                Copy-Item -Path "$PSScriptRoot\included_apps.txt" -Destination $DAAUPath -Recurse -Force -ErrorAction SilentlyContinue
            }
            Else{
                New-Item -Path $DAAUPath -Name "included_apps.txt" -ItemType "file" -ErrorAction SilentlyContinue
            }
        }
        Else {
            Copy-Item -Path "$PSScriptRoot\excluded_apps.txt" -Destination $DAAUPath -Recurse -Force -ErrorAction SilentlyContinue
        }

        # Set regkeys for notification name and icon
        & reg add "HKCR\AppUserModelId\Windows.SystemToast.DAAU.Notification" /v DisplayName /t REG_EXPAND_SZ /d "Doherty App Updater" /f | Out-Null
        & reg add "HKCR\AppUserModelId\Windows.SystemToast.DAAU.Notification" /v IconUri /t REG_EXPAND_SZ /d $DAAUPath\icons\DAToastIcon.png /f | Out-Null

        # Settings for the scheduled task for Updates
        $taskAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -File `"$($DAAUPath)\winget-upgrade.ps1`""
        $taskTrigger1 = New-ScheduledTaskTrigger -AtLogOn
        $taskTrigger2 = New-ScheduledTaskTrigger  -Daily -At 6AM
        $taskUserPrincipal = New-ScheduledTaskPrincipal -UserId S-1-5-18 -RunLevel Highest
        $taskSettings = New-ScheduledTaskSettingsSet -Compatibility Win8 -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit 03:00:00

        # Set up the task, and register it
        $task = New-ScheduledTask -Action $taskAction -Principal $taskUserPrincipal -Settings $taskSettings -Trigger $taskTrigger2,$taskTrigger1
        Register-ScheduledTask -TaskName 'DA-AppUpdater'-InputObject $task -Force | Out-Null

        # Settings for the scheduled task for Notifications
        $taskAction = New-ScheduledTaskAction -Execute "wscript.exe" -Argument "`"$($DAAUPath)\Invisible.vbs`" `"powershell.exe -ExecutionPolicy Bypass -File `"`"`"$($DAAUPath)\winget-notify.ps1`"`""
        $taskUserPrincipal = New-ScheduledTaskPrincipal -GroupId S-1-5-11
        $taskSettings = New-ScheduledTaskSettingsSet -Compatibility Win8 -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit 00:05:00

        # Set up the task, and register it
        $task = New-ScheduledTask -Action $taskAction -Principal $taskUserPrincipal -Settings $taskSettings
        Register-ScheduledTask -TaskName 'DA-AppUpdater-Notify'-InputObject $task -Force | Out-Null

        # Install config file
        [xml]$ConfigXML = @"
<?xml version="1.0"?>
<app>
    <DAAUAutoUpdate>$(!($DisableDAAUAutoUpdate))</DAAUAutoUpdate>
    <DAAUPreRelease>$(!($DisableDAAUPreRelease))</DAAUPreRelease>
    <UseDAAUWhiteList>$UseWhiteList</UseDAAUWhiteList>
</app>
"@
        $ConfigXML.Save("$DAAUPath\config\config.xml")

        Write-Host "`nInstallation succeeded!" -ForegroundColor Green
        Start-Sleep 1
        
        #Run Winget Immediately
        Start-DAAppUpdater
    }
    Catch{
        Write-host "`nInstallation failed! Run me with admin rights" -ForegroundColor Red
        Start-sleep 1
        Return $False
    }
}

function Set-DAAUNotificationPriority{
    $LoggedInUser = Get-WMIObject -class Win32_ComputerSystem | Select-Object -ExpandProperty username
    If($LoggedInUser -contains "defaultuser0") {
        Write-Host "Autopilot deployment defaultuser0 detected. Loading Default User registry hive."
        reg load HKU\Default C:\Users\Default\NTUSER.DAT
        Write-Host "Creating default user notification registry keys"
        New-Item -Path "HKU:\Default\SOFTWARE\Microsoft\Windows\CurrentVersion\Notifications\Settings\Windows.SystemToast.DAAU.Notification"
        reg unload HKU\Default
    }
    Else {
        $objUser = New-Object System.Security.Principal.NTAccount($LoggedInUser)
        $strSID = $objUser.Translate([System.Security.Principal.SecurityIdentifier])
        Write-Host "Standard deployment detected. Adding registry keys to logged-in user hive."
        New-PSDrive -Name "HKU" -PSProvider "Registry" -Root "HKEY_USERS"
        Set-Location -Path "HKU:\$($strSID.Value)\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings"
        New-Item -Path "HKU:\$($strSID.Value)\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings" -Name "Windows.SystemToast.DAAU.Notification" -Force
        New-ItemProperty "HKU:\$($strSID.Value)\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings\Windows.SystemToast.DAAU.Notification" -Name "Rank" -Value "99" -PropertyType Dword -Force
        Remove-PSDrive -Name "HKU" -Force -ErrorAction Continue
    }
}

function Start-DAAppUpdater {
    #If -DoNotUpdate is true, skip.
    If (!($DoNotUpdate)){
        #If -Silent, run Winget-AutoUpdate now
        If ($Silent){
            $RunWinget = 1
        }
        #If running interactively, ask for WingetAutoUpdate
        Else {
            $MsgBoxTitle = "DA-AppUpdater"
            $MsgBoxContent = "Would you like to run DA-AppUpdater now?"
            $MsgBoxTimeOut = 60
            $MsgBoxReturn = (New-Object -ComObject "Wscript.Shell").Popup($MsgBoxContent,$MsgBoxTimeOut,$MsgBoxTitle,4+32)
            If ($MsgBoxReturn -ne 7) {
                $RunWinget = 1
            }
            Else {
                $RunWinget = 0
            }
        }
        If ($RunWinget -eq 1){
        Try {
            Write-host "Running DA-AppUpdater..." -ForegroundColor Yellow
            Get-ScheduledTask -TaskName "DA-AppUpdater" -ErrorAction SilentlyContinue | Start-ScheduledTask -ErrorAction SilentlyContinue
            While ((Get-ScheduledTask -TaskName "DA-AppUpdater").State -ne  'Ready') {
                Start-Sleep 1
            }
        }
        Catch {
            Write-host "Failed to run DA-AppUpdater..." -ForegroundColor Red
        }
    }
    }
    Else {
    Write-host "Skip running DA-AppUpdater"
    }
}


<# MAIN #>
Start-DALogging

Write-Host "`n"
Write-Host "###################################"
Write-Host "#                                 #"
Write-Host "#          DA App Updater         #"
Write-Host "#                                 #"
Write-Host "###################################"
Write-Host "`n"
Write-host "Installing to $DAAUPath\"

Try {
    #Attempt MS Store Update
    Invoke-MSStoreUpdate
    Start-Sleep -Seconds 60

    #Check Pre-Reqs
    Confirm-VCPlusPlusPrereq
    Confirm-WinGetPrereq

    #Start Install
    If ($Script:WingetExists -eq $True) {
        Write-Host "Winget Installed - Version $($WingetInstall.Version)"
        Write-Host "Installing DA App Updater"
        Install-DAAppUpdater
        Write-Host "Configuring Notification Priority"
        Set-DAAUNotificationPriority
        Write-Host "Install complete. Exiting with success code"
        Start-Sleep 3
        Exit 0
    }
    Else {
        Write-Error "Winget is not installed. Exiting with retry code"
        Start-Sleep 3
        Exit 1618 
        }
}
Catch {
    Write-Error "$_.Exception.Message"
    Start-Sleep 3
    Exit 1618 
}

Stop-Transcript