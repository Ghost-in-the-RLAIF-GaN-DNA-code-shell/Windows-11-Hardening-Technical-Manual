# Windows 11 Upgrade - Runbook Summary

This directory contains the split manual and a set of PowerShell diagnostics and repair scripts to support Windows 11 upgrades where RPC/Firewall/Servicing stack issues are suspected.

Files included:
- docs/manual.md — Full manual and runbook (lessons learned, diagnostics, procedures).
- scripts/*.ps1 — PowerShell scripts for diagnostics and safe repair actions.

How to use
- Clone the repository and check out the branch containing these files.
- Review docs/manual.md for background and runbooks.
- Run scripts from an elevated PowerShell session (Administrator). These scripts are read-only diagnostics unless specifically noted.
- Use summary-dx.ps1 to run the collection and produce a timestamped report at %ProgramData%\Win11UpgradeDiag\

Safety notes
- Do not run repair actions on production systems without a maintenance window.
- The scripts use PowerShell and DISM/SFC; follow the manual guidance for protected services and avoid sc config for RpcEptMapper/RpcSs/MpsSvc.

