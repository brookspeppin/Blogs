#Created by Brooks Peppin, www.brookspeppin.com
#Updated 1/28/22

#Initializing Variables
$dir = "C:\WinPE"
$source = "C:\WinPE\boot.wim"
$mountpath = "C:\WinPE\Mount"

#Creating Directories
if(!(Test-Path $dir)){
mkdir $dir
mkdir $mountpath
mkdir "$dir\WinPE10.0-Drivers"
}

#Download and Install Win11 ADK (Backwards compatible with win10)
#Check for latest URLS here: https://docs.microsoft.com/en-us/windows-hardware/get-started/adk-install
$downloads = "$home\Downloads"
Invoke-WebRequest "https://go.microsoft.com/fwlink/?linkid=2165884" -OutFile "$downloads\adksetup.exe"
start-process -FilePath "$downloads\adksetup.exe" -ArgumentList "/quiet /features OptionId.DeploymentTools" -Wait

#Download and Install Win11 WinPE ADK (Backwards compatible with win10)
Invoke-WebRequest "https://go.microsoft.com/fwlink/?linkid=2166133" -OutFile "$downloads\adkwinpesetup.exe"
start-process -FilePath "$downloads\adkwinpesetup.exe" -ArgumentList "/quiet /features OptionId.WindowsPreinstallationEnvironment" -Wait

#Download Dell WinPE10 Pack
#Check for latest here: https://www.dell.com/support/kbdoc/en-us/000108642/winpe-10-driver-pack
$downloads = "$home\Downloads"
Invoke-WebRequest "https://downloads.dell.com/FOLDER07703466M/1/WinPE10.0-Drivers-A25-F0XPX.CAB" -OutFile "$downloads\WinPE10.0-Drivers-A25.cab"
expand "$downloads\WinPE10.0-Drivers-A25.cab" -F:* "$dir\WinPE10.0-Drivers"


#Optional - Copying Source WinPE from ADK. Only need to do this the first time
echo f | xcopy "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Windows Preinstallation Environment\amd64\en-us\winpe.wim" $source /f /y

#Mount Wim
Dism /Mount-Image /ImageFile:$source /index:1  /MountDir:$mountpath

#Adding Dell WinPE Drivers
dism /image:$mountpath /add-driver /driver:"$dir\WinPE10.0-Drivers\winpe\x64" /recurse

#Adding modules, including powershell
$packagepath = "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Windows Preinstallation Environment\amd64\WinPE_OCs"
Dism /Add-Package /Image:"$mountpath" /PackagePath:"$packagepath\WinPE-WMI.cab"
Dism /Add-Package /Image:"$mountpath" /PackagePath:"$packagepath\en-us\WinPE-WMI_en-us.cab"
Dism /Add-Package /Image:"$mountpath" /PackagePath:"$packagepath\WinPE-NetFX.cab"
Dism /Add-Package /Image:"$mountpath" /PackagePath:"$packagepath\en-us\WinPE-NetFX_en-us.cab"
Dism /Add-Package /Image:"$mountpath" /PackagePath:"$packagepath\WinPE-Scripting.cab"
Dism /Add-Package /Image:"$mountpath" /PackagePath:"$packagepath\en-us\WinPE-Scripting_en-us.cab"
Dism /Add-Package /Image:"$mountpath" /PackagePath:"$packagepath\WinPE-PowerShell.cab"
Dism /Add-Package /Image:"$mountpath" /PackagePath:"$packagepath\en-us\WinPE-PowerShell_en-us.cab"
Dism /Add-Package /Image:"$mountpath" /PackagePath:"$packagepath\WinPE-StorageWMI.cab"
Dism /Add-Package /Image:"$mountpath" /PackagePath:"$packagepath\en-us\WinPE-StorageWMI_en-us.cab"
Dism /Add-Package /Image:"$mountpath" /PackagePath:"$packagepath\WinPE-DismCmdlets.cab"
Dism /Add-Package /Image:"$mountpath" /PackagePath:"$packagepath\en-us\WinPE-DismCmdlets_en-us.cab"

#Modifying Startnet
'wpeinit' | out-file "$mountpath\windows\system32\startnet.cmd" -Force -Encoding ASCII
$(@('@for %%a in (C D E F G H) do @if exist %%a:\Apply-Image.ps1 set BOOTDRIVE=%%a')) | out-file "$mountpath\windows\system32\startnet.cmd" -Force -Encoding ASCII -Append
'powershell -executionpolicy bypass -file %BOOTDRIVE%:\Apply-Image.ps1' | out-file "$mountpath\windows\system32\startnet.cmd" -Append -Encoding ASCII

#Saving Changes
Dism /Unmount-Image /MountDir:$mountpath /commit
