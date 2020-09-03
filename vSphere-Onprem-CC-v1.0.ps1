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
	
	You need to have on your C:\ drive the "linked" script remote-cc.ps1 and add variables in this script as well
	
	Requires -RunAsAdministrator (or elevated PowerShell session)
	Requires existing domain controller (powered on!)
	Requires a Citrix Cloud API key see --> https://docs.citrix.com/en-us/citrix-cloud/citrix-cloud-management/identity-access-management.html

.NOTES
	NAME: vSphere-Onprem-CC-v1.0.ps1
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

# PREREQUISITES 
# Setup script running time
    $ScriptStopWatch = [System.Diagnostics.StopWatch]::StartNew()

# Check if user is admin and script is running elevated
    $CurrentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (!($CurrentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))) {
        Write-Host "User does not have admin rights. Are you running this in an elevated session?" -ForegroundColor Red
        Write-Host "Stopping script." -ForegroundColor Red
        Return
    }

# Enable TLS 1.2 required for Citrix Bearer Token
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Setup script running time
    $ScriptStopWatch = [System.Diagnostics.StopWatch]::StartNew()

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


# Install Module VMware PowerCLI
Install-Module -Name VMware.PowerCLI -AllowClobber -Force -confirm:$false

# Disable Certificate error
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false

# Disable VMware CEIP
Set-PowerCLIConfiguration -Scope User -ParticipateInCEIP $false

# Connect to vCenter
Connect-VIServer -Server vcenter6.lab.local -user administrator@vsphere.local -Password IamCTPin2020! 

# Retrieve Template details
$Temp = Read-Host " Please provide the name of the Temaplate to use"
$Template = Get-Template -Name $Temp

# Retrieve Customization File details
$OSCust = Read-Host " Please provide the name of the customization file to use"
$Specs = Get-OSCustomizationSpec -Name $OSCust

# Retrieve name for the first Cloud Connector
$cc1 = Read-Host "Please provide the name for the fist Cloud Connector Server"

# Retrieve name for the second Cloud Connector
$cc2 = Read-Host "Please provide the name for the second Cloud Connector Server"

# Retrieve name of the ESX Host
$VMHost = Read-host "Please provide IP of 1 of your ESX host where you want the VM to be installed on" 

# Retrieve name of the Datastore
$Datastore = read-host "Please provide the name of the Datastore where you want the VM to be installed on" 

# Deploy First Cloud Connector
Write-host "3. Deploy first Cloud Connector" -Foregroundcolor green
New-VM -Name $cc1 -Template $Template -VMHost $VMhost -Datastore $Datastore –OSCustomizationSpec $specs –Confirm:$false >$null

# Start first Cloud Connector 
Write-host "4. Start First Cloud Connector" -Foregroundcolor green
Start-VM -VM $cc1 >$null

# Change network adapter settings
Get-vm $cc1 | get-networkadapter | set-networkadapter -connected:$true -StartConnected:$true -Confirm:$false
# It is difficult to estimate time to deploy the VM from Template, so just ask for verification by user before processing with Cloud Connector software deployment
start-sleep -Seconds 60

# Ensure VM is domain-joined
read-host "Ensure your VMs are deployed and domain-joined, the press Enter"

# Configure Cloud Connector 
Write-host "5. Configure Cloud Connector on first server" -Foregroundcolor green
Copy-VMGuestFile -Source C:\remote-cc.ps1 -Destination C:\remote-cc.ps1 -VM $cc1 -LocalToGuest -GuestUser administrator@ctx.local -GuestPassword Citrix2020!
$script = "C:\remote-cc.ps1"
Invoke-VMScript -vm $cc1 -ScriptText $script -GuestUser administrator@ctx.local -GuestPassword Citrix2020! -ScriptType Powershell 

# Deploy second Cloud Connector
Write-host "6. Deploy second Cloud Connector" -Foregroundcolor green
New-VM -Name $cc2 -Template $Template -VMHost $VMhost -Datastore $Datastore –OSCustomizationSpec $specs –Confirm:$false >$null

# Start second Cloud Connector 
Write-host "7. Start second Cloud Connector" -Foregroundcolor green
Start-VM -VM $cc2 >$null

# Change network adapter settings
get-vm $cc2 | get-networkadapter | set-networkadapter -connected:$true -StartConnected:$true -Confirm:$false
# It is difficult to estimate time to deploy the VM from Template, so just ask for verification by user before processing with Cloud Connector software deployment
start-sleep -Seconds 60

# Ensure VM is domain-joined
read-host "Ensure your VMs are deployed and domain-joined, the press Enter"

# Configure Cloud Connector 
Write-host "8. Configure Cloud Connector on second server" -Foregroundcolor green
Copy-VMGuestFile -Source C:\remote-cc.ps1 -Destination C:\remote-cc.ps1 -VM $cc2 -LocalToGuest -GuestUser administrator@ctx.local -GuestPassword Citrix2020!
$script = "C:\remote-cc.ps1"
Invoke-VMScript -vm $cc2 -ScriptText $script -GuestUser administrator@ctx.local -GuestPassword Citrix2020! -ScriptType Powershell 

write-host "You can now check in your Citrix Cloud Portal that Resource Location has been created and 2 Cloud Connector are present"
start-sleep -Seconds 60

# Present timing
    $ScriptStopWatch.Stop()
    $ScriptRunningTime = [math]::Round($ScriptStopWatch.Elapsed.TotalMinutes,1)
    Write-Host "Script ran for" $ScriptRunningTime "Minutes" -ForegroundColor Magenta
# -------------------------------

 