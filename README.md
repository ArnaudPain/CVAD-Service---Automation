# CVAD-Service---Automation

You will find here 4 Powershell Script to help you to migrate CVAD to CVAD Service.

Base on your the following choice to be made:

Citrix on Azure:
1. Use script site-to-site.ps1 if you want to connect your on-premise to Azure with Cisco Meraki MX80.
2. Use script cvad-to-cvad-service-azure-cc.ps1 to deploy 2 Windows Server 2016, join your domain, download and deploy Cloud Connector.

Citrix on-prem:
1. Use script deploy-cc-premises.ps1 to deploy 2 cloud connector on your vSphere (remote-cc.ps1 need to be present on your C:\ drive before running the script).

Migrate:
1. Use script run-cvad-tool.ps1.

All the script that will be used need to be downloaded directly on your C:\ drive.

You will have to provide information in each script before running.
