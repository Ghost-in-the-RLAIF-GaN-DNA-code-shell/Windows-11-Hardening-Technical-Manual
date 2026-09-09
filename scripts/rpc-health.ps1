# rpc-health.ps1
# Check RpcSs and RpcEptMapper service health and endpoint mapper connectivity

param(
    [switch]$VerboseOutput
)

function Write-Log { param($m) Write-Output "[rpc-health] $m" }

Write-Log "Checking RpcSs and RpcEptMapper services"
Get-Service -Name RpcSs,RpcEptMapper | Select-Object Name,Status,StartType | Format-Table -AutoSize

Write-Log "Testing local endpoint mapper (TCP 135)"
Test-NetConnection -ComputerName 127.0.0.1 -Port 135 -InformationLevel Detailed

if ($VerboseOutput) {
    Write-Log "Inspecting RPC registry keys (informational)"
    Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Services\RpcEptMapper","HKLM:\SYSTEM\CurrentControlSet\Services\RpcSs" -ErrorAction SilentlyContinue | Format-List
}

Write-Log "rpc-health completed"
