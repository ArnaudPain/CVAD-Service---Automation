# Script to deploy Cloud Connector on-premises
# This File is in Unicode format. Do not edit in an ASCII editor. Notepad++ UTF-8-BOM
# Created by Arnaud Pain
# September, 2020
# Version 1.0

<#
.SYNOPSIS
	This script will be copied and used on on-premises vSphere Cloud Connector VM to install Citrix Cloud Connector

.NOTES
	NAME: Remote-cc.ps1
	VERSION: 1.00
	AUTHOR: Arnaud Pain
	LASTEDIT: September 12, 2020
    Copyright (c) Arnaud Pain. All rights reserved.
#>

# SET VARIABLES ----------------
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
# -------------------------------

# Citrix Cloud credentials
 $CustomerID = "" #To be filled before running the Master script
 $ClientID = "" #To be filled before running the Master script
 $ClientSecret = "" #To be filled before running the Master script

# Citrix Cloud Information
    $CTX_Resource_Location_Name = "" #To be filled before running the Master script

# SCRIPT ------------------------
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

