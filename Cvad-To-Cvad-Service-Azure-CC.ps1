# SCRIPT INFO -------------------
# --- Migrate from CVAD to CVAD Service with Azure Cloud Connector ---
# By Arnaud Pain
# v0.1
# -------------------------------
# Run on management machine
# Requires -RunAsAdministrator (or elevated PowerShell session)
# Requires existing domain controller (powered on!)
# Requires a Citrix Cloud API key see --> https://docs.citrix.com/en-us/citrix-cloud/citrix-cloud-management/identity-access-management.html
# -------------------------------

# SET VARIABLES ----------------
# Citrix Cloud credentials
    $CustomerID = "2g60i8n7zhxd" #To be filled before running the script
    $ClientID = "d03d1473-cc68-4486-9bf3-02d7c7f455a0" #To be filled before running the script
    $ClientSecret = "t8m5YuezfTxyo8JvBppuCw==" #To be filled before running the script
# Azure specifics - Must be valid
    $AzureResourceGroupLocation = "EastUS2"
    $AzureVNetName = "CTX-VNET" # <<-- must have domain controller on network
    $AzureSubnetName = "Default"
# Azure specifics - Will be created if needed
    $AzureResourceGroupName = "CTX-RG"
    $AzureVNetResourceGroupName = "CTX-RG"
    $AzureDiagnosticsStorageAccountName = "eastus2diagan" # <<-- Must be all lower case
    $AzureDiagnosticResourceGroupName = "DIAG-RG"
# Miscellaneous
    $DomainName = "ctx.local"
# Citrix Cloud Information
    $CTX_Resource_Location_Name = "EAST-US-2"
# Azure specific
    $AzureStorageAccountName = "citrixdeploymentauto" # <<-- Must be all lower case
    $CloudConnectorDeploymentTemplateFile = "https://raw.githubusercontent.com/ArnaudPain/Citrix-Azure/master/Azure-Citrix-Cloud-Connector-Deployment-Template-2016.json"
# Virtual machine specifics
    $CloudConnectorMachineName1 = "AZ-CCC-01"
	$CloudConnectorMachineName2 = "AZ-CCC-02"
	$CloudConnectorMachineType = "Standard_DS2_v2"
    $CloudConnectorDiskType = "Premium_LRS"
	
# FTP Variables
    $Username = "arnaudpain/ftp@arnaud.biz"
    $Password = "9$<rZK-k"

# Citrix Delivery controller
    $DDC= "ctx-ddc-01"

# Miscellaneous
    $LocalTempFolder = "C:\Temp"
    $UsersGroupName = "Domain Users"
# -------------------------------

# PREREQUISITES -----------------
# Setup script running time
    $ScriptStopWatch = [System.Diagnostics.StopWatch]::StartNew()

# Check if user is admin and script is running elevated
    $CurrentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (!($CurrentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))) {
        Write-Host "User does not have admin rights. Are you running this in an elevated session?" -ForegroundColor Red
        Write-Host "Stopping script." -ForegroundColor Red
        Return
    }

# Enable TLS 1.2
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
# -------------------------------

# FUNCTIONS ---------------------
    Function Add-JDAzureRMVMToDomain {
        param(
            [Parameter(Mandatory = $true)]
            [string]$DomainName,
            [Parameter(Mandatory = $false)]
            [System.Management.Automation.PSCredential]$Credentials = $ADCredentials,
            [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
            [Alias('VMName')]
            [string]$Name,
            [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
            [ValidateScript( { Get-AzureRmResourceGroup -Name $_ })]
            [string]$ResourceGroupName
        )
        begin {
            # Define domain join settings (username/domain/password)
            $Settings = @{
                Name    = $DomainName
                User    = $Credentials.UserName
                Restart = "true"
                Options = 3
            }
            $ProtectedSettings = @{
                Password = $Credentials.GetNetworkCredential().Password
            }
            Write-Verbose -Message "Domainname is: $DomainName"
        }
        process {
            try {
                $RG = Get-AzureRmResourceGroup -Name $ResourceGroupName
                $JoinDomainHt = @{
                    ResourceGroupName  = $RG.ResourceGroupName
                    ExtensionType      = 'JsonADDomainExtension'
                    Name               = 'joindomain'
                    Publisher          = 'Microsoft.Compute'
                    TypeHandlerVersion = '1.0'
                    Settings           = $Settings
                    VMName             = $Name
                    ProtectedSettings  = $ProtectedSettings
                    Location           = $RG.Location
                }
                Write-Verbose -Message "Joining $Name to $DomainName"
                Set-AzureRMVMExtension @JoinDomainHt
            }
            catch {
                Write-Warning $_
            }
        }
        end { }
    }

    Function RegisterRP {
        Param(
            [string]$ResourceProviderNamespace
        )

        Write-Host "Registering Azure resource provider '$ResourceProviderNamespace'";
        Register-AzureRmResourceProvider -ProviderNamespace $ResourceProviderNamespace;
    }
# -------------------------------

# MODULES-1 ---------------------
# Azure - Import necessary modules
    Write-Host "1. Import necessary PowerShell modules - Part 1" -ForegroundColor Green

# Azure Resource Manager module
    if (Get-Module -ListAvailable -Name AzureRM) {
        Write-Host "Azure RM module already available, importing..." -ForegroundColor Yellow
        Import-Module AzureRM | Out-Null
    } else {
        Write-Host "Azure RM module not yet available, installing..." -ForegroundColor Yellow
        Install-Module -Name AzureRM -scope AllUsers -Confirm:$false -force
        Import-Module AzureRM | Out-Null
    }
# -------------------------------

# AUTHENTICATION ----------------
    Write-Host "2. Ask user for credentials" -ForegroundColor Green

# Azure
    Write-Host "*** Azure login ***" -ForegroundColor Yellow
    Login-AzureRmAccount

# Virtual machines - Local administrator
    Write-Host "*** Virtual machine - Local administrator ***" -ForegroundColor Yellow
    Write-Host "Please enter the Windows administrator credentials to be set on the Cloud Connector" -ForegroundColor Yellow
    $CloudConnectorAdminUsername = Read-Host "Username"
    $CloudConnectorAdminPassword = Read-Host "Password" -AsSecureString
	  
# Virtual machines - Domain join
    Write-Host "*** Virtual machine - Domain join ***" -ForegroundColor Yellow
    Write-Host "Enter the credentials for a user that is allowed to join machines to the domain" -ForegroundColor Yellow
    $ADCredentials = Get-Credential 

# MODULES-2 ---------------------
# Azure - Import necessary modules
    Write-Host "3. Import necessary PowerShell modules - Part 2" -ForegroundColor Green

# Azure Active Directory module    
    if (Get-Module -ListAvailable -Name AzureAD) {
        Write-Host "Azure AD module already available, importing..." -ForegroundColor Yellow
        Import-Module AzureAD | Out-Null
    } else {
        Write-Host "Azure AD module not yet available, installing..." -ForegroundColor Yellow
        Install-Module -Name AzureAD -Scope AllUsers -Confirm:$false -Force
        Import-Module AzureAD | Out-Null
    }


# SCRIPT ------------------------
# Citrix Cloud - Bearer Token
    Write-Host "4. Citrix Cloud - Get Bearer Token" -ForegroundColor Green
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
    Write-Host "5. Citrix Cloud - Create Resource Location" -ForegroundColor Green
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

# Create Azure storage account
    Write-Host "6. Azure - Create Azure resource groups (if needed)" -ForegroundColor Green

# Check for existing resource group and create new one if needed
    $AzureResourceGroup = Get-AzureRmResourceGroup -Name $AzureResourceGroupName -ErrorAction SilentlyContinue
    if (!$AzureResourceGroup) {
        Write-Host "Resource group '$AzureResourceGroupName' does not exist yet" -ForegroundColor Yellow
        Write-Host "Creating resource group '$AzureResourceGroupName' in location '$AzureResourceGroupLocation'" -ForegroundColor Yellow
        New-AzureRmResourceGroup -Name $AzureResourceGroupName -Location $AzureResourceGroupLocation
    } else {
        Write-Host "Using existing resource group '$AzureResourceGroupName'" -ForegroundColor Yellow
    }

    if ($AzureVNetResourceGroupName -ne $AzureResourceGroupName) {
        Write-Host "Different resource group specified for Virtual Networks" -ForegroundColor Yellow
        $AzureVNetResourceGroup = Get-AzureRmResourceGroup -Name $AzureVNetResourceGroupName -ErrorAction SilentlyContinue
        if (!$AzureVNetResourcegroup) {
            Write-Host "Virtual network resource group '$AzureVNetResourceGroupName' does not exist yet" -ForegroundColor Yellow
            Write-Host "Creating virtual network resource group '$AzureVNetResourceGroupName' in location '$AzureResourceGroupLocation'" -ForegroundColor Yellow
            New-AzureRmResourceGroup -Name $AzureVNetResourceGroupName -Location $AzureResourceGroupLocation
        } else {
            Write-Host "Using existing virtual network resource group '$AzureVNetResourceGroupName'" -ForegroundColor Yellow    
        }
    } else {
        Write-Host "Specified virtual network resource group is identical to the VM resource group" -ForegroundColor Yellow
    }

    if ($AzureDiagnosticResourceGroupName -ne $AzureResourceGroupName) {
        Write-Host "Different resource group specified for diagnostic information" -ForegroundColor Yellow
        $AzureDiagnosticResourceGroup = Get-AzureRmResourceGroup -Name $AzureDiagnosticResourceGroupName -ErrorAction SilentlyContinue
        if (!$AzureDiagnosticResourceGroup) {
            Write-Host "Diagnostic resource group '$AzureDiagnosticResourceGroupName' does not exist yet" -ForegroundColor Yellow
            Write-Host "Creating diagnostic resource group '$AzureDiagnosticResourceGroupName' in location '$AzureResourceGroupLocation'" -ForegroundColor Yellow
            New-AzureRmResourceGroup -Name $AzureDiagnosticResourceGroupName -Location $AzureResourceGroupLocation
        } else {
            Write-Host "Using existing diagnostic virtual network resource group '$AzureDiagnosticResourceGroupName'" -ForegroundColor Yellow 
        }
    } else {
        Write-Host "Specified diagnostic resource group is identical to the VM resource group" -ForegroundColor Yellow
    }

# Create Azure storage account
    Write-Host "7. Azure - Create Azure storage accounts (if needed)" -ForegroundColor Green

# Check for existing storage accounts and create new ones if needed
    if ($AzureStorageAccount = (Get-AzureRmStorageAccount -ResourceGroupName $AzureResourceGroupName -Name $AzureStorageAccountName -ErrorAction SilentlyContinue).StorageAccountName) {
        Write-Host "Azure storage account already exists" -ForegroundColor Yellow
    } else {
        Write-Host "Azure storage account does not exist yet, creating..." -ForegroundColor Yellow
        $AzureStorageAccount = (New-AzureRmStorageAccount -ResourceGroupName $AzureResourceGroupName -Name $AzureStorageAccountName -SkuName Standard_GRS -Location $AzureResourceGroupLocation).StorageAccountName
    }

    if (Get-AzureRmStorageAccount -ResourceGroupName $AzureDiagnosticResourceGroupName -Name $AzureDiagnosticsStorageAccountName -ErrorAction SilentlyContinue) {
        Write-Host "Azure diagnostics storage account already exists" -ForegroundColor Yellow
    } else {
        Write-Host "Azure diagnostics storage account does not exist yet, creating..." -ForegroundColor Yellow
        New-AzureRmStorageAccount -ResourceGroupName $AzureDiagnosticResourceGroupName -Name $AzureDiagnosticsStorageAccountName -SkuName Standard_LRS -Location $AzureResourceGroupLocation
    }

# Check for existing storage keys and create new one if needed
    if ($AzureStorageKeys = Get-AzureRMStorageAccountKey -ResourceGroupName $AzureResourceGroupName -Name $AzureStorageAccount -ErrorAction SilentlyContinue | Where-Object{$_.KeyName -eq "Key1"}) {
        Write-Host "Azure storage key already exists" -ForegroundColor Yellow
    } else {
        Write-Host "Azure storage key does not exist yet, creating..." -ForegroundColor Yellow
        $AzureStorageKeys = New-AzureRmStorageAccountKey -ResourceGroupName $AzureResourceGroupName -Name $AzureStorageAccount -KeyName "Key1"
    }
    
    $AzureStorageSAKey = ($AzureStorageKeys | Where-Object {$_.KeyName -eq "Key1"}).Value

# Various
    $ResourceProviders = @("microsoft.resources", "microsoft.compute");
    if ($ResourceProviders.Length) {
        Write-Host "Registering Resource Providers" -ForegroundColor Yellow
        foreach ($ResourceProvider in $ResourceProviders) {
            RegisterRP($ResourceProvider);
        }
    }

    if (!(Test-Path -Path $LocalTempFolder -ErrorAction SilentlyContinue)) {
        New-Item -ItemType Directory -Path $LocalTempFolder -Force
    }

    $AzureSubscription = Get-AzureRmSubscription | Select-Object -First 1
    $AzureSubscriptionId = $AzureSubscription.Id

# Azure - Create Cloud Connector virtual machine
    Write-Host "8. Azure - Create Cloud Connector Virtual Machine x 2" -ForegroundColor Green

# Various
    $CloudConnectorNIName1 = $CloudConnectorMachineName1 + "01"
	$CloudConnectorNIName2 = $CloudConnectorMachineName2 + "02"

# Start the deployment CC 1
    Write-Host "Starting Cloud Connector" $CloudConnectorMachineName1 "deployment. This can take few minutes..." -ForegroundColor Yellow
    New-AzureRmResourceGroupDeployment -ResourceGroupName $AzureResourceGroupName -Name "CloudConnector" -TemplateUri 'https://raw.githubusercontent.com/ArnaudPain/Citrix-Azure/master/Azure-Citrix-Cloud-Connector-Deployment-Template-2016.json' `
        -Location $AzureResourceGroupLocation `
		-NetworkInterfaceName $CloudConnectorNIName1 `
        -SubnetName $AzureSubnetName `
        -VirtualNetworkId "/subscriptions/$AzureSubscriptionId/resourceGroups/$AzureVNetResourceGroupName/providers/Microsoft.Network/virtualNetworks/$AzureVNetName" `
        -VirtualMachineName $CloudConnectorMachineName1 `
        -VirtualMachineRG $AzureResourceGroupName `
        -OSDiskType $CloudConnectorDiskType `
        -VirtualMachineSize $CloudConnectorMachineType `
        -AdminUsername $CloudConnectorAdminUsername `
        -AdminPassword $CloudConnectorAdminPassword `
        -DiagnosticsStorageAccountName $AzureDiagnosticsStorageAccountName `
        -DiagnosticsStorageAccountId "/subscriptions/$AzureSubscriptionId/resourceGroups/$AzureDiagnosticResourceGroupName/providers/Microsoft.Storage/storageAccounts/$AzureDiagnosticsStorageAccountName"
	Restart-AzureRmVM -ResourceGroupName $AzureResourceGroupName -Name $CloudConnectorMachineName1 
	Start-Sleep -Seconds 60
	
# Domain join CC 1
    Write-Host "Cloud connector" $CloudConnectorMachineName1 "created, joining machine to domain and restarting" -ForegroundColor Yellow
    Get-AzureRmVM -ResourceGroupName $AzureResourceGroupName | Where-Object { $_.Name -like $CloudConnectorMachineName1 } | Add-JDAzureRMVMToDomain -DomainName $DomainName 
    Start-Sleep -Seconds 30
    Restart-AzureRmVM -ResourceGroupName $AzureResourceGroupName -Name $CloudConnectorMachineName1 

# Start the deployment CC 2
    Write-Host "Starting Cloud Connector" $CloudConnectorMachineName2 "deployment. This can take few minutes..." -ForegroundColor Yellow
    New-AzureRmResourceGroupDeployment -ResourceGroupName $AzureResourceGroupName -Name "CloudConnector" -TemplateUri 'https://raw.githubusercontent.com/ArnaudPain/Citrix-Azure/master/Azure-Citrix-Cloud-Connector-Deployment-Template-2016.json' `
        -Location $AzureResourceGroupLocation `
		-NetworkInterfaceName $CloudConnectorNIName2 `
        -SubnetName $AzureSubnetName `
        -VirtualNetworkId "/subscriptions/$AzureSubscriptionId/resourceGroups/$AzureVNetResourceGroupName/providers/Microsoft.Network/virtualNetworks/$AzureVNetName" `
        -VirtualMachineName $CloudConnectorMachineName2 `
        -VirtualMachineRG $AzureResourceGroupName `
        -OSDiskType $CloudConnectorDiskType `
        -VirtualMachineSize $CloudConnectorMachineType `
        -AdminUsername $CloudConnectorAdminUsername `
        -AdminPassword $CloudConnectorAdminPassword `
        -DiagnosticsStorageAccountName $AzureDiagnosticsStorageAccountName `
        -DiagnosticsStorageAccountId "/subscriptions/$AzureSubscriptionId/resourceGroups/$AzureDiagnosticResourceGroupName/providers/Microsoft.Storage/storageAccounts/$AzureDiagnosticsStorageAccountName"
    Restart-AzureRmVM -ResourceGroupName $AzureResourceGroupName -Name $CloudConnectorMachineName2 
	Start-Sleep -Seconds 60

# Domain join CC2
    Write-Host "Cloud connector" $CloudConnectorMachineName2 "created, joining machine to domain and restarting" -ForegroundColor Yellow
    Get-AzureRmVM -ResourceGroupName $AzureResourceGroupName | Where-Object { $_.Name -like $CloudConnectorMachineName2 } | Add-JDAzureRMVMToDomain -DomainName $DomainName 
    Start-Sleep -Seconds 30
    Restart-AzureRmVM -ResourceGroupName $AzureResourceGroupName -Name $CloudConnectorMachineName2 
 

    Write-Host "9. Citrix Cloud/Azure - Deploy Cloud Connector software on Server 1" -ForegroundColor Green
    $AzureStorageContainerName1 = "cloudconinstaller1"

# Create Cloud Connector deployment script
    $DeployCloudConnectorScriptContent = "
        `$CustomerID = `"$CustomerID`"
        `$ClientID = `"$ClientID`" 
        `$ClientSecret = `"$ClientSecret`" 
        `$CTXCloudResourceID = `"$CTXCloudResourceID`"

        `$Username = `"arnaudpain/ftp@arnaud.biz`"
		`$Password = `"9$<rZK-k`"
		`$LocalFile = `"C:\cwcconnector.exe`"
		`$RemoteFile = `"ftp://arnaudpain.sharefileftp.com/automation/cwcconnector.exe`"
		
		`$FTPRequest = [System.Net.FtpWebRequest]::Create(`$RemoteFile)
		`$FTPRequest.Credentials = New-Object System.Net.NetworkCredential(`$Username,`$Password)
		`$FTPRequest.Method = [System.Net.WebRequestMethods+Ftp]::DownloadFile
		`$FTPRequest.UseBinary = `$true
		`$FTPRequest.KeepAlive = `$false
		`$FTPResponse = `$FTPRequest.GetResponse()
		`$ResponseStream = `$FTPResponse.GetResponseStream()
		`$LocalFileFile = New-Object IO.FileStream (`$LocalFile,[IO.FileMode]::Create)
		`[byte[]]`$ReadBuffer = New-Object byte[] 1024
		`do {
		`$ReadLength = `$ResponseStream.Read(`$ReadBuffer,0,1024)
		`$LocalFileFile.Write(`$ReadBuffer,0,`$ReadLength)
		`}
		`while (`$ReadLength -ne 0)
		`$LocalFileFile.Close()
		`$Arguments = `"/q /customername:`$CustomerID /clientid:`$ClientID /clientsecret:`$ClientSecret /location:`$CTXCloudResourceID /acceptTermsofservice:true`"
        Start-Process `$LocalFile `$Arguments -Wait"

    $ScriptFile = "InstallCloudCon1.ps1"
    $LocalScriptFile = "$LocalTempFolder\$ScriptFile"
    Set-Content -Path $LocalScriptFile -Value $DeployCloudConnectorScriptContent -Force

    $TempScriptContent = Get-Content -Path $LocalTempFolder\$ScriptFile 
    $TempScriptContent = $TempScriptContent -Replace "\?", ""
    Set-Content -Path $LocalScriptFile -Value $TempScriptContent -Force
    
# Upload Cloud Connector deployment script
    $AzureStorageContext = New-AzureStorageContext -StorageAccountName $AzureStorageAccountname -StorageAccountKey $AzureStorageSAKey
    Set-AzureRmCurrentStorageAccount -Context $AzureStorageContext
    New-AzureStorageContainer -Name $AzureStorageContainerName1
    Set-AzureStorageBlobContent -File $LocalScriptFile -container $AzureStorageContainerName1 -Force
    
    Set-AzureRmVMCustomScriptExtension -Name 'Cloudcon-Installer' -ContainerName $AzureStorageContainerName1 -FileName $ScriptFile -StorageAccountName $AzureStorageAccountName -ResourceGroupName $AzureResourceGroupName -VMName $CloudConnectorMachineName1 -Run "installcloudcon1.ps1" -Location $AzureResourceGroupLocation
    Start-Sleep -Seconds 10

    Write-Host "Citrix Cloud Connector installation succesful, cleaning up..." -ForegroundColor Yellow

# Remove Extension and Script
    Remove-AzureRmVMCustomScriptExtension -ResourceGroupName $AzureResourceGroupName -VMName $CloudConnectorMachineName1 -Name 'Cloudcon-Installer1' -Force 

# Delete storage container
    Remove-AzureStorageContainer -name $AzureStorageContainerName1 -Force
 
    Write-Host "10. Citrix Cloud/Azure - Deploy Cloud Connector software on Server 2" -ForegroundColor Green
    $AzureStorageContainerName2 = "cloudconinstaller2"

# Create Cloud Connector deployment script
    $DeployCloudConnectorScriptContent = "
        `$CustomerID = `"$CustomerID`"
        `$ClientID = `"$ClientID`" 
        `$ClientSecret = `"$ClientSecret`" 
        `$CTXCloudResourceID = `"$CTXCloudResourceID`"

        `$Username = `"arnaudpain/ftp@arnaud.biz`"
		`$Password = `"9$<rZK-k`"
		`$LocalFile = `"C:\cwcconnector.exe`"
		`$RemoteFile = `"ftp://arnaudpain.sharefileftp.com/automation/cwcconnector.exe`"
		
		`$FTPRequest = [System.Net.FtpWebRequest]::Create(`$RemoteFile)
		`$FTPRequest.Credentials = New-Object System.Net.NetworkCredential(`$Username,`$Password)
		`$FTPRequest.Method = [System.Net.WebRequestMethods+Ftp]::DownloadFile
		`$FTPRequest.UseBinary = `$true
		`$FTPRequest.KeepAlive = `$false
		`$FTPResponse = `$FTPRequest.GetResponse()
		`$ResponseStream = `$FTPResponse.GetResponseStream()
		`$LocalFileFile = New-Object IO.FileStream (`$LocalFile,[IO.FileMode]::Create)
		`[byte[]]`$ReadBuffer = New-Object byte[] 1024
		`do {
		`$ReadLength = `$ResponseStream.Read(`$ReadBuffer,0,1024)
		`$LocalFileFile.Write(`$ReadBuffer,0,`$ReadLength)
		`}
		`while (`$ReadLength -ne 0)
		`$LocalFileFile.Close()
		`$Arguments = `"/q /customername:`$CustomerID /clientid:`$ClientID /clientsecret:`$ClientSecret /location:`$CTXCloudResourceID /acceptTermsofservice:true`"
        Start-Process `$LocalFile `$Arguments -Wait"

    $ScriptFile = "InstallCloudCon2.ps1"
    $LocalScriptFile = "$LocalTempFolder\$ScriptFile"
    Set-Content -Path $LocalScriptFile -Value $DeployCloudConnectorScriptContent -Force

    $TempScriptContent = Get-Content -Path $LocalTempFolder\$ScriptFile 
    $TempScriptContent = $TempScriptContent -Replace "\?", ""
    Set-Content -Path $LocalScriptFile -Value $TempScriptContent -Force
    
# Upload Cloud Connector deployment script
    $AzureStorageContext = New-AzureStorageContext -StorageAccountName $AzureStorageAccountname -StorageAccountKey $AzureStorageSAKey
    Set-AzureRmCurrentStorageAccount -Context $AzureStorageContext
    New-AzureStorageContainer -Name $AzureStorageContainerName2
    Set-AzureStorageBlobContent -File $LocalScriptFile -container $AzureStorageContainerName2 -Force
    
    Set-AzureRmVMCustomScriptExtension -Name 'Cloudcon-Installer' -ContainerName $AzureStorageContainerName2 -FileName $ScriptFile -StorageAccountName $AzureStorageAccountName -ResourceGroupName $AzureResourceGroupName -VMName $CloudConnectorMachineName2 -Run "installcloudcon2.ps1" -Location $AzureResourceGroupLocation
    Start-Sleep -Seconds 10

    Write-Host "Citrix Cloud Connector installation succesful, cleaning up..." -ForegroundColor Yellow

# Remove Extension and Script
    Remove-AzureRmVMCustomScriptExtension -ResourceGroupName $AzureResourceGroupName -VMName $CloudConnectorMachineName2 -Name 'Cloudcon-Installer2' -Force 

# Delete storage container
    Remove-AzureStorageContainer -name $AzureStorageContainerName2 -Force

# Present timing
    $ScriptStopWatch.Stop()
    $ScriptRunningTime = [math]::Round($ScriptStopWatch.Elapsed.TotalMinutes,1)
    Write-Host "Script ran for" $ScriptRunningTime "Minutes" -ForegroundColor Magenta
# -------------------------------
