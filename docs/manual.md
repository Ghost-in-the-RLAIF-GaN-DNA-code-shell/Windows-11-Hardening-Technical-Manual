# Windows 11 Upgrade Failures, RPC/Firewall Interference, Hardening Side‑Effects,
# GRUB Safety, and WinRE Recovery Guide — Lessons Learned 2026

Version: Lessons Learned 2026  
Repository: Ghost-in-the-RLAIF-GaN-DNA-code-shell/Windows-11-Hardening-Technical-Manual

Windows 11 Upgrade Failures, RPC/Firewall Interference, Hardening Side‑Effects,
GRUB Safety, and WinRE Recovery Guide — Lessons Learned 2026
=====================================================================

Summary
-------
This manual consolidates real-world failure cases and remediation patterns for Windows 11 upgrades where RPC, the Windows Firewall service, servicing stack, and hardening policies interfere with Setup. It documents why Setup requires RpcEptMapper, RpcSs, and MpsSvc; explains the correct meaning of common errors (including 0x800706D9 as an RPC endpoint mapper failure); provides PowerShell diagnostics and repair scripts (PowerShell must be used to repair protected services on modern Windows builds); describes safe GRUB/EFI handling and WinRE usage; and preserves local-account survival techniques (no Microsoft account). Use this as an operational runbook and investigative reference.

Table of contents
-----------------
- 1. Key concepts & failure overview
- 2. Why Setup requires RpcEptMapper, RpcSs, MpsSvc, dynamic RPC ports, servicing RPC
- 3. Error classes & root causes (corrected)
- 4. Quick repair (PowerShell) — do NOT use sc config for protected services
- 5. Windows Setup phases and "46%" stall analysis
- 6. Lessons learned (A)
- 7. Hardening interference (B) — table + checklist
- 8. PowerShell diagnostics & scripts (C)
- 9. GRUB + Windows dual‑boot safety (D)
- 10. Local account survival guide (E)
- 11. Basic Windows maintenance (F)
- 12. Recovery procedures & step-by-step runbooks
- 13. Appendices: corrected Copilot instruction block, logs, EFI diagrams, checklist, warnings

1. Key concepts & failure overview
----------------------------------
- Windows Setup runs multiple phases (DOWNLEVEL → SAFE_OS → APPLY_IMAGE/driver migration → FIRST_BOOT → SECOND_BOOT) requiring the servicing stack and inter-process communication via RPC.
- RPC (Remote Procedure Call) is core to Setup's orchestration: servicing, DISM, TrustedInstaller, driver migration, and parts of Windows Update use local RPC channels.
- The Windows Firewall service (MpsSvc) is a dependency in the RPC subsystem on modern Windows builds for endpoint registration/initialization; if MpsSvc is disabled, RPC endpoint registration can fail and manifest as endpoint mapper errors (e.g., 0x800706D9).
- Dual‑boot systems and EFI layout issues create additional risk: Windows will write to the EFI System Partition (ESP) and update NVRAM boot entries during upgrades.

2. Why Windows Setup requires RpcEptMapper, RpcSs, MpsSvc, dynamic RPC ports, servicing RPC
-------------------------------------------------------------------------------------------
- RpcEptMapper (RPC Endpoint Mapper)
  - Role: Provides the "where is the service?" function for RPC — clients query it to learn which TCP port an RPC server is listening on (TCP 135 is the well-known endpoint mapper port).
  - Setup usage: Many servicing components register ephemeral RPC interfaces; Setup uses the endpoint mapper to locate those ephemeral ports.
  - Failure effect: If RpcEptMapper cannot register or provide endpoints, clients cannot discover RPC endpoints → endpoint mapper failures and RPC errors.

- RpcSs (Remote Procedure Call service)
  - Role: Core RPC runtime: coordinates transport, threads, authentication, and endpoint management.
  - Setup usage: Any RPC client/server interaction (servicing stack, TrustedInstaller, driver migration) depends on RpcSs.
  - Failure effect: RPC calls fail early; Setup cannot perform component store operations.

- MpsSvc (Windows Firewall service)
  - Role (clarified): On modern Windows, the Firewall service participates in supporting the RPC subsystem's endpoint registration and local transport initialization. The Firewall service is not required because Setup "checks firewall policy" — rather, it is a runtime dependency the RPC stack uses in endpoint registration/initialization.
  - Setup usage: The servicing stack and related components rely on RPC channels that depend on RPC initialization which, on many modern builds, has a runtime dependency tied to the Firewall service.
  - Failure effect: If MpsSvc is disabled or cannot initialize correctly, RPC subsystem initialization or endpoint registration can fail → RpcEptMapper reports no endpoints available → RPC clients cannot bind/connect and Setup servicing operations fail.

- RPC dynamic ports (ephemeral ports)
  - Role: Many RPC servers use dynamic ports assigned at runtime; clients obtain these via RpcEptMapper.
  - Setup usage: Component server endpoints (servicing stack, DISM-related services, driver migration endpoints) commonly use ephemeral ports.
  - Failure effect: If ephemeral port ranges are blocked at the kernel/network-stack level or if endpoint registration fails, RPC clients will hang or time out and Setup may stall (commonly observed during APPLY_IMAGE/driver migration).

- Servicing stack RPC communication
  - Role: The servicing stack (TrustedInstaller, CBS, DISM services) exposes RPC endpoints for package application, servicing, and driver staging.
  - Setup usage: Image application and driver migration are coordinated by the servicing stack via RPC.
  - Failure effect: If RPC endpoints are unreachable or unregistered, Setup cannot apply image changes or migrate drivers → stalls or rollback.

3. Error classes & root causes (corrected)
-------------------------------------------
- 0x800706D9 — "There are no more endpoints available from the endpoint mapper."
  - Correct meaning: This is an RPC Endpoint Mapper failure: the endpoint mapper could not return an available endpoint for the requested RPC service.
  - Typical chain in observed upgrade failures:
    - MpsSvc disabled or fails to initialize → RPC subsystem cannot register/initialize endpoints → RpcEptMapper reports no available endpoints → RPC clients cannot bind/connect → Setup reports 0x800706D9 during servicing calls.
  - Key point: 0x800706D9 signals an RPC endpoint/registration problem; the Firewall service’s role is as an RPC dependency in this failure mode, not because Setup is performing firewall policy checks.

- RPC endpoint mapper failures (e.g., RPC_S_SERVER_UNAVAILABLE, RPC_S_UNKNOWN_IF)
  - Meaning: Clients cannot locate or contact RPC endpoints.
  - Root causes:
    - RpcEptMapper or RpcSs stopped or misconfigured
    - MpsSvc disabled causing RPC endpoint registration failure
    - Corrupted RPC registry entries or service binaries
    - Kernel-level restrictions to local transports (rare, advanced configurations)

- Servicing stack corruption (DISM errors, TrustedInstaller failures)
  - Meaning: Component store is inconsistent or servicing stack binaries are corrupted.
  - Manifestations:
    - DISM /Cleanup-Image failures
    - Setup stalls during APPLY_IMAGE or reports package errors
    - Windows Update or DISM reports servicing errors in logs

4. Quick repair (PowerShell) — do NOT use sc config for protected services
--------------------------------------------------------------------------
Important: On modern Windows 11 builds (24H2–25H2+), RpcEptMapper, RpcSs, and MpsSvc are protected services. Avoid sc config because it may not correctly update SCM metadata for these protected services. Use PowerShell Set-Service and Start-Service which correctly update the service configuration on modern Windows.

Run the following elevated (Administrator) PowerShell commands:

```powershell
# Repair RPC and Windows Firewall service using PowerShell (REQUIRED on modern builds)
Set-Service -Name RpcEptMapper -StartupType Automatic
Start-Service -Name RpcEptMapper

Set-Service -Name RpcSs -StartupType Automatic
Start-Service -Name RpcSs

Set-Service -Name MpsSvc -StartupType Automatic
Start-Service -Name MpsSvc
```

Notes:
- These cmdlets correctly update service configuration and start the services via the Windows Service Controller in the way modern Windows expects.
- Re-enabling MpsSvc is typically required when endpoint mapper errors are present, because a disabled Firewall service can prevent RPC endpoint registration → 0x800706D9. The proximate failure is RPC initialization; MpsSvc is a dependency in that initialization path.
- Do not assert that Setup enforces firewall policy or that Defender binaries are checked by Setup. Defender is not a servicing dependency for Setup in this failure class.

5. Windows Setup phases and "46%" stall analysis
------------------------------------------------
Windows Setup high-level phases:
- DOWNLEVEL — Pre-setup work, image checks, initial preparation.
- SAFE_OS — Limited, WinRE-like environment where the image is applied and system components prepared (APPLY_IMAGE, driver staging).
- FIRST_BOOT — Boot into the new image; drivers and services initialize.
- SECOND_BOOT — Finalization, OOBE, and user configuration.

46% stall mapping:
- "46%" commonly maps to APPLY_IMAGE and driver migration.
- During APPLY_IMAGE, the servicing stack applies packages to the component store and migrates drivers. TrustedInstaller and other servicing components provide RPC endpoints for these operations.
- If RPC dynamic ports are blocked or endpoint registration fails (e.g., due to MpsSvc disabled), APPLY_IMAGE blocks waiting for RPC calls and timeouts, producing an apparent hang at ~46%.

How RPC dynamic ports and servicing stack failures cause stalls:
- Clients query RpcEptMapper (TCP 135) to find ephemeral ports. If endpoint mapper cannot respond or the service cannot register endpoints, clients stall.
- Firewall/stack-level blocking of ephemeral ranges or local transport failures cause servicing RPC timeouts.
- Servicing stack retries and long timeouts make the hang appear permanent until services are re-enabled or repaired.

6. Lessons learned (A)
----------------------
- RPC dependency
  - Do not disable RpcSs or RpcEptMapper. These services are essential for the RPC subsystem.
- Firewall dependency
  - MpsSvc is a runtime dependency for RPC endpoint registration on modern Windows. Disabling it can cause endpoint mapper failures and break Setup.
- Servicing stack behavior
  - The servicing stack uses RPC to apply image changes and migrate drivers; it must be intact and able to register endpoints.
- EFI partition requirements
  - ESP must be FAT32 with correct partition type GUID, enough free space, and intact boot entries.
- Known failure codes
  - 0x800706D9 (RPC endpoint mapper), RPC_S_SERVER_UNAVAILABLE, DISM/CBS errors (e.g., 0x800f081f, 0x80070002), other servicing errors.
- Dual‑boot considerations
  - Windows modifies ESP and NVRAM. Back up ESP and boot entries prior to upgrades.

7. Hardening interference (B)
------------------------------
Hardening policies and disabled services that frequently break upgrades:
- Disabling RpcSs, RpcEptMapper, MpsSvc
- Preventing TrustedInstaller from spawning/updating due to WDAC/AppLocker rules
- Locking down ephemeral port ranges via kernel/firewall policy
- Removing or corrupting service registry entries or binaries (dangerous; restore from known good sources)

Table: Hardening → Effect → Severity → Fix

| Hardening / Policy                                                         | Effect (what breaks)                                                                 | Severity | Fix / Mitigation |
|----------------------------------------------------------------------------|--------------------------------------------------------------------------------------:|---------:|------------------|
| Disable RpcSs / RpcEptMapper                                               | RPC calls fail; Setup cannot discover endpoints                                      | High     | Restore and start using PowerShell Set-Service/Start-Service; repair registry if needed |
| Disable MpsSvc (Windows Firewall)                                          | RPC endpoint registration may fail → endpoint mapper errors (0x800706D9) → servicing/RPC operations break | High     | Re-enable MpsSvc via PowerShell; start RpcSs/RpcEptMapper; verify RPC endpoint registration and event logs |
| Block ephemeral ports (e.g., 49152–65535)                                  | Servicing RPC timeouts; driver migration stalls                                      | High     | Temporarily allow ephemeral ports or add local exceptions for servicing processes during upgrade |
| WDAC/AppLocker restricts installers or TrustedInstaller                    | TrustedInstaller cannot spawn or patch components                                   | High     | Add temporary policy exceptions for servicing and Setup processes during upgrade window |
| Registry hardening (remove/modify service entries)                         | Service fails to start or cannot register endpoints                                  | High     | Restore registry entries from backup; repair OS with DISM/restore image |
| Removing Windows Defender binaries or claims that Defender affects Setup   | Incorrect root cause attribution—Defender is not required for Setup; removal is unsafe and may cause unrelated system instability | Medium/Low | Do not remove system binaries; restore from known-good image if missing |

Hardening checklist (quick)
- Audit RpcSs, RpcEptMapper, MpsSvc, TrustedInstaller services and their SCM metadata.
- Verify ephemeral port allowance for local RPC communications.
- Ensure WDAC/AppLocker rules permit TrustedInstaller and Setup processes during upgrades.
- Document and temporarily relax relevant controls in a pre-upgrade maintenance window.

8. PowerShell diagnostics & scripts (C)
---------------------------------------
Run elevated (Administrator). Scripts below are safe diagnostics unless noted.

8.1 RPC service health
```powershell
# rpc-health.ps1
$services = "RpcSs","RpcEptMapper"
Get-Service -Name $services | Select-Object Name,Status,StartType | Format-Table -AutoSize

# Check endpoint mapper connectivity (port 135)
Test-NetConnection -ComputerName 127.0.0.1 -Port 135 -InformationLevel Detailed

# Check for RPC-related registry entries (informational)
Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Services\RpcEptMapper","HKLM:\SYSTEM\CurrentControlSet\Services\RpcSs" -ErrorAction SilentlyContinue
```

8.2 Firewall service health
```powershell
# firewall-health.ps1
Get-Service -Name MpsSvc | Format-List *
Get-NetFirewallProfile | Format-Table Name,Enabled,DefaultInboundAction,DefaultOutboundAction
```

8.3 Windows Update logs & servicing logs
```powershell
# update-logs.ps1
$paths = @(
  "$env:windir\Panther\setupact.log",
  "$env:windir\Panther\setuperr.log",
  "$env:windir\Logs\CBS\CBS.log",
  "$env:windir\WindowsUpdate.log"
)
foreach ($p in $paths) {
  if (Test-Path $p) { Write-Output "`n=== $p ===`n"; Get-Content -Path $p -Tail 200 -ErrorAction SilentlyContinue }
  else { Write-Output "Missing: $p" }
}
```

8.4 Servicing stack health (DISM/CBS)
```powershell
# servicing-health.ps1
Write-Output "Checking component store health..."
DISM /Online /Cleanup-Image /CheckHealth
DISM /Online /Cleanup-Image /ScanHealth
DISM /Online /Cleanup-Image /RestoreHealth
Write-Output "Running SFC..."
sfc /scannow
```

8.5 EFI layout
```powershell
# efi-layout.ps1
Get-Disk | Where-Object PartitionStyle -EQ 'GPT' | ForEach-Object {
    $disk = $_
    Write-Output "`nDisk $($disk.Number): $($disk.FriendlyName)`n"
    Get-Partition -DiskNumber $disk.Number | Format-Table -AutoSize
    Get-Volume -DiskNumber $disk.Number | Where-Object FileSystem -EQ 'FAT32' | Format-Table DriveLetter,FileSystemLabel,Size,SizeRemaining
}
bcdedit /enum firmware
```

8.6 WinRE status
```powershell
# winre-status.ps1
reagentc /info
# To enable if needed:
# reagentc /enable
# To set WinRE image location:
# reagentc /setreimage /path C:\Recovery\WindowsRE
```

8.7 Aggregate diagnostic summary
```powershell
# summary-dx.ps1 (run the component scripts in order)
.\rpc-health.ps1
.\firewall-health.ps1
.\update-logs.ps1
.\servicing-health.ps1
.\efi-layout.ps1
.\winre-status.ps1
```

9. GRUB + Windows dual‑boot safety (D)
--------------------------------------
9.1 What Windows touches
- \EFI\Microsoft\Boot files on the ESP
- NVRAM boot entries (Windows Boot Manager may be set as default)
- BCD store and WinRE entries

9.2 What Windows generally does not alter
- It does not intentionally alter GRUB binaries if they are kept on a separate ESP on another disk or protected location; however, Windows often rewrites the ESP and NVRAM entries causing GRUB to be non-default.

9.3 EFI backup procedure (recommended before upgrade)
1. Boot to WinPE or Linux Live.
2. Identify and mount the ESP (FAT32).
3. Backup the EFI folder byte-exact:

PowerShell (Admin):
```powershell
$esp = Get-Partition -GptType "{C12A7328-F81F-11D2-BA4B-00A0C93EC93B}" -ErrorAction SilentlyContinue
if ($esp) {
  $esp | Set-Partition -NewDriveLetter Z -ErrorAction SilentlyContinue
  robocopy "Z:\EFI" "C:\Backup\EFI-Backup\EFI" /MIR /FFT /Z /XA:SH
}
```

Linux (recommended for byte-exact tar):
```bash
sudo mkdir /mnt/esp
sudo mount /dev/sdX1 /mnt/esp
sudo tar -cvpzf /mnt/usb/esp-backup-$(date +%F).tar.gz -C /mnt/esp .
```

4. Export firmware boot entries:
```powershell
bcdedit /enum firmware > C:\Backup\bcd-firmware.txt
# or on Linux:
sudo efibootmgr -v > /mnt/usb/efibootmgr-$(date +%F).txt
```

9.4 Restoring EFI & GRUB after Windows upgrade
- Restore the \EFI\GRUB folder from backup to the ESP.
- Recreate NVRAM entries with efibootmgr or bcdedit:
  - efibootmgr example:
    - sudo efibootmgr --create --disk /dev/sdX --part 1 --label "GRUB" --loader '\EFI\GRUB\grubx64.efi'
- If GRUB cannot find Windows, update grub.cfg or run update-grub.

9.5 WinRE safe usage with GRUB present
- Use a dedicated WinRE USB for critical repairs when GRUB is present to avoid Windows rewriting ESP.
- Expect Windows Boot Manager to be set as default after upgrades and plan to restore GRUB with efibootmgr or firmware settings.

Diagram — Boot flow and interactions (ASCII)
---------------------------------------------
EFI System Partition (ESP):
/---------------------------------------------\
| \EFI\Microsoft\Boot\bootmgfw.efi            | <- Windows Boot Manager
| \EFI\GRUB\grubx64.efi                       | <- GRUB (Linux)
\---------------------------------------------/
NVRAM BootOrder -> [0001: Windows Boot Manager] [0002: GRUB]

Flow:
- On upgrade, Windows writes \EFI\Microsoft\Boot and may set Windows Boot Manager first in BootOrder.
- Restore: efibootmgr/bcdedit to adjust BootOrder or reinsert GRUB entry.

10. Local Account Survival Guide (E)
------------------------------------
Registry keys to enforce local-only accounts (apply with care):

```reg
[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System]
"DisableMicrosoftAccount"=dword:00000003
"BlockUserFromMicrosoftAccount"=dword:00000001
"NoConnectedUser"=dword:00000001
```

OOBE bypass (allow local account creation during OOBE):
```reg
[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE]
"BypassNRO"=dword:00000001
```

Notes & cautions:
- Apply via tested GPO or provisioning mechanisms.
- Changes affect user experience (Microsoft Store sign-ins, Connected User features).

11. Basic Windows maintenance (F)
---------------------------------
11.1 DISM and SFC
```cmd
DISM /Online /Cleanup-Image /CheckHealth
DISM /Online /Cleanup-Image /ScanHealth
DISM /Online /Cleanup-Image /RestoreHealth
sfc /scannow
```
- If DISM needs a source and the internet is restricted:
```cmd
DISM /Online /Cleanup-Image /RestoreHealth /Source:WIM:X:\sources\install.wim:1 /LimitAccess
```

11.2 Component cleanup
```cmd
DISM /Online /Cleanup-Image /StartComponentCleanup /ResetBase
net stop wuauserv
rd /s /q %windir%\SoftwareDistribution\Download
net start wuauserv
```

11.3 Driver maintenance
- Export drivers:
```powershell
pnputil /export-driver * C:\DriverBackup
```
- Remove or update problematic third‑party drivers before upgrade.

11.4 Update troubleshooting
- Ensure services: bits, wuauserv, cryptSvc, trustedinstaller are running.
- Example reset:
```powershell
Stop-Service wuauserv -Force
Stop-Service bits -Force
Rename-Item -Path $env:windir\SoftwareDistribution -NewName SoftwareDistribution.old -ErrorAction SilentlyContinue
Rename-Item -Path $env:windir\System32\catroot2 -NewName catroot2.old -ErrorAction SilentlyContinue
Start-Service wuauserv; Start-Service bits
```

12. Recovery procedures & step-by-step runbooks
-----------------------------------------------

12.1 Runbook: Repair RPC/Firewall & retry upgrade
1. Boot Windows (if possible) or WinRE.
2. Open elevated PowerShell.
3. Repair services using PowerShell (do NOT use sc config):
```powershell
Set-Service -Name RpcEptMapper -StartupType Automatic
Start-Service -Name RpcEptMapper

Set-Service -Name RpcSs -StartupType Automatic
Start-Service -Name RpcSs

Set-Service -Name MpsSvc -StartupType Automatic
Start-Service -Name MpsSvc
```
4. Confirm port 135:
```powershell
Test-NetConnection -ComputerName 127.0.0.1 -Port 135
netstat -ano | findstr :135
```
5. Run servicing health checks:
```cmd
DISM /Online /Cleanup-Image /RestoreHealth
sfc /scannow
```
6. Inspect Panther logs:
```powershell
Get-Content $env:windir\Panther\setupact.log -Tail 200
Get-Content $env:windir\Panther\setuperr.log -Tail 200
```
7. If endpoint or firewall-timeout errors persist, temporarily allow TCP 135 and needed ephemeral range or repair kernel-level configurations.
8. Retry the upgrade and monitor Panther logs.

12.2 Runbook: Recover from 46% APPLY_IMAGE hang
1. Wait 2–4 hours if feasible (time-consuming retries may complete).
2. If persistent, reboot to WinRE (3 forced restarts to trigger WinRE).
3. In WinRE command prompt, run offline servicing checks (if C: is Windows):
```cmd
DISM /Image:C:\ /Cleanup-Image /CheckHealth
DISM /Image:C:\ /Cleanup-Image /RestoreHealth
```
4. Repair services as in 12.1 (if WinRE supports it on the offline image, prefer repairing in the running OS).
5. If corrupt servicing stack, repair from ISO:
```cmd
DISM /Online /Cleanup-Image /RestoreHealth /Source:WIM:X:\sources\install.wim:1 /LimitAccess
```
6. Capture logs and escalate if repeated failure occurs.

12.3 Runbook: Prepare dual-boot host for upgrade
1. Backup ESP (see 9.3).
2. Export boot entries.
3. Temporarily set Windows Boot Manager as default (reduce complexity).
4. Create temporary policy exceptions for servicing processes.
5. Perform upgrade.
6. Restore GRUB/NVRAM as needed.

12.4 Creating a WinRE USB (safe offline WinRE)
- Use the Windows PE / ADK to create a bootable WinRE/WinPE USB. Booting from external media reduces risk of Windows rewriting ESP.

13. Appendices
--------------
13.1 Corrected Copilot instruction block (paste into Copilot prompts)
> Important correction for Copilot:  
>  
> Windows Setup failures such as **0x800706D9** are caused by **RPC endpoint mapper failures**, not by “firewall policy” or “missing firewall binaries”.  
>  
> Windows 11 Setup requires the following services to be **enabled and running**:  
> - **RpcEptMapper**  
> - **RpcSs**  
> - **MpsSvc (Windows Firewall)**  
>  
> This is because the Windows servicing stack uses **local RPC channels**, and RPC depends on the Firewall service for endpoint registration.  
>  
> Therefore:  
> - Do **not** claim that Setup checks firewall policy.  
> - Do **not** claim that Defender binaries affect Setup.  
> - Do **not** claim that removing firewall rules breaks Setup.  
>  
> Additionally, when documenting repair actions for RPC-related failures (e.g., 0x800706D9), never use sc config.  
> Modern Windows requires PowerShell service configuration because RPC and MpsSvc are protected services and sc config does not correctly update their SCM metadata.  
>  
> Always use:
> ```powershell
> Set-Service -Name RpcEptMapper -StartupType Automatic
> Start-Service -Name RpcEptMapper
> 
> Set-Service -Name RpcSs -StartupType Automatic
> Start-Service -Name RpcSs
> 
> Set-Service -Name MpsSvc -StartupType Automatic
> Start-Service -Name MpsSvc
> ```
> The correct explanation is:  
> **“Windows Setup fails because RPC cannot initialize when MpsSvc is disabled.”**

13.2 Key logs and locations
- %windir%\Panther\setupact.log
- %windir%\Panther\setuperr.log
- %windir%\Logs\CBS\CBS.log
- %windir%\WindowsUpdate.log
- Event Viewer → System, Application

13.3 Important commands quick reference
- Repair protected services (PowerShell, Admin):
```powershell
Set-Service -Name RpcEptMapper -StartupType Automatic
Start-Service -Name RpcEptMapper
Set-Service -Name RpcSs -StartupType Automatic
Start-Service -Name RpcSs
Set-Service -Name MpsSvc -StartupType Automatic
Start-Service -Name MpsSvc
```
- DISM / SFC:
```cmd
DISM /Online /Cleanup-Image /ScanHealth
DISM /Online /Cleanup-Image /RestoreHealth
sfc /scannow
```
- WinRE:
```cmd
reagentc /info
reagentc /disable
reagentc /enable
```
- Backup ESP (PowerShell):
```powershell
$esp = Get-Partition -GptType "{C12A7328-F81F-11D2-BA4B-00A0C93EC93B}"
$esp | Set-Partition -NewDriveLetter Z
robocopy "Z:\EFI" "C:\Backup\EFI-Backup\EFI" /MIR
```

13.4 Warnings and Cautions
- WARNING: Re-enabling MpsSvc or temporarily opening ephemeral ports on production systems may change attack surface during the maintenance window. Document and revert exceptions after upgrade.
- WARNING: Manipulating NVRAM/EFI entries without backups can render systems unbootable. Always back up the ESP and BootOrder before changes.
- WARNING: Editing the registry affects all users. Export keys before changing and apply via GPO where possible.
- WARNING: Do not remove system binaries. Removing Windows Defender binaries is unsafe and unrelated to RPC endpoint mapper failures.

13.5 Troubleshooting checklist (quick)
- Are RpcSs and RpcEptMapper running?
- Is MpsSvc running and able to start correctly?
- Is TCP 135 reachable locally?
- Are ephemeral RPC ports allowed for local communications?
- Is the component store healthy? (DISM / SFC)
- Do Panther setup logs show RPC timeouts or endpoint mapper errors?
- Is ESP intact and of sufficient size?
- Were hardening policies applied? If yes, temporarily relax them for the upgrade window.

14. Example investigative timeline (real‑world pattern)
-------------------------------------------------------
1. Symptom: Upgrade aborts early with 0x800706D9.
   - Check services: MpsSvc is stopped/disabled → re-enable via PowerShell → RPC endpoint registration restored → setup proceeds.
2. Symptom: Upgrade stalls at 46%.
   - Panther logs show APPLY_IMAGE waiting on TrustedInstaller RPC; netstat shows missing endpoints → ephemeral ports or endpoint registration problem → repair MpsSvc/RpcEptMapper → upgrade resumes.
3. Symptom: Post‑upgrade, GRUB not default.
   - Restore backup of ESP and NVRAM entries; recreate GRUB entry if needed.

15. Final recommendations
-------------------------
- Do not permanently disable RpcSs, RpcEptMapper, or MpsSvc. For hardened environments, document approved exceptions and plan a pre-upgrade maintenance window to temporarily relax relevant controls.
- Use PowerShell Set-Service/Start-Service to repair protected services on modern Windows builds — do not use sc config for these services.
- Back up the EFI System Partition and NVRAM entries before performing upgrades.
- Keep a WinRE/WinPE USB for isolated recovery and to avoid accidental ESP writes.
- Centralize diagnostic scripts in your runbook and include the corrected Copilot instruction block when automating documentation generation.

End of manual.
