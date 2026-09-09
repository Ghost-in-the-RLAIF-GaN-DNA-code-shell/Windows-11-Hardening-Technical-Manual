# servicing-health.ps1
# Run DISM and SFC health checks. RUN AS ADMIN.

Write-Output "[servicing-health] Checking component store health (DISM)"
DISM /Online /Cleanup-Image /CheckHealth
DISM /Online /Cleanup-Image /ScanHealth

Write-Output "[servicing-health] Attempting restore (may use Windows Update)"
DISM /Online /Cleanup-Image /RestoreHealth

Write-Output "[servicing-health] Running SFC"
sfc /scannow

Write-Output "servicing-health.ps1 completed"
