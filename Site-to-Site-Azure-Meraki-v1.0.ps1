#Requires -Version 5.0
#This File is in Unicode format. Do not edit in an ASCII editor. Notepad++ UTF-8-BOM

#region help text

<#
.SYNOPSIS
	Configure Site-to-Site VPN between Azure and Meraki MX80 on-premises
.DESCRIPTION
	The script will deploy and configure site-to-site VPN requirement on Azure.
	At the end of the Azure configuration you will have 5 minutes to configure on-premises Meraki before validation occurs.
		
	Requires -RunAsAdministrator (or elevated PowerShell session)
	Requires existing domain controller (powered on!)
	Requires a Citrix Cloud API key see --> https://docs.citrix.com/en-us/citrix-cloud/citrix-cloud-management/identity-access-management.html
	Requires Active Directory on Azure or Site to Site connectivity between Azure and on-premises

.NOTES
	NAME: Site-to-Site-Azure-Meraki-v1.0.ps1
	VERSION: 1.00
	AUTHOR: Arnaud Pain
	LASTEDIT: September 3, 2020
#>
#endregion

# VARIABLES TO BE SET BEFORE RUNNING THE SCRIPT
$Location = "" # To be filled before running the script
$resourceGroupName = "" # To be filled before running the script
$VNName = "" # To be filled before running the script
$VNAddPrefix = "" # To be filled before running the script
$SubAddPrefix = "" # To be filled before running the script
$GWAddPrefix = "" # To be filled before running the script
$subnet1 = New-AzVirtualNetworkSubnetConfig -Name 'GatewaySubnet' -AddressPrefix $GWAddPrefix
$subnet2 = New-AzVirtualNetworkSubnetConfig -Name 'Default' -AddressPrefix $SubAddPrefix
$RemoteName = "" # To be filled before running the script
$AZVNGC = "" # To be filled before running the script
$RemoteIP = '' # To be filled before running the script
$VIPIP = "" # To be filled before running the script
$SecretKey = "" # To be filled before running the script

# MAIN SCRIPT

# Setup script running time
    $ScriptStopWatch = [System.Diagnostics.StopWatch]::StartNew()

# suppress these warning messages
Set-Item Env:\SuppressAzurePowerShellBreakingChangeWarnings "true" 

# Connect to Azure
Write-Host "1. Connect to Azure" -ForegroundColor Green
Connect-AzAccount
Write-Host "Connected to Azure" -ForegroundColor Yellow

# Deploy Resource Group
Write-Host "2. Create Resource Group" -ForegroundColor Green
New-AzResourceGroup -Name $resourceGroupName -Location $Location | Out-Null
Write-Host "Resource Group created" -ForegroundColor Yellow
start-sleep -Seconds 10

#Create Virtual Network
Write-Host "3. New Azure Virtual Network" -ForegroundColor Green
New-AzVirtualNetwork -Name $VNName -ResourceGroupName $resourceGroupName -Location $location -AddressPrefix $VNAddPrefix -Subnet $subnet1, $subnet2 
$virtualNetwork = Get-AzVirtualNetwork 
start-sleep -Seconds 10

# Add a subnet
Write-Host "4. Net Azure Subnet Network" -ForegroundColor Green
$subnetConfig = Get-AzVirtualNetworkSubnetConfig -Name default -VirtualNetwork $virtualNetwork 
start-sleep -Seconds 10

# Associate the subnet to the virtual network
Write-Host "5. Associate Subnet to Azure Virtual Network" -ForegroundColor Green
$virtualNetwork | Set-AzVirtualNetwork 
start-sleep -Seconds 10

# Create Local network gateway
Write-Host "6. Create Local Network Gateway" -ForegroundColor Green\
New-AzLocalNetworkGateway -Name $RemoteName -ResourceGroupName $resourceGroupName -Location $Location -GatewayIpAddress $RemoteIP -AddressPrefix @('192.168.59.0/24','192.168.0.0/24')
start-sleep -Seconds 10

# Request a Public IP AddressPrefix
Write-Host "7. Request Public IP Address Prefix" -ForegroundColor Green
$gwpip= New-AzPublicIpAddress -Name $VIPIP -ResourceGroupName $resourceGroupName -Location $Location -AllocationMethod Dynamic
start-sleep -Seconds 30

# Create the Gateway IP Addressing configuration
Write-Host "8. Create Gateway IP Configuration" -ForegroundColor Green
$vnet = Get-AzVirtualNetwork -Name $VNName -ResourceGroupName $resourceGroupName
$subnet = Get-AzVirtualNetworkSubnetConfig -Name "GatewaySubnet" -VirtualNetwork $vnet
$gwipconfig = New-AzVirtualNetworkGatewayIpConfig -Name gwipconfig1 -SubnetId $subnet.Id -PublicIpAddressId $gwpip.Id
start-sleep -Seconds 10

# Create the VPN Gateway
Write-Host "9. Create VPN Gateway" -ForegroundColor Green
New-AzVirtualNetworkGateway -Name $AZVNGC -ResourceGroupName $resourceGroupName -Location $Location -IpConfigurations $gwipconfig -GatewayType Vpn -VpnType PolicyBased -GatewaySku Basic
start-sleep -Seconds 10

# Configure VPN Device
Write-Host "10. Configure VPN Device" -ForegroundColor Green
Get-AzPublicIpAddress -Name VPN-PIP -ResourceGroupName $resourceGroupName
start-sleep -Seconds 60

# Create the VPN Connection
# Define Variables
$gateway1 = Get-AzVirtualNetworkGateway -Name $AZVNGC -ResourceGroupName $resourceGroupName
$local = Get-AzLocalNetworkGateway -Name LAB-MX80 -ResourceGroupName $resourceGroupName
start-sleep -Seconds 30

# Create the connection
Write-Host "11. Create VPN Connection" -ForegroundColor Green
New-AzVirtualNetworkGatewayConnection -Name $AZVNGC -ResourceGroupName $resourceGroupName -Location $Location -VirtualNetworkGateway1 $gateway1 -LocalNetworkGateway2 $local -ConnectionType IPsec -ConnectionProtocol IKEv1 -RoutingWeight 0 -SharedKey $SecretKey
#Configuration on Meraki need to be done and wait few minutes before running following command

#Timer of 5 minutes to allow Meraki configuration to be done using PIP and Sharedkey
Write-Host "You have 5 minutes to configure your Meraki with the following information:" -ForegroundColor White
Write-Host "The IP Address of the Azure Cloud Gateway is" $gwpip -ForegroundColor Green
Write-Host "The Shared Secret is" $secretKey -ForegroundColor Green
start-sleep -Seconds 600
#Verify the VPN Connection
Get-AzVirtualNetworkGatewayConnection -Name $AZVNGC -ResourceGroupName $resourcegroupName

# Present timing
    $ScriptStopWatch.Stop()
    $ScriptRunningTime = [math]::Round($ScriptStopWatch.Elapsed.TotalMinutes,1)
    Write-Host "Script ran for" $ScriptRunningTime "Minutes" -ForegroundColor Magenta

