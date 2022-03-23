#Initialisation

function Start-Init {
    #Config console output encoding
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8

    #Log Header
    $Log = "`n##################################################`n#     CHECK FOR APP UPDATES - $(Get-Date -Format 'dd/MM/yyyy')`n##################################################"
    $Log | Write-host

    #Logs initialisation if admin
    try{
        $LogPath = "$WorkingDir\logs"
        if (!(Test-Path $LogPath)){
            New-Item -ItemType Directory -Force -Path $LogPath
        }
        #Log file
        $Script:LogFile = "$LogPath\updates.log"
        $Log | out-file -filepath $LogFile -Append
    }
    #Logs initialisation if non-admin
    catch{
        $LogPath = "$env:USERPROFILE\DA-AppUpdater\logs"
        if (!(Test-Path $LogPath)){
            New-Item -ItemType Directory -Force -Path $LogPath
        }
        $Script:LogFile = "$LogPath\updates.log"
        $Log | out-file -filepath $LogFile -Append
    }
}