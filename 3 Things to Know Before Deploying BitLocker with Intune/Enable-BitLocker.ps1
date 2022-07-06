 # Author: Brooks Peppin, www.brookspeppin.com, @brookspeppin
 # Updated: 7/6/22

$LogFilePath = "C:\Temp"

$logfilename = "$LogFilePath\BitLocker_Encryption.log"

 

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

 

$BLinfo = Get-Bitlockervolume -MountPoint $env:systemdrive | Select *

Write-Log "Current BL Status: $(@($blinfo.VolumeStatus)), $(@($blinfo.EncryptionMethod))"

if ($blinfo.EncryptionMethod -ne "XtsAes256") {

    #Decrypting in case the system is auto-encrypted with a different method than the one I want
    Write-Log "Disabling Encryption"

    Try {

 

        Disable-BitLocker -MountPoint $env:SystemDrive -ErrorAction SilentlyContinue

        do {

            $BitLockerOSVolume = Get-BitLockerVolume -MountPoint $env:SystemDrive

            Start-Sleep -Seconds 15

            $BitLockerOSVolume.EncryptionPercentage

        }

        until ($BitLockerOSVolume.EncryptionPercentage -eq 0)

    }    

    catch {

        write-log "Ran into an issue: $PSItem"  -fail


    }

}

 

try {

    # Check if TPM chip is currently owned, if not take ownership

    $TPMClass = Get-WmiObject -Namespace "root\cimv2\Security\MicrosoftTPM" -Class "Win32_TPM"

    $IsTPMOwned = $TPMClass.IsOwned().IsOwned

    if ($IsTPMOwned -eq $false) {

        Write-Log "TPM chip is currently not owned, value from WMI class method 'IsOwned' was: $($IsTPMOwned)"

       

        # Generate a random pass phrase to be used when taking ownership of TPM chip

        $NewPassPhrase = (New-Guid).Guid.Replace("-", "").SubString(0, 14)

 

        # Construct owner auth encoded string

        $NewOwnerAuth = $TPMClass.ConvertToOwnerAuth($NewPassPhrase).OwnerAuth

 

        # Attempt to take ownership of TPM chip

        $Invocation = $TPMClass.TakeOwnership($NewOwnerAuth)

        if ($Invocation.ReturnValue -eq 0) {

            Write-Log  "TPM chip ownership was successfully taken"

        }

        else {

            Write-Log "Failed to take ownership of TPM chip, return value from invocation: $($Invocation.ReturnValue)"

        }

    }

    else {

        Write-Log "TPM chip is currently owned, will not attempt to take ownership"

    }

}

catch [System.Exception] {

    write-log "Ran into an issue: $PSItem"  -fail

}

 

try {

    Write-Log "Enabling BitLocker, TPM Protector and Recovery Password Protector"
        #This ensure that the correct encryption type is also set in the registry. The Intune BitLocker profile will also set this same key. 
    #Prevent hardware level auto-encryption
    REG ADD "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\FVE" /V OSAllowedHardwareEncryptionAlgorithms /T REG_DWORD /D 0 /F

    #AES-XTS256
    REG ADD "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\FVE" /V EncryptionMethodWithXtsOs /T REG_DWORD /D 7 /F

    #This will add TPM + Recovery Password Protector
    Enable-BitLocker -MountPoint $env:SystemDrive -UsedSpaceOnly -SkipHardwareTest -RecoveryPasswordProtector

    sleep 5

    $BLinfo = Get-Bitlockervolume -MountPoint $env:systemdrive | Select *

    Write-Log "Current BL Status: $(@($blinfo.MountPoint)), $(@($blinfo.VolumeStatus)), $(@($blinfo.EncryptionMethod)),$(@($blinfo.KeyProtector))"

}

catch {

    write-log "Ran into an issue: $PSItem"  -fail

}

 