# Script to deploy Cloud Connector on-premises
# This File is in Unicode format. Do not edit in an ASCII editor. Notepad++ UTF-8-BOM
# Created by Arnaud Pain
# September, 2020
# Version 1.0

<#
.SYNOPSIS
	This script will configure Azure site-to-site VPN to an on-premises Cisco Meraki MX80
	User will have 5 minutes at the end of the Azure commands to configure Meraki before validation occurs.
	
.NOTES
	NAME: Site-to-Site-v1.0.ps1
	VERSION: 1.00
	AUTHOR: Arnaud Pain
	LASTEDIT: September 12, 2020
    Copyright (c) Arnaud Pain. All rights reserved.
#>


# Setup script running time
    $ScriptStopWatch = [System.Diagnostics.StopWatch]::StartNew()

# suppress these warning messages
Set-Item Env:\SuppressAzurePowerShellBreakingChangeWarnings "true" 

# Set Variables
write-host "Here after you will have 11 questions to answer"
$Location = Read-host "1/11 Provide your Azure Resource Location"
$resourceGroupName = Read-Host "2/11 Provide the name of the Azure Resource Group to create"
$VNName = Read-host "3/11 Provide the name of the Virtual Network to create"
$VNAddPrefix = Read-host "4/11 Provide Azure Virtual Network IP Range"
$SubAddPrefix = Read-host "5/11 Provide Azure Subnet IP Range"
$GWAddPrefix = Read-host "6/11 Provide Azure Gateway Address Prefix"
$subnet1 = New-AzVirtualNetworkSubnetConfig -Name 'GatewaySubnet' -AddressPrefix $GWAddPrefix
$subnet2 = New-AzVirtualNetworkSubnetConfig -Name 'Default' -AddressPrefix $SubAddPrefix
$RemoteName = Read-host "7/11 Provide Azure name for your Meraki"
$AZVNGC = Read-host "8/11 Provide name for the Gateway"
$RemoteIP = Read-host "9/11 Please provide public IP of your Cisco Meraki MX80"
$VIPIP = Read-Host "10/11 Provide a name for the Public IP Address that will be created"
$SecretKey = Read-Host "11/11 Provide the Secret Key"

# Connect to Azure
Write-Host "1. Connect to Azure" -ForegroundColor Green
Connect-AzAccount
Write-Host "Connected to Azure" -ForegroundColor Yellow

# Deploy Resource Group
Write-Host "2. Create Resource Group" -ForegroundColor Green
New-AzResourceGroup -Name $resourceGroupName -Location $Location | Out-Null
Write-Host "Resource Group created" -ForegroundColor Yellow
start-sleep -Seconds 10

Write-Host "3. New Azure Virtual Network" -ForegroundColor Green
#Create Virtual Network
New-AzVirtualNetwork -Name $VNName -ResourceGroupName $resourceGroupName -Location $location -AddressPrefix $VNAddPrefix -Subnet $subnet1, $subnet2 
$virtualNetwork = Get-AzVirtualNetwork 
start-sleep -Seconds 10

Write-Host "4. Net Azure Subnet Network" -ForegroundColor Green
# Add a subnet
$subnetConfig = Get-AzVirtualNetworkSubnetConfig -Name default -VirtualNetwork $virtualNetwork 
start-sleep -Seconds 10

Write-Host "5. Associate Subnet to Azure Virtual Network" -ForegroundColor Green
# Associate the subnet to the virtual network
$virtualNetwork | Set-AzVirtualNetwork 
start-sleep -Seconds 10

Write-Host "6. Create Local Network Gateway" -ForegroundColor Green
# Create Local network gateway
New-AzLocalNetworkGateway -Name $RemoteName -ResourceGroupName $resourceGroupName -Location $Location -GatewayIpAddress $RemoteIP -AddressPrefix @('192.168.59.0/24','192.168.0.0/24')
start-sleep -Seconds 10

Write-Host "7. Request Public IP Address Prefix" -ForegroundColor Green
# Request a Public IP AddressPrefix
$gwpip= New-AzPublicIpAddress -Name $VIPIP -ResourceGroupName $resourceGroupName -Location $Location -AllocationMethod Dynamic
start-sleep -Seconds 30

Write-Host "8. Create Gateway IP Configuration" -ForegroundColor Green
# Create the Gateway IP Addressing configuration
$vnet = Get-AzVirtualNetwork -Name $VNName -ResourceGroupName $resourceGroupName
$subnet = Get-AzVirtualNetworkSubnetConfig -Name "GatewaySubnet" -VirtualNetwork $vnet
$gwipconfig = New-AzVirtualNetworkGatewayIpConfig -Name gwipconfig1 -SubnetId $subnet.Id -PublicIpAddressId $gwpip.Id
start-sleep -Seconds 10

Write-Host "9. Create VPN Gateway" -ForegroundColor Green
# Create the VPN Gateway
New-AzVirtualNetworkGateway -Name $AZVNGC -ResourceGroupName $resourceGroupName -Location $Location -IpConfigurations $gwipconfig -GatewayType Vpn -VpnType PolicyBased -GatewaySku Basic
start-sleep -Seconds 10

Write-Host "10. Configure VPN Device" -ForegroundColor Green
# Configure VPN Device
Get-AzPublicIpAddress -Name VPN-PIP -ResourceGroupName $resourceGroupName
start-sleep -Seconds 60

# Create the VPN Connection
# Set Variables
$gateway1 = Get-AzVirtualNetworkGateway -Name $AZVNGC -ResourceGroupName $resourceGroupName
$local = Get-AzLocalNetworkGateway -Name LAB-MX80 -ResourceGroupName $resourceGroupName
start-sleep -Seconds 30

Write-Host "11. Create VPN Connection" -ForegroundColor Green
# Create the connection
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
# -------------------------------