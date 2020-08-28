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
 $CustomerID = "2g60i8n7zhxd" #To be filled before running the script
 $ClientID = "d03d1473-cc68-4486-9bf3-02d7c7f455a0" #To be filled before running the script
 $ClientSecret = "t8m5YuezfTxyo8JvBppuCw==" #To be filled before running the script

# Citrix Cloud Information
    $CTX_Resource_Location_Name = "On-Premises"

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

