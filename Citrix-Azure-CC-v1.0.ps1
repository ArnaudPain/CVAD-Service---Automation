#This File is in Unicode format. Do not edit in an ASCII editor. Notepad++ UTF-8-BOM

#region help text
<#
.SYNOPSIS
	Deploy 2 Windows Server 2016 or 2019 on Azure, domain join and deploy Citrix Cloud Connector in Azure

.PREREQUISITES
	Requires a valid Azure subscription with Resource Groups and Virtual Network configured
	Requires -RunAsAdministrator (or elevated PowerShell session)
	Requires existing domain controller (powered on!)
	Requires a Citrix Cloud API key see --> https://docs.citrix.com/en-us/citrix-cloud/citrix-cloud-management/identity-access-management.html
	Requires Active Directory on Azure or Site to Site connectivity between Azure and on-premises
	
.DESCRIPTION
	The script will create Resource Location in Citrix Cloud (name to be provided during the script run)
	It will deploy 2 VMs in Azure based on Windows Server 2016 or 2019 Template (to be selected during the script run)
	When VMs are deployed they will be domain-joined (domain and credentials to be provided during the script run)
	Citrix Cloud Connector software is downloaded from your Citrix Cloud account and deployed on each server

.INPUTS
	You will have to first fill the data.json file before running this script.
	data.json need to be in same folder as this script.

.NOTES
	NAME: Citrix-Azure-CC-v1.0.ps1
	VERSION: 1.00
	AUTHOR: Arnaud Pain
	LASTEDIT: September 17, 2020
	Copyright (c) Arnaud Pain. All rights reserved.
#>
#endregion

# VARIABLES 
$jsonObj = get-content customerspecific.json | ConvertFrom-Json
$CustomerID=$jsonObj.CustomerID
$ClientID=$jsonObj.ClientID
$ClientSecret=$jsonObj.ClientSecret
$AzureResourceGroupLocation=$jsonObj.AzureResourceGroupLocation
$AzureVNetName=$jsonObj.AzureVNetName
$AzureResourceGroupName=$jsonObj.AzureResourceGroupName
$DomainName=$jsonObj.DomainName
$CTX_Resource_Location_Name=$jsonObj.CTX_Resource_Location_Name
$OSType=$jsonObj.OSType
$CloudConnector1MachineName=$jsonObj.CloudConnector1MachineName
$CloudConnector2MachineName=$jsonObj.CloudConnector2MachineName
$CloudConnectorMachineType=$jsonObj.CloudConnectorMachineType
$CloudConnectorDiskType=$jsonObj.CloudConnectorDiskType
$AzureSubnetName=$jsonObj.AzureSubnetName
$CloudConnectorAdminUsername=$jsonObj.CloudConnectorAdminUsername
$CloudConnectorAdminPassword=ConvertTo-SecureString $jsonObj.CloudConnectorAdminPassword -AsPlainText -Force
$Domainuser=$jsonObj.Domainuser
$Domainuserpwd=ConvertTo-SecureString $jsonObj.Domainuserpwd -AsPlainText -Force  
$AzureVNetResourceGroupName = $AzureResourceGroupName # Azure Virtual Network Resource Group Name will be equal to Azure Resource Group
$AzureDiagnosticsStorageAccountName = "diagsa" + -join ((48..57) + (97..122) | Get-Random -Count 12 | % {[char]$_}) # Create a random 12 caracters name starting with diagsa for Diagnostic Storage Account
$AzureDiagnosticResourceGroupName = $AzureResourceGroupName #  Azure Diagnostic Resource Group Name will be equal to Azure Resource Group
$AzureStorageAccountName = "sa" + -join ((48..57) + (97..122) | Get-Random -Count 12 | % {[char]$_})# Create a random 12 caracters name starting with sa for Storage Account
$CloudConnector1NICName = $CloudConnector1MachineName + "_NIC" # Define CloudConnector1MachineName NIC Name 
$CloudConnector2NICName = $CloudConnector2MachineName + "_NIC"# Define CloudConnector2MachineName NIC Name
$TrustURL = "https://trust.citrixworkspacesapi.net/root/tokens/clients"
$CloudConnectorDeploymentTemplateFile = "https://raw.githubusercontent.com/ArnaudPain/CVAD-Service---Automation/master/Azure-Citrix-Cloud-Connector-Deployment-Template-"+$OSType+".json"
$LocalTempFolder = "C:\Temp"
$UsersGroupName = "Domain Users"

# PREREQUISITES 
# Setup script running time
    $ScriptStopWatch = [System.Diagnostics.StopWatch]::StartNew()

# Check if user is admin and script is running elevated
    $CurrentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (!($CurrentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))) {
        Write-Host "User does not have admin rights. Are you running this in an elevated session?" -foregroundcolor red
		Write-Host "Stopping script." -foregroundcolor red
        Return
    }

# Enable TLS 1.2 required for Citrix Bearer Token
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# DEFINE FUNCTIONS
    Function Add-JDAzureRMVMToDomain #Credit to Johan https://365lab.net/2016/02/25/domain-join-azurerm-vms-with-powershell/ 
	{ 
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

# IMPORT MODULES
# Azure - Install and Import Azure RM PowerShell modules
    Write-Host "Step 1/10 Install and Import Azure RM PowerShell modules" -ForegroundColor Green
    if (Get-Module -ListAvailable -Name AzureRM) {
        Write-Host "Azure RM module already available, importing..." -ForegroundColor Yellow
        Import-Module AzureRM | Out-Null
    } else {
        Write-Host "Azure RM module not yet available, installing..." -ForegroundColor Yellow
        Install-Module -Name AzureRM -scope AllUsers -Confirm:$false -force
        Import-Module AzureRM | Out-Null
    }

# AUTHENTICATION 
    Write-Host "Step 2/10 Ask user for credentials" -ForegroundColor Green
# Azure
    Write-Host "Azure login" -ForegroundColor Blue -BackgroundColor white
	Login-AzureRmAccount | out-null
	
# Define Domain credentials    
    $ADCredentials = new-object -typename System.Management.Automation.PSCredential -argumentlist $domainuser, $domainuserpwd

# IMPORT MODULES (CONTINUE)
# Azure - Install and Import Azure Active Directory module    
    Write-Host "Step 3/10 Install and Import Azure AD PowerShell modules" -ForegroundColor Green
    if (Get-Module -ListAvailable -Name AzureAD) {
        Write-Host "Azure AD module already available, importing..." -ForegroundColor Yellow
        Import-Module AzureAD | Out-Null
    } else {
        Write-Host "Azure AD module not yet available, installing..." -ForegroundColor Yellow
        Install-Module -Name AzureAD -Scope AllUsers -Confirm:$false -Force
        Import-Module AzureAD | Out-Null
    }

# MAIN SCRIPT 
# Citrix Cloud - Bearer Token
    Write-Host "Step 4/10 Citrix Cloud - Get Bearer Token" -ForegroundColor Green
    $Body = @{
        "ClientId"     = $ClientID;
        "ClientSecret" = $ClientSecret
    }
    $PostHeaders = @{
        "Content-Type" = "application/json"
    } 
    
    $Response = Invoke-RestMethod -Uri $TrustURL -Method POST -Body (ConvertTo-Json -InputObject $Body) -Headers $PostHeaders
    $BearerToken = $Response.token   
    $Token = "CwsAuth Bearer=" + $BearerToken

# Citrix Cloud - Create Resource Location
    Write-Host "Step 5/10 Citrix Cloud - Create Resource Location" -ForegroundColor Green
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
    Write-Host "Step 6/10 Azure - Create Azure resource groups (if needed)" -ForegroundColor Green

# Check for existing resource group and create new one if needed
    $AzureResourceGroup = Get-AzureRmResourceGroup -Name $AzureResourceGroupName -ErrorAction SilentlyContinue
    if (!$AzureResourceGroup) {
        Write-Host "Resource group '$AzureResourceGroupName' does not exist yet" -ForegroundColor Yellow
        Write-Host "Creating resource group '$AzureResourceGroupName' in location '$AzureResourceGroupLocation'" -ForegroundColor Yellow
        New-AzureRmResourceGroup -Name $AzureResourceGroupName -Location $AzureResourceGroupLocation >$null
    } else {
        Write-Host "Using existing resource group '$AzureResourceGroupName'" -ForegroundColor Yellow
    }

    if ($AzureVNetResourceGroupName -ne $AzureResourceGroupName) {
        Write-Host "Different resource group specified for Virtual Networks" -ForegroundColor Yellow
        $AzureVNetResourceGroup = Get-AzureRmResourceGroup -Name $AzureVNetResourceGroupName -ErrorAction SilentlyContinue
        if (!$AzureVNetResourcegroup) {
            Write-Host "Virtual network resource group '$AzureVNetResourceGroupName' does not exist yet" -ForegroundColor Yellow
            Write-Host "Creating virtual network resource group '$AzureVNetResourceGroupName' in location '$AzureResourceGroupLocation'" -ForegroundColor Yellow
            New-AzureRmResourceGroup -Name $AzureVNetResourceGroupName -Location $AzureResourceGroupLocation >$null
        }
		else {
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
            New-AzureRmResourceGroup -Name $AzureDiagnosticResourceGroupName -Location $AzureResourceGroupLocation >$null
		}
		else {
            Write-Host "Using existing diagnostic virtual network resource group '$AzureDiagnosticResourceGroupName'" -ForegroundColor Yellow 
        }
    } else {
        Write-Host "Specified diagnostic resource group is identical to the VM resource group" -ForegroundColor Yellow
    }

# Create Azure storage account
    Write-Host "Step 7/10 Azure - Create Azure storage accounts (if needed)" -ForegroundColor Green

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
        New-AzureRmStorageAccount -ResourceGroupName $AzureDiagnosticResourceGroupName -Name $AzureDiagnosticsStorageAccountName -SkuName Standard_LRS -Location $AzureResourceGroupLocation >$null
    }

# Check for existing storage keys and create new one if needed
    if ($AzureStorageKeys = Get-AzureRMStorageAccountKey -ResourceGroupName $AzureResourceGroupName -Name $AzureStorageAccount -ErrorAction SilentlyContinue | Where-Object{$_.KeyName -eq "Key1"}) {
        Write-Host "Azure storage key already exists" -ForegroundColor Yellow
    } else {
        Write-Host "Azure storage key does not exist yet, creating..." -ForegroundColor Yellow
        $AzureStorageKeys = New-AzureRmStorageAccountKey -ResourceGroupName $AzureResourceGroupName -Name $AzureStorageAccount -KeyName "Key1"
    }
    
    $AzureStorageSAKey = ($AzureStorageKeys | Where-Object {$_.KeyName -eq "Key1"}).Value 

# Retrieve Subscription ID
    $AzureSubscriptionId = Get-AzureRmSubscription | Select-Object -Last 1 -ExpandProperty Id # Here I used -Last 1 as the subscription I want to use appears in last place

# Azure - Create Cloud Connector virtual machine
    Write-Host "Step 8/10 Azure - Create Cloud Connector Virtual Machine x 2" -ForegroundColor Green
# Start the deployment CC 1
    Write-Host "Starting Cloud Connector" $CloudConnector1MachineName "deployment..." -ForegroundColor Yellow
    New-AzureRmResourceGroupDeployment -ResourceGroupName $AzureResourceGroupName -Name "CloudConnector" -TemplateUri $CloudConnectorDeploymentTemplateFile `
        -Location $AzureResourceGroupLocation `
        -NetworkInterfaceName $CloudConnector1NICName `
        -SubnetName $AzureSubnetName `
        -VirtualNetworkId "/subscriptions/$AzureSubscriptionId/resourceGroups/$AzureVNetResourceGroupName/providers/Microsoft.Network/virtualNetworks/$AzureVNetName" `
        -VirtualMachineName $CloudConnector1MachineName `
        -VirtualMachineRG $AzureResourceGroupName `
        -OSDiskType $CloudConnectorDiskType `
        -VirtualMachineSize $CloudConnectorMachineType `
        -AdminUsername $CloudConnectorAdminUsername `
        -AdminPassword $CloudConnectorAdminPassword `
        -DiagnosticsStorageAccountName $AzureDiagnosticsStorageAccountName `
        -DiagnosticsStorageAccountId "/subscriptions/$AzureSubscriptionId/resourceGroups/$AzureDiagnosticResourceGroupName/providers/Microsoft.Storage/storageAccounts/$AzureDiagnosticsStorageAccountName"  >$null
 	
# Domain join CC 1
    Write-Host "Cloud connector" $CloudConnector1MachineName "created, joining machine to domain and restarting" -ForegroundColor Yellow
    Get-AzureRmVM -ResourceGroupName $AzureResourceGroupName | Where-Object { $_.Name -like $CloudConnector1MachineName } | Add-JDAzureRMVMToDomain -DomainName $DomainName | out-null

# Start the deployment CC 2
    Write-Host "Starting Cloud Connector" $CloudConnector2MachineName "deployment..." -ForegroundColor Yellow
    New-AzureRmResourceGroupDeployment -ResourceGroupName $AzureResourceGroupName -Name "CloudConnector" -TemplateUri $CloudConnectorDeploymentTemplateFile `
        -Location $AzureResourceGroupLocation `
        -NetworkInterfaceName $CloudConnector2NICName `
        -SubnetName $AzureSubnetName `
        -VirtualNetworkId "/subscriptions/$AzureSubscriptionId/resourceGroups/$AzureVNetResourceGroupName/providers/Microsoft.Network/virtualNetworks/$AzureVNetName" `
        -VirtualMachineName $CloudConnector2MachineName `
        -VirtualMachineRG $AzureResourceGroupName `
        -OSDiskType $CloudConnectorDiskType `
        -VirtualMachineSize $CloudConnectorMachineType `
        -AdminUsername $CloudConnectorAdminUsername `
        -AdminPassword $CloudConnectorAdminPassword `
        -DiagnosticsStorageAccountName $AzureDiagnosticsStorageAccountName `
        -DiagnosticsStorageAccountId "/subscriptions/$AzureSubscriptionId/resourceGroups/$AzureDiagnosticResourceGroupName/providers/Microsoft.Storage/storageAccounts/$AzureDiagnosticsStorageAccountName"  >$null
	
# Domain join CC2
    Write-Host "Cloud connector" $CloudConnector2MachineName "created, joining machine to domain and restarting" -ForegroundColor Yellow
    Get-AzureRmVM -ResourceGroupName $AzureResourceGroupName | Where-Object { $_.Name -like $CloudConnector2MachineName } | Add-JDAzureRMVMToDomain -DomainName $DomainName | out-null

# Cloud Connector deployment script
    $DeployCloudConnectorScriptContent = "
		[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
		`$CustomerID = `"$CustomerID`"
        `$ClientID = `"$ClientID`" 
        `$ClientSecret = `"$ClientSecret`" 
        `$CTXCloudResourceID = `"$CTXCloudResourceID`"

        `$LocalFile = `"C:\cwcconnector.exe`"
		`$downloadsUri = `"https://downloads.cloud.com/`" + `$CustomerID + `"/connector/cwcconnector.exe`"
		`Invoke-WebRequest -Uri `$downloadsUri -OutFile `$LocalFile
		       
		`$Arguments = `"/q /customername:`$CustomerID /clientid:`$ClientID /clientsecret:`$ClientSecret /location:`$CTXCloudResourceID /acceptTermsofservice:true`"
        Start-Process `$LocalFile `$Arguments -Wait"

# Deploy Cloud Connector on Server 1
    Write-Host "Step 9/10 Citrix Cloud - Deploy Cloud Connector software on Server 1" -ForegroundColor Green
    $AzureStorageContainerName1 = -join ((48..57) + (97..122) | Get-Random -Count 12 | % {[char]$_})  # Create a random 12 caracters name 
    $ScriptFile = "InstallCloudCon.ps1"
	$LocalScriptFile = "$LocalTempFolder\$ScriptFile"
    Set-Content -Path $LocalScriptFile -Value $DeployCloudConnectorScriptContent -Force
	$TempScriptContent = Get-Content -Path $LocalTempFolder\$ScriptFile
    $TempScriptContent = $TempScriptContent -Replace "\?", ""
    Set-Content -Path $LocalScriptFile -Value $TempScriptContent -Force
    
# Upload Cloud Connector deployment script
    $AzureStorageContext = New-AzureStorageContext -StorageAccountName $AzureStorageAccountname -StorageAccountKey $AzureStorageSAKey
    Set-AzureRmCurrentStorageAccount -Context $AzureStorageContext | out-null
    New-AzureStorageContainer -Name $AzureStorageContainerName1 | out-null
    Set-AzureStorageBlobContent -File $LocalScriptFile -container $AzureStorageContainerName1 -Force | out-null
    
    Set-AzureRmVMCustomScriptExtension -Name 'InstallCloudCon1' -ContainerName $AzureStorageContainerName1 -FileName $ScriptFile -StorageAccountName $AzureStorageAccountName -ResourceGroupName $AzureResourceGroupName -VMName $CloudConnector1MachineName -Run "InstallCloudCon.ps1" -Location $AzureResourceGroupLocation | out-null
    
    Write-Host "Citrix Cloud Connector installation succesful, cleaning up..." -ForegroundColor Yellow

# Remove Extension and Script
    Remove-AzureRmVMCustomScriptExtension -ResourceGroupName $AzureResourceGroupName -VMName $CloudConnector1MachineName -Name 'InstallCloudCon1' -Force | out-null

# Delete storage container
    Remove-AzureStorageContainer -name $AzureStorageContainerName1 -Force | out-null

# Deploy Cloud Connector on Server 2
    Write-Host "Step 10/10 Citrix Cloud - Deploy Cloud Connector software on Server 2" -ForegroundColor Green
    $AzureStorageContainerName2 = -join ((48..57) + (97..122) | Get-Random -Count 12 | % {[char]$_})  # Create a random 12 caracters name 
    
# Upload Cloud Connector deployment script
    $AzureStorageContext = New-AzureStorageContext -StorageAccountName $AzureStorageAccountname -StorageAccountKey $AzureStorageSAKey
    Set-AzureRmCurrentStorageAccount -Context $AzureStorageContext | out-null
    New-AzureStorageContainer -Name $AzureStorageContainerName2 | out-null
    Set-AzureStorageBlobContent -File $LocalScriptFile -container $AzureStorageContainerName2 -Force | out-null
    
    Set-AzureRmVMCustomScriptExtension -Name 'InstallCloudCon2' -ContainerName $AzureStorageContainerName2 -FileName $ScriptFile -StorageAccountName $AzureStorageAccountName -ResourceGroupName $AzureResourceGroupName -VMName $CloudConnector2MachineName -Run "InstallCloudCon.ps1" -Location $AzureResourceGroupLocation | out-null
    
    Write-Host "Citrix Cloud Connector installation succesful, cleaning up..." -ForegroundColor Yellow

# Remove Extension and Script
    Remove-AzureRmVMCustomScriptExtension -ResourceGroupName $AzureResourceGroupName -VMName $CloudConnector2MachineName -Name 'InstallCloudCon2' -Force | out-null

# Delete storage container
    Remove-AzureStorageContainer -name $AzureStorageContainerName2 -Force | out-null
 
# Present timing
    $ScriptStopWatch.Stop()
    $ScriptRunningTime = [math]::Round($ScriptStopWatch.Elapsed.TotalMinutes,1)
    Write-Host "Script ran for" $ScriptRunningTime "Minutes" -ForegroundColor Magenta -BackgroundColor White

# END OF SCRIPT
