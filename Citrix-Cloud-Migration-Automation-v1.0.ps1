﻿#Requires -Version 5.0
#This File is in Unicode format. Do not edit in an ASCII editor. Notepad++ UTF-8-BOM

#region help text

<#
.SYNOPSIS
	Automate migration from CVAD to CVAD Service.
.DESCRIPTION
	The script wil automatically export configuration from CVAD on-premises and import to CVAD Services (Citrix Cloud)
	Some manual tasks for migration are still needed but next release should fix this.
		
	Requires -RunAsAdministrator (or elevated PowerShell session)
	Requires a Citrix Cloud API key see --> https://docs.citrix.com/en-us/citrix-cloud/citrix-cloud-management/identity-access-management.html
	Requires Active Directory on Azure or Site to Site connectivity between Azure and on-premises

.NOTES
	NAME: Citrix-Cloud-Migration-Automation-v1.0.ps1
	VERSION: 1.00
	AUTHOR: Arnaud Pain
	LASTEDIT: September 3, 2020
#>
#endregion

# VARIABLES TO BE SET BEFORE RUNNING THE SCRIPT
# Define FTP variables
$Username = "arnaudpain/ftp@arnaud.biz"
$Password = "9$<rZK-k"
# Citrix Cloud credentials
        $CustomerID = "" # To be filled before running the script
        $ClientID = "" # To be filled before running the script
        $ClientSecret = "" # To be filled before running the script
        $Citrix_Resource_Location_Name = "" # To be filled before running the script
# Cloud Connector VM Name
    $CloudConnectorMachineName1 = "" # To be filled before running the script
    $CloudConnectorMachineName2 = "" # To be filled before running the script

# Setup script running time
    $ScriptStopWatch = [System.Diagnostics.StopWatch]::StartNew()

# Check if user is admin and script is running elevated
    $CurrentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (!($CurrentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))) {
        Write-Host "User does not have admin rights. Are you running this in an elevated session?" -ForegroundColor Red
        Write-Host "Stopping script." -ForegroundColor Red
        Return
    }

# MAIN SCRIPT
# Citrix Cloud - Bearer Token
    Write-Host "1. Citrix Cloud - Get Bearer Token" -ForegroundColor Green
    $Body = @{
        "ClientId"     = $ClientID;
        "ClientSecret" = $ClientSecret
    }
    $PostHeaders = @{
        "Content-Type" = "application/json"
    } 

    $TrustURL = "https://trust.citrixworkspacesapi.net/root/tokens/clients"
    $Response = Invoke-RestMethod -Uri $TrustURL -Method POST -Body (ConvertTo-Json -InputObject $Body) -Headers $PostHeaders
    $BearerToken = $Response.token   
    $Token = "CwsAuth Bearer=" + $BearerToken
	
# AUTHENTICATION 
    Write-Host "2. Ask user for credentials" -ForegroundColor Green

# VMware vCenter administrator account
    Write-Host "*** VMWare vCenter administrator ***" -ForegroundColor Yellow
    Write-Host "Please enter the vCenter administrator credentials" -ForegroundColor Yellow
    $vCenterAdminUsername = Read-Host "Username"
    $vCenterAdminPassword = Read-Host "Password" 
	  
# Citrix PVS Server administrator account
    Write-Host "*** Citrix PVS Server administrator ***" -ForegroundColor Yellow
    Write-Host "Enter the credentials for a user that is an administrator on the PVS Server" -ForegroundColor Yellow
    $PVSAdminUsername = Read-Host "Username"
    $PVSAdminPassword = Read-Host "Password"
    
# Test if CVAD Tool already installed
	$Test = Test-path "C:\Program Files\Citrix\AutoConfig\Citrix.AutoConfig"
	if ($test -eq "True") {
	Write-Host "Citrix Auto Config Tool  already installed, continue" -foregroundcolor Green
	}
	else {

	# Download Citrix Auto Config Tool
	write-host "Download Citrix Auto Config Tool" -ForegroundColor Yellow
	$LocalFile = "C:\AutoConfig_PowerShell_x64_1.0.199.msi"
	$RemoteFile = "ftp://arnaudpain.sharefileftp.com/automation/AutoConfig_PowerShell_x64_1.0.199.msi"
	$FTPRequest = [System.Net.FtpWebRequest]::Create($RemoteFile)
	$FTPRequest.Credentials = New-Object System.Net.NetworkCredential($Username,$Password)
	$FTPRequest.Method = [System.Net.WebRequestMethods+Ftp]::DownloadFile
	$FTPRequest.UseBinary = $true
	$FTPRequest.KeepAlive = $false
	$FTPResponse = $FTPRequest.GetResponse()
	$ResponseStream = $FTPResponse.GetResponseStream()
	$LocalFileFile = New-Object IO.FileStream ($LocalFile,[IO.FileMode]::Create)
	[byte[]]$ReadBuffer = New-Object byte[] 1024
	do {
	$ReadLength = $ResponseStream.Read($ReadBuffer,0,1024)
	$LocalFileFile.Write($ReadBuffer,0,$ReadLength)
	}
	while ($ReadLength -ne 0)
	$LocalFileFile.Close()
	
	write-host "Citrix Auto Config Tool downloaded" -ForegroundColor Green
	Start-Sleep -Seconds 5

	# Install Citrix Auto Config Tool
	Write-Host "Install Citrix AutoConfig tool" -ForegroundColor Yellow
	msiexec /i c:\AutoConfig_PowerShell_x64_1.0.199.msi /q 
	Write-Host "AutoConfig Tool installed" -ForegroundColor Green
	Start-Sleep -Seconds 5
	}

# Import Module
	Write-Host "Import Citrix AutoConfig tool Module" -ForegroundColor Yellow
	Import-Module 'C:\Program Files\Citrix\AutoConfig\Citrix.AutoConfig\Citrix.AutoConfig.psd1'
	Start-Sleep -Seconds 5

# Export CVAD
	Write-Host "Export on-premises configuration" -ForegroundColor Yellow
	Export-CvadAcToFile -AdminAddress ctx-ddc-01.ctx.local 
	Write-Host "Configuration exported" -ForegroundColor Green
	Start-Sleep -Seconds 5


# Configure Zone Mapping
	(Get-Content $env:userprofile\Documents\Citrix\AutoConfig\ZoneMapping.yml).replace('Name_Of_Your_Resouce_Zone', """$Citrix_Resource_Location_Name""") | Set-content $env:userprofile\Documents\Citrix\AutoConfig\ZoneMapping.yml

# Create customerinfo.yml
	Write-Host "Configure CustomerInfo.yml file" -ForegroundColor Yellow
	New-CvadAcCustomerInfoFile -CustomerId $CustomerID -ClientId $ClientID -Secret $ClientSecret 
	Write-Host "CustomInfo.yml file set" -ForegroundColor Green

# PVS test: if PVS in cvadsecurity.yml then add "HostConnections: True" in CustomerInfo.yml file
	Write-Host "Check if PVS is used" -ForegroundColor Yellow
	If (get-content $env:userprofile\Documents\Citrix\AutoConfig\cvadacsecurity.yml | Select-string PVS) {
	add-content $env:userprofile\Documents\Citrix\AutoConfig\customerinfo.yml "HostConnections: True"
	Write-Host "PVS is used, Customerinfo.yml configured" -ForegroundColor Green
	}
	else {Write-Host "PVS not used, continue" -ForegroundColor Green}

# Fill CvadAcsecurity.yml file
	If (get-content $env:userprofile\Documents\Citrix\AutoConfig\cvadacsecurity.yml | Select-string PVS) {
	$usernamesource = "Put user name here"
	$usernamepassword = "Put password here"
	# Set PVS Username
	$filecontent = get-content $env:userprofile\Documents\Citrix\AutoConfig\cvadacsecurity.yml
	$Filecontent[3] = $filecontent[3] -replace $usernamesource, $PVSAdminUsername
	set-content $env:userprofile\Documents\Citrix\AutoConfig\cvadacsecurity.yml -Value $filecontent
	# Set PVS Password
	$filecontent = get-content $env:userprofile\Documents\Citrix\AutoConfig\cvadacsecurity.yml
	$Filecontent[4] = $filecontent[4] -replace $usernamepassword, $PVSAdminPassword
	set-content $env:userprofile\Documents\Citrix\AutoConfig\cvadacsecurity.yml -Value $filecontent
	# Set vCenter Username
	$filecontent = get-content $env:userprofile\Documents\Citrix\AutoConfig\cvadacsecurity.yml
	$Filecontent[7] = $filecontent[7] -replace $usernamesource, $vCenterAdminUsername
	set-content $env:userprofile\Documents\Citrix\AutoConfig\cvadacsecurity.yml -Value $filecontent
	# Set vCenter Password
	$filecontent = get-content $env:userprofile\Documents\Citrix\AutoConfig\cvadacsecurity.yml
	$Filecontent[8] = $filecontent[8] -replace $usernamepassword, $vCenterAdminPassword
	set-content $env:userprofile\Documents\Citrix\AutoConfig\cvadacsecurity.yml -Value $filecontent
	}
	else #MCS
	{
	# Set vCenter Username
	$filecontent = get-content $env:userprofile\Documents\Citrix\AutoConfig\cvadacsecurity.yml
	$Filecontent[3] = $filecontent[3] -replace $usernamesource, $vCenterAdminUsername
	set-content $env:userprofile\Documents\Citrix\AutoConfig\cvadacsecurity.yml -Value $filecontent
	# Set vCenter Password
	$filecontent = get-content $env:userprofile\Documents\Citrix\AutoConfig\cvadacsecurity.yml
	$Filecontent[4] = $filecontent[4] -replace $usernamepassword, $vCenterAdminPassword
	set-content $env:userprofile\Documents\Citrix\AutoConfig\cvadacsecurity.yml -Value $filecontent
	}

# Import Settings
	$ready = read-Host "Ready to Import. Press Enter to start"
	Write-Host "Import configuration in CVAD Service" -ForegroundColor Yellow
	Import-CvadAcToSite -All $true -Confirm $false 

# change GPO Setting 
	write-host "Please change Controller settings in GPO to replace current with:" $CloudConnectorMachineName1 "and" $CloudConnectorMachineName2
	$ready = read-Host "Press Enter when Controller settings changed in GPO."

# restart VDA
	$Test = Write-Host "Please restart your VDA to register with Cloud Connector and press Enter"

# Verification
	$Test = Write-Host "Ensure your VDA a registered and press Enter"
