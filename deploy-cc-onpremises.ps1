# PREREQUISITES -----------------
# Setup script running time
    $ScriptStopWatch = [System.Diagnostics.StopWatch]::StartNew()

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


# Install Module VMware PowerCLI
Install-Module -Name VMware.PowerCLI -AllowClobber -Force -confirm:$false

# Disable Certificate error
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false

# Disable VMware CEIP
Set-PowerCLIConfiguration -Scope User -ParticipateInCEIP $false

# Connect to vCenter
Connect-VIServer -Server vcenter6.lab.local -user administrator@vsphere.local -Password IamCTPin2020! 

# Retrieve Customization File details
$Specs = Get-OSCustomizationSpec -Name 'WindowsServer2016'

# Retrieve Template details
$Template = Get-Template -Name '2K16-Template'

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

 