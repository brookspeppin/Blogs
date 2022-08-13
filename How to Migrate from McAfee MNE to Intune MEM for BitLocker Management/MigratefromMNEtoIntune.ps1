 

#region declarations

$DriveLetter = $env:SystemDrive

$date = (Get-Date).ToString('yyyy-MM-dd')

$LogFilePath = "c:\Temp"

$logfilename = "$LogFilePath\IntuneBitLockerEscrow.log"

$registryStamp = "HKLM:\SOFTWARE\IT\Intune"

 

#endregion declarations

#region functions

function Write-Log {

 

    Param (

        [Parameter(Mandatory = $true)]

        [string]$Message,

        [switch]$fail,

        [string]$color

    )

   

    If ((Test-Path $LogFilePath) -eq $false) {

        mkdir $LogFilePath | out-null

    }

   

    $time = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")

    $time + '...' + $Message | Out-File -FilePath $logfilename -Append

    if ($fail) {

        Write-Host $Message -ForegroundColor Red

    }

    else {

        if ($color) {

            Write-Host $Message  -ForegroundColor $color

        }

        else {

            Write-Host $Message

        }

       

    }

 

}

 

#endregion functions

 

#region execute

 

[string[]]$ProviderGUIDs = @()

 

#region Get MS DM Provider GUID

#Gets enrollment registry keys where the value is MS DM Server.  This will find the MDM/Intune enrollment GUID that we will use for all of the other steps.

$ProviderRegistryPath = "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Enrollments"

$ProviderPropertyName = "ProviderID"

$ProviderPropertyValue = "MS DM Server"

$ProviderGUID = (Get-ChildItem -Path Registry::$ProviderRegistryPath -Recurse -ErrorAction SilentlyContinue | ForEach-Object { if ((Get-ItemProperty -Name $ProviderPropertyName -Path $_.PSPath -ErrorAction SilentlyContinue | Get-ItemPropertyValue -Name $ProviderPropertyName -ErrorAction SilentlyContinue) -match $ProviderPropertyValue) { $_ } }).PSChildName

if ($ProviderGUID) {

    $ProviderGUIDs += $ProviderGUID

    Write-Log "Provider GUID Found $($ProviderGUID). Intune Enrolled."

    write-log  "Checking if Bitlocker Profile is applied..."

    if (Test-Path "HKLM:\SOFTWARE\Microsoft\PolicyManager\Providers\$ProviderGUID\default\Device\BitLocker") {

        write-log  "BitLocker profile applied. Backing up key to Azure."

        $BLV = Get-BitLockerVolume -MountPoint "C:" | select *

        [array]$ID = ($BLV.KeyProtector | Where-Object { $_.KeyProtectorType -eq 'RecoveryPassword' }).KeyProtectorId

        BackupToAAD-BitLockerKeyProtector -MountPoint "C:" -KeyProtectorId $ID[0]

       

        #Repairing MNE Service

        $MNE = get-service "McAfee Management of Native Encryption Service" | select *

 

        if($MNE.StartType -ne "Automatic")

        {

        Write-Log "MNE Service was not set to Automatic...correcting."

        Set-Service -name $MNE.Name -StartupType Automatic

        }

        if($MNE.Status -ne "Running")

        {

        Write-Log "MNE Service was not running...correcting."

        Start-Service $MNE.Name

        }

 

        #Tag System Intune Enrolled

        Start-Process "C:\Program Files\McAfee\Agent\maconfig.exe" -ArgumentList "-custom -prop4 Intune-Managed" -Wait -RedirectStandardOutput c:\temp\McafeeBitLockerTag.log

        Sleep -Seconds 10

        #Collect/Send Props

        Start-Process "C:\Program Files\McAfee\Agent\maconfig.exe" -ArgumentList "-p" -Wait

        Sleep -Seconds 60

        #Collect/Send Props

        Start-Process "C:\Program Files\McAfee\Agent\maconfig.exe" -ArgumentList "-p" -Wait

 

        #Resyncing Intune

        Get-ScheduledTask | ? { $_.TaskName -eq "Schedule to run OMADMClient by client" } | Start-ScheduledTask

        Sleep -Seconds 60

        Get-ScheduledTask | ? { $_.TaskName -eq "PushLaunch" } | Start-ScheduledTask

 

        #Stamping Registry


        Write-Log "Applying registry stamp in $registryStamp "
        $time = get-date

        if (!(Test-Path $registryStamp )) { New-Item -Path $registryStamp  -Force | Out-Null }

        New-ItemProperty -Path $registryStamp  -Name MigratedfromMNE -Value 'True' -PropertyType string -Force | Out-Null

        New-ItemProperty -Path $registryStamp  -Name MigratedDate -Value "$time" -PropertyType string -Force | Out-Null

    }

 

}

else {

    Write-Log "No Provider GUID Found. Not Intune Enrolled."

}




#endregion execute