<#	
	.NOTES
	===========================================================================
	 Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2018 v5.5.155
	 Created on:   	1/27/2021
	 Created by:   	Brooks Peppin, www.brookspeppin.com
	 Organization: 	
	 Filename:     	Create-Win10-Media
	===========================================================================
	.DESCRIPTION
		Creates Windows 10 bootable USB that supports both UEFI with Secure Boot.
#>
If (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
{
	# Relaunch as an elevated process:
	Start-Process powershell.exe "-File", ('"{0}"' -f $MyInvocation.MyCommand.Path) -Verb RunAs
	exit
}


Write-Host "==================================================================="
Write-Host "================ Windows 10 x64 USB Media Creator ================="
Write-Host "=================== www.brookspeppin.com =========================="
Write-Host "====================Updated Jan 27, 2022==========================="
Write-Host "==================================================================="`n
Write-Host "This script creates automated bootable Windows 10 setup media that "
Write-Host "supports both UEFI with Secure Boot on. It will create 2 partitions"
Write-Host "(1 FAT32 and 1 NTFS) in order to support consistent UEFI booting."`n

Write-Host "Detected mounted ISO..."
$iso = get-volume | where({ $_.DriveType -eq 'CD-ROM' })
if($iso){
	Write-Host "Detected ISO: $(@($iso.DriveLetter)):, $(@($iso.FileSystemLabel)) "
	Write-Host "Is this correct? (y/n)" -foreground "yellow"
	$confirmation = Read-Host
	if ($confirmation -eq 'y')
	{

	}
	else
	{

	}

}else{
	Write-Host "No ISOs detected. Please re-mount and re-run the script." -foreground "yellow"
}

Write-host "Detecting USB drives..."
Get-Disk | where({ $_.BusType -eq 'USB' }) | select Number, FriendlyName, Model, @{ Name = "TotalSize"; Expression = { "{0:N2}" -f ($_.Size/1GB) } } | out-host #Listing drives that ARE USB
Write-host "Please select the correct drive number to format (enter drive number only). For example: 1"
$drivenumber = Read-Host

if($drivenumber -eq "0")
{
	Write-Host "You have selected drive 0, which is generally your internal HD. Double-check to make sure this is correct." -foreground "red"
	Get-Disk | where({ $_.BusType -eq 'USB' }) | select Number, FriendlyName, Model, @{ Name = "TotalSize"; Expression = { "{0:N2}" -f ($_.Size/1GB) } } | out-host #Listing drives that ARE USB
Write-host "Please select the correct drive to USB drive to format (enter drive number only). Enter disk number only. For example: 1 "
	$drivenumber = Read-Host
	
}
Write-host "You have selected the following drive to format."
Write-Host  "Please ensure this is correct as the drive will be completely formatted! " -ForegroundColor Red
Get-Disk $drivenumber | select Number, FriendlyName, Model, @{ Name = "TotalSize"; Expression = { "{0:N2}" -f ($_.Size/1GB) } } | out-host
Write-Host "Is this correct? (y/n)" -foreground "yellow"
$confirmation = Read-Host
if ($confirmation -eq 'y')
{
	write-host "Drive $drivenumber confirmed. Continuing..."
}
else
{
	exit
}
	
	$command = @"
select disk $drivenumber
clean
convert mbr
create partition primary size=1000
create partition primary
select partition 1
online volume
format fs=fat32 quick label=BOOT
assign 
active
select partition 2
format fs=ntfs quick label=DATA
assign  
exit
"@
	$command | Diskpart

$Boot = ((Get-Volume).where({ $_.FileSystemLabel -eq "BOOT" })).DriveLetter + ":"
$Data = ((Get-Volume).where({ $_.FileSystemLabel -eq "DATA" })).DriveLetter + ":"
$ISO_Letter = $iso.DriveLetter + ":"
Write-Host "Copying boot files to BOOT (FAT32) partition"
robocopy $ISO_Letter $Boot /mir /xf install.wim

Write-Host "Copying install.wim DATA (NTFS) partition"
xcopy "$ISO_Letter\sources\install.wim" $data\sources\
Write-Host "Done!" -ForegroundColor Green