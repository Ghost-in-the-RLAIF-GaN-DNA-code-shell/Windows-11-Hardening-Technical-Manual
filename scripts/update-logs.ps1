# update-logs.ps1
# Tail setup/servicing logs and show recent Windows Update related events

$paths = @(
  "$env:windir\Panther\setupact.log",
  "$env:windir\Panther\setuperr.log",
  "$env:windir\Logs\CBS\CBS.log",
  "$env:windir\WindowsUpdate.log"
)

foreach ($p in $paths) {
    if (Test-Path $p) {
        Write-Output "`n=== $p ===`n"
        Get-Content -Path $p -Tail 200 -ErrorAction SilentlyContinue
    } else {
        Write-Output "Missing: $p"
    }
}

Write-Output "Recent Windows Update events (System log, last 200 events)"
Get-WinEvent -LogName System -MaxEvents 200 | Where-Object { $_.Message -match "WindowsUpdate|Update" } | Select TimeCreated,Id,LevelDisplayName,Message | Format-Table -AutoSize

Write-Output "update-logs.ps1 completed"
