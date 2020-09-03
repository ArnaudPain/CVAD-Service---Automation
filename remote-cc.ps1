#Requires -Version 5.0
#This File is in Unicode format. Do not edit in an ASCII editor. Notepad++ UTF-8-BOM

#region help text

<#
.SYNOPSIS
	Deploy 2 Windows Server on vSphere or ESX, domain join and deploy Citrix Cloud Connector
.DESCRIPTION
	The script will create Resource Location in Citrix Cloud.
	It will ask you for:
	 Name of the Template
	 Name of the customization file
	 Name of each server to deploy
	 
	When VMs are deployed they will be domain-joined
	Then Citrix Cloud Connector software is downloaded from my ShareFile FTP and deployed
	
	You need to have on your C:\ drive the "linked" script remote-cc.ps1
	
	Requires -RunAsAdministrator (or elevated PowerShell session)
	Requires existing domain controller (powered on!)
	Requires a Citrix Cloud API key see --> https://docs.citrix.com/en-us/citrix-cloud/citrix-cloud-management/identity-access-management.html
	Requires Active Directory on Azure or Site to Site connectivity between Azure and on-premises

.NOTES
	NAME: remote-cc.ps1
	VERSION: 1.00
	AUTHOR: Arnaud Pain
	LASTEDIT: September 3, 2020
#>
#endregion

# VARIABLES TO BE SET BEFORE RUNNING THE SCRIPT
# Citrix Cloud credentials
 $CustomerID = "" # To be filled before running the script
 $ClientID = "" # To be filled before running the script
 $ClientSecret = "" # To be filled before running the script

# Citrix Cloud Information
    $CTX_Resource_Location_Name = "" # To be filled before running the script

# FTP Variables
    $Username = "arnaudpain/ftp@arnaud.biz"
    $Password = "9$<rZK-k"

# Download Cloud Connector software
$LocalFile = "C:\cwcconnector.exe"
$RemoteFile = "ftp://arnaudpain.sharefileftp.com/automation/cwcconnector.exe"
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

# Enable TLS 1.2
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12


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

# Citrix Cloud - Create Resource Location
    Write-Host "2. Citrix Cloud - Create Resource Location" -ForegroundColor Green
    $Body = @{
        "Name" = $CTX_Resource_Location_Name
    }
    
    $Headers = @{
        "Accept"        = "application/json";
        "Authorization" = $Token;
        "Content-Type"  = "application/json"
    }
    $Json = ConvertTo-Json -InputObject $Body
    
    $ResourceURL = "https://registry-eastus-release-b.citrixworkspacesapi.net/" + $CustomerID + "/resourcelocations"
    $Resource = Invoke-WebRequest -Method POST -uri $ResourceURL -body $json -Headers $headers -UseBasicParsing

    $CTXCloudResourceID = ($Resource.Content | ConvertFrom-Json).ID

# Install Cloud Connector
$arg = "/q /Customer:$CustomerID /ClientId:$ClientID /ClientSecret:$ClientSecret /ResourceLocationId:$CTXCloudResourceID /AcceptTermsOfService:true"
Start-Process "C:\cwcconnector.exe" $arg -Wait

