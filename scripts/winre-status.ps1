# winre-status.ps1
# Query WinRE status using reagentc and provide helper commands

Write-Output "[winre-status] reagentc /info"
reagentc /info

Write-Output "To enable WinRE: reagentc /enable"
Write-Output "To set WinRE image location: reagentc /setreimage /path C:\Recovery\WindowsRE"

Write-Output "winre-status.ps1 completed"
