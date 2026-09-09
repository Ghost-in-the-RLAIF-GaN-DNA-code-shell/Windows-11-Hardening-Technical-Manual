# firewall-health.ps1
# Check Windows Firewall (MpsSvc) status and basic firewall profile info

Write-Output "[firewall-health] Checking MpsSvc service"
Get-Service -Name MpsSvc | Format-List

Write-Output "[firewall-health] Firewall profiles"
Get-NetFirewallProfile | Format-Table Name,Enabled,DefaultInboundAction,DefaultOutboundAction

Write-Output "[firewall-health] Done"
