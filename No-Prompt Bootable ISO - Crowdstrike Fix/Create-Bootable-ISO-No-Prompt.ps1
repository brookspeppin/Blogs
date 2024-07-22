#Initializing Variables
#Brooks Peppin - www.brookspeppin.com
# x/Twitter - @brookspeppin
# 7/22/24 - added fix to prompting on BIOS based systems

$WinPE_amd64 = "C:\WinPE_amd64"
$source ="C:\WinPE_amd64\media\sources\boot.wim"
$mountpath = "$WinPE_amd64\Mount"
$downloads = "$home\Downloads"
 

#Download and Installing ADK
Invoke-WebRequest https://go.microsoft.com/fwlink/?linkid=2196127 -OutFile "$downloads\adksetup.exe"
start-process -FilePath "$downloads\adksetup.exe" -ArgumentList " /features OptionId.DeploymentTools" -Wait

#Download and Install Win11 22H2 WinPE ADK (Backwards compatible with win10)- https://go.microsoft.com/fwlink/?linkid=2196224
Invoke-WebRequest https://go.microsoft.com/fwlink/?linkid=2196224 -OutFile "$downloads\adkwinpesetup.exe"
start-process -FilePath "$downloads\adkwinpesetup.exe" -ArgumentList "/quiet /features OptionId.WindowsPreinstallationEnvironment" -Wait
 

#Setup WinPE folders
$env = "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\DandISetEnv.bat"
cmd.exe /c """$env"" && copype amd64 $WinPE_amd64"

#Mount Dism and Create Startnet.cmd

Dism /Mount-Image /ImageFile:$source /index:1  /MountDir:$mountpath
'wpeinit' | out-file "$mountpath\windows\system32\startnet.cmd" -Force -Encoding ASCII
'@for %%a in (C D E F G H I J K L M N O P) do @if exist %%a:\Windows\System32\drivers\CrowdStrike\ set WIN=%%a'| out-file "$mountpath\windows\system32\startnet.cmd" -Force -Encoding ASCII -Append
'del %WIN%:\Windows\System32\drivers\CrowdStrike\C-00000291*.sys' | out-file "$mountpath\windows\system32\startnet.cmd" -Append -Encoding ASCII
'Wpeutil Shutdown' | out-file "$mountpath\windows\system32\startnet.cmd" -Force -Encoding ASCII -Append
 

#Add key components
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

#Save and Unmount Image
Dism /Unmount-Image /MountDir:$mountpath /commit

#make it no prompt
#credit nick richardson - https://spiderzebra.com/
$ADKPath = (Get-ItemProperty -Path "HKLM:\Software\WOW6432Node\Microsoft\Windows Kits\Installed Roots").KitsRoot10 + "Assessment and Deployment Kit\Deployment Tools"
$oscdimg = $ADKPath + "\amd64\Oscdimg\oscdimg.exe"
$etfsboot = $ADKPath + "\amd64\Oscdimg\etfsboot.com"
$efisys_noprompt = $ADKPath + "\amd64\Oscdimg\efisys_noprompt.bin"
Remove-Item "$WinPE_amd64\media\Boot\bootfix.bin" #Remove the prompt for BIOS based systems
$parameters = "-bootdata:2#p0,e,b""$etfsboot""#pEF,e,b""$efisys_noprompt"" -u1 -udfver102 ""$WinPE_amd64\media"" ""$WinPE_amd64\crowdstrike_noprompt.iso"""
$ProcessingResult = Start-Process -FilePath $oscdimg -ArgumentList $parameters -Wait -NoNewWindow -PassThru