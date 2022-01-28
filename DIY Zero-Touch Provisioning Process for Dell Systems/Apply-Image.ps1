#Image Apply
#Updated: 1/5/22, bpeppin
$version = "1.5"
Add-Type -AssemblyName PresentationCore, PresentationFramework

#Variable Section
$date = (Get-Date).ToString('yyyy-MM-dd')
$LogFilePath = $env:TEMP
$logfilename = "$LogFilePath\$date" + "_ImageApply.log"
$dest = "C:\Dell"
$stopwatch = [system.diagnostics.stopwatch]::StartNew()
$data = (get-volume | Where FileSystemLabel -eq "DATA").DriveLetter + ":"
$boot = (get-volume | Where FileSystemLabel -eq "BOOT").DriveLetter + ":"
$imagefile = $data + "\sources\install.wim"

#Functions
function Write-Log {

    Param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [switch]$fail
    )
	
    If ((Test-Path $LogFilePath) -eq $false) {
        mkdir $LogFilePath
    }
	
    $time = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $time + '...' + $Message | Out-File -FilePath $logfilename -Append
    if ($fail) {
        Write-Host $Message -ForegroundColor Red
    }
    else {
        Write-Host $Message
    }

}

function Driver-Download {
    #Download Catalog file
    ipconfig

    $usb = (get-volume | Where FileSystemLabel -eq "DATA").DriveLetter + ":"
    $source = "http://downloads.dell.com/catalog/DriverPackCatalog.cab"
    $catalog = "$usb\Dell\DriverPackCatalog.cab"
    Write-Log "Downloading driver catalog file from $source"
    if (!(Test-Path "$usb\Dell\")) {
        mkdir "$usb\Dell\"
    }
    try {
        Invoke-WebRequest -URi $source -OutFile $catalog -Verbose
    }
    catch {
        Write-Log -Message "Error downloading dell catalog file. Error: $PSItem " -fail
        exit
                
    }
    #parse Catalog file
    $catalogXMLFile = "$usb\Dell\DriverPackCatalog.xml"
    Write-Log "Expanding catalog cab file..."
    try {
        EXPAND $catalog $catalogXMLFile
    }
    catch {
        Write-Log "Error Expanding catalog cab file. Error: $PSItem" -fail
        exit
    }


    #Find Model Info
    [xml]$catalogXMLDoc = Get-Content $catalogXMLFile
    $Model = $((Get-WmiObject -Class Win32_ComputerSystem).Model).Trim()
    Write-Log "Model: $model"
    write-Log "Parsing catalog xml to get model specific driver CAB and download URL"
    $cabSelected = $catalogXMLDoc.DriverPackManifest.DriverPackage | ? { ($_.SupportedSystems.Brand.Model.name -eq "$model") -and ($_.type -eq "Win") -and ($_.SupportedOperatingSystems.OperatingSystem.osCode -eq "Windows10" ) } | sort type

    #Cab Information
    $cabsource = "http://" + $catalogXMLDoc.DriverPackManifest.baseLocation + "/" + $cabSelected.path
    Write-Log "Source Cab download location: $cabsource"
    $Filename = [System.IO.Path]::GetFileName($cabsource)

    $folder = $usb + "\Dell\$model"
    $destination = $usb + "\Dell\$model\" + $Filename

    Write-Log "Destination download location: $destination"

    if (Test-Path $destination) {
        Write-Log "$destination file already exists. Checking file hash"
        $hash = Get-FileHash $destination -Algorithm MD5
        Write-Log "Original MD5 hash: $(@($cabSelected.hashMD5))"
        Write-Log "Current MD5 file hash: $(@($hash.hash))"

        if ($hash.hash -ne $cabSelected.hashMD5) {
            try {
                Write-Log "Hashes don't match, redownloading Dell Driver pack for $model..."
                Invoke-WebRequest -URi $cabsource -OutFile $destination -UseBasicParsing
                $hash = Get-FileHash $destination -Algorithm MD5
                Write-Log "Updated file hash: $(@($hash.hash))"
            }
            catch {
                write-log "Ran into an issue: $PSItem" -fail
                exit
            }

        }
        else {
            Write-Log "Hashes match. No need to re-download."
        }

    }
    else {
        if (!(Test-Path $folder)) {
            mkdir $folder
        }
        try {
            Write-Log "Driver cab missing from USB. Downloading Dell Driver pack for $model..."
            Invoke-WebRequest -URi $cabsource -OutFile $destination -UseBasicParsing
        }
        catch {
            write-log "Ran into an issue: $PSItem" -fail
            exit
        }


    }

    <#     Write-Log "Copying cab file to OS drive"
    try {
        echo f | xcopy $destination 'W:\Dell\DriverPack.cab' /f /s /y
    }
    catch {
        Write-log "Error copy cab file"
    } #>
    $global:foldermodel = "W:\Drivers"
    if (!(test-path "$global:foldermodel")) {
        Write-Log "Extracting Dell Cab to C:\Drivers" #Note it's W:\ in WinPE
        mkdir $global:foldermodel | out-null
        EXPAND $destination -F:* $global:foldermodel | Out-Null
    }


}


Write-Log "Script Version: $version"
#Set High Perf
try {
    Write-Log "Setting high performance mode"
    powercfg /s 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c
}
catch {
    write-log "Ran into an issue: $PSItem" -fail
    exit
}

#https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/oem-deployment-of-windows-desktop-editions-sample-scripts?preserve-view=true&view=windows-10#-createpartitions-uefitxt
Write-Host "Formatting Drive"
$command = @"
select disk 0
clean
convert gpt
create partition efi size=100
format quick fs=fat32 label="System"
assign letter="S"
create partition msr size=16
create partition primary 
shrink minimum=700
format quick fs=ntfs label="Windows"
assign letter="W"
create partition primary
format quick fs=ntfs label="Recovery"
assign letter="R"
set id="de94bba4-06d1-4d40-a16a-bfd50179d6ac"
gpt attributes=0x8000000000000001
list volume
exit
"@
$command | Diskpart

#Run Dell Specific Items
$Make = (Get-WmiObject -Class Win32_ComputerSystem).Manufacturer
if ($make -like "Dell*") {
    Driver-Download
    #CCTK

    cd "X:\Provisioning\"

    Write-Log "Applying CCTK. Log also set to C:\Temp\cctk.log"
    # ThunderBolt Docks Connection Options
    .\cctk.exe --thunderbolt=enable -l=X:\Windows\Temp\cctk.log
    .\cctk.exe --thunderboltbootsupport=enable -l=X:\Windows\Temp\cctk.log
    .\cctk.exe --thunderboltprebootmodule=enable -l=X:\Windows\Temp\cctk.log
    .\cctk.exe --thunderboltsecuritylevel=nosecurity -l=X:\Windows\Temp\cctk.log
    .\cctk.exe --MacAddrPassThru=SystemUnique

    # Disable Legacy Boot, enable UEFI
    .\cctk.exe bootorder --activebootlist=uefi -l=X:\Windows\Temp\cctk.log
    .\cctk.exe --legacyorom=disable -l=X:\Windows\Temp\cctk.log
    .\cctk.exe --secureboot=enable -l=X:\Windows\Temp\cctk.log
    .\cctk.exe --uefinwstack=enable -l=X:\Windows\Temp\cctk.log
    .\cctk.exe --EmbSataRaid=Ahci -l=X:\Windows\Temp\cctk.log

    # USB settings
    .\cctk.exe --usbpowershare=enabled -l=X:\Windows\Temp\cctk.log

    # Set SMART Error Checking
    .\cctk.exe --smarterrors=enable -l=X:\Windows\Temp\cctk.log

    # Check TPM, enable and activate - a password is set and then removed in order to change these setting
    .\cctk.exe --setuppwd=password -l=X:\Windows\Temp\cctk.log
    .\cctk.exe --tpmsecurity=enabled --valsetuppwd=password -l=X:\Windows\Temp\cctk.log
    .\cctk.exe --tpmactivation=activate --valsetuppwd=password -l=X:\Windows\Temp\cctk.log
    .\cctk.exe --setuppwd= --valsetuppwd=password -l=X:\Windows\Temp\cctk.log

    # Image Performance Settings
    .\cctk.exe --BlockSleep=Enabled -l=X:\Windows\Temp\cctk.log
    .\cctk.exe --Fastboot=Minimal -l=X:\Windows\Temp\cctk.log
    .\cctk.exe --Speedstep=Enabled -l=X:\Windows\Temp\cctk.log
    .\cctk.exe --TurboMode=Enabled -l=X:\Windows\Temp\cctk.log
    .\cctk.exe --CStatesCtrl=Disabled -l=X:\Windows\Temp\cctk.log



}

#Apply Image - Enterprise is Index 3
try {
    Write-Log "Applying Image"
    dism /Apply-Image /ImageFile:$imagefile /Index:3 /ApplyDir:W:\
}
catch {
    write-log "Ran into an issue: $PSItem" -fail
    exit
}

if (!(Test-Path "W:\Temp")) {
    mkdir "W:\Temp"
}

#Apply Drivers
if ($make -like "Dell*") {
    try {
        Write-Log "Applying Drivers"
        dism.exe /image:W:\ /Add-Driver /driver:$global:foldermodel /recurse
    }
    catch {
        write-log "Ran into an issue: $PSItem"  -fail
        exit
    }
}

# Copy boot files to the System partition ==

try {
    Write-Log "Copying boot files"
    W:\Windows\System32\bcdboot W:\Windows /s S:
}
catch {
    write-log "Ran into an issue: $PSItem" -fail
    exit
}


# Copy the Windows RE image to the    Windows RE Tools partition
try {
    Write-Log "Copying WinRE" 
    md R:\Recovery\WindowsRE
    xcopy /h W:\Windows\System32\Recovery\Winre.wim R:\Recovery\WindowsRE\
}
catch {
    write-log "Ran into an issue: $PSItem" -fail
    exit
}

# Register the location of the recovery tools 
try {
    Write-Log "Setting location of recovery tools"
    W:\Windows\System32\Reagentc /Setreimage /Path R:\Recovery\WindowsRE /Target W:\Windows | out-null
}
catch {
    write-log "Ran into an issue: $PSItem" -fail
    exit
}


#Copying Unattend.xml
Write-Log "Copying Unattend.xml to c:\windows\system32\sysprep"
$unattend = "$boot\unattend.xml"
try {
    Copy-Item -Path $unattend -Destination "W:\windows\system32\sysprep" -Force -ErrorAction Stop
}
catch {
    write-log "Ran into an issue: $PSItem" -fail
    exit
}

#Copying .net Files
mkdir "W:\Temp\sxs" | out-null
$path = "$data" + '\sources\sxs' 
Try {
    write-log "Copying .Net files..."
    Copy-Item -Path "$path\*" -Destination "W:\Temp\sxs" -Force -Recurse -ErrorAction Stop
}
catch {
    write-log "Ran into an issue: $PSItem" -fail
    exit
}

$stopwatch.Stop()
$ts = $stopwatch.Elapsed
$elapsedTime = [string]::Format( "{0:00} min. {1:00}.{2:00} sec.", $ts.Minutes, $ts.Seconds, $ts.Milliseconds / 10 )
Write-log "Time Elapsed:  $elapsedTime"


#Coping Log Files
try {
    Write-Log "Copying logs to C:\Temp"
    copy-item "$env:TEMP\*" "W:\Temp"-Force -Recurse -ErrorAction Stop
}
catch {
    write-log "Ran into an issue: $PSItem" -fail
    exit
}

wpeutil reboot