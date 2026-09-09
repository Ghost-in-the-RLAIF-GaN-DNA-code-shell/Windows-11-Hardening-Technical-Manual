# summary-dx.ps1
# Orchestrator: run diagnostics scripts and write a timestamped report to %ProgramData%\Win11UpgradeDiag\

$OutputDir = "$env:ProgramData\Win11UpgradeDiag"
if (-not (Test-Path $OutputDir)) { New-Item -Path $OutputDir -ItemType Directory -Force | Out-Null }
$Time = Get-Date -Format yyyy-MM-dd_HH-mm-ss
$Report = Join-Path $OutputDir "diag-report-$Time.txt"

"Windows 11 Upgrade Diagnostic Report - $Time" | Out-File $Report -Encoding utf8
"Host: $env:COMPUTERNAME" | Out-File $Report -Append
"User: $env:USERNAME" | Out-File $Report -Append
"---`n" | Out-File $Report -Append

function Append-Section($Title, [scriptblock]$Action) {
    "== $Title ==" | Out-File $Report -Append
    try {
        & $Action *>&1 | Out-File $Report -Append
    } catch {
        "Error running $Title: $_" | Out-File $Report -Append
    }
    "`n" | Out-File $Report -Append
}

Append-Section "rpc-health" { .\rpc-health.ps1 }
Append-Section "firewall-health" { .\firewall-health.ps1 }
Append-Section "update-logs (tail)" { .\update-logs.ps1 }
Append-Section "servicing-health" { .\servicing-health.ps1 }
Append-Section "efi-layout" { .\efi-layout.ps1 }
Append-Section "winre-status" { .\winre-status.ps1 }

"Report written to: $Report" | Out-File $Report -Append
Write-Output "Diagnostic run complete. Report: $Report"
