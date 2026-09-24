# Preventing Windows 11 from Redirecting to MSN During Captive Portal Login

Audience: Windows system administrators, power users, and network engineers.

This manual describes how Windows 11's Network Connectivity Status Indicator (NCSI) interacts with captive portals and how to reduce or disable the probes that can result in an automatic browser launch. The procedures change system-wide connectivity detection. Test them on representative systems before deploying them broadly.

> **Important warning:** NCSI is not the data-plane connection. Disabling its probes does not disconnect the computer, but it can cause Windows to report **No Internet**, suppress connectivity-dependent state changes, or stop automatically discovering captive portals. Applications may still have full network access. Keep an out-of-band administration path available.

## 1. NCSI internals

NCSI is implemented as part of Windows network location and connectivity detection, primarily through the Network Location Awareness (NlaSvc) service and related system components. It evaluates a network interface after link, DHCP, routing, DNS, or network-profile changes.

NCSI uses two complementary mechanisms:

- **Active probing:** Windows sends a known HTTP request to a Microsoft connectivity-test endpoint and compares the response with the expected result. A successful, unmodified response indicates Internet connectivity. A redirect, altered body, timeout, DNS failure, or unexpected status can indicate a captive portal, restricted network, or failure.
- **Passive probing:** Windows observes normal network activity and DNS/network results over time. Passive detection can update the connectivity state without deliberately requesting the active test resource.

The result is represented in the connectivity state exposed to Windows and applications. Typical states include local connectivity only, an authenticated Internet connection, or a network requiring sign-in. The exact timing and browser behavior vary by Windows build, policy, endpoint security software, network profile, and captive-portal implementation.

### NCSI decision flow

```text
Interface/link change, DHCP renewal, or network-profile event
                         |
                         v
                 NlaSvc evaluates interface
                         |
             +-----------+-----------+
             |                       |
             v                       v
       Passive observations     Active probe enabled?
             |                       |
             |                 +-----+------+
             |                 |            |
             |                No           Yes
             |                 |            |
             +--------+--------+            v
                      |             DNS + HTTP test
                      v                    |
              Combine evidence            v
                      |       +-----------+-----------+
                      |       |                       |
                      |       v                       v
                      |  Expected response       Redirect/altered/
                      |  and reachability       timeout/DNS failure
                      |       |                       |
                      +-------+-----------+-----------+
                                  |
                                  v
                    Update connectivity state
                                  |
             Captive-portal indication may invoke the
             Windows network sign-in experience/browser
```

## 2. Why MSN or Edge can appear

A captive portal commonly permits DNS and an initial HTTP request but intercepts unauthenticated traffic. When NCSI requests its test host, the gateway may:

1. resolve the test hostname to a gateway-controlled address;
2. return an HTTP redirect to a login page; or
3. replace the expected test response with portal HTML.

Windows interprets that mismatch as evidence that authentication is required. A system component can then invoke the network sign-in experience, which may display Edge and the portal's redirect target. If the gateway redirects broadly, that target can appear to be MSN or another Microsoft web destination even though NCSI did not intentionally request an MSN page.

The redirect is therefore usually a side effect of captive-portal interception, not proof that the user manually opened MSN. Browser policy, Web Account Manager, security software, and the portal's redirect rules can also affect the final page.

## 3. Disable NCSI active probing

Run these commands from an elevated PowerShell session. `EnableActiveProbing=0` is the primary setting.

### PowerShell

```powershell
$ncsi = 'HKLM:\SYSTEM\CurrentControlSet\Services\NlaSvc\Parameters\Internet'
New-Item -Path $ncsi -Force | Out-Null
New-ItemProperty -Path $ncsi -Name EnableActiveProbing -PropertyType DWord -Value 0 -Force | Out-Null
```

### REG ADD equivalent

```text
reg add "HKLM\SYSTEM\CurrentControlSet\Services\NlaSvc\Parameters\Internet" /v EnableActiveProbing /t REG_DWORD /d 0 /f
```

This prevents the normal active HTTP validation request. It does not block arbitrary application traffic and does not prevent a user from opening a browser manually.

## 4. Optional probe-host and path neutralization

Some administrators also remove or empty the active probe host and path. This is defense in depth, not a substitute for disabling active probing, and behavior can vary by Windows release. Do not use this option if your organization depends on the standard NCSI endpoint for diagnostics.

### PowerShell

```powershell
$ncsi = 'HKLM:\SYSTEM\CurrentControlSet\Services\NlaSvc\Parameters\Internet'
New-ItemProperty -Path $ncsi -Name ActiveWebProbeHost -PropertyType String -Value '' -Force | Out-Null
New-ItemProperty -Path $ncsi -Name ActiveWebProbePath -PropertyType String -Value '' -Force | Out-Null
```

### REG ADD equivalent

```text
reg add "HKLM\SYSTEM\CurrentControlSet\Services\NlaSvc\Parameters\Internet" /v ActiveWebProbeHost /t REG_SZ /d "" /f
reg add "HKLM\SYSTEM\CurrentControlSet\Services\NlaSvc\Parameters\Internet" /v ActiveWebProbePath /t REG_SZ /d "" /f
```

## 5. Optional passive-probe reduction

Set `PassivePollPeriod` to zero only when passive NCSI polling is itself undesirable. This can make the connectivity state remain stale or show **No Internet** until another network event occurs.

### PowerShell

```powershell
$ncsi = 'HKLM:\SYSTEM\CurrentControlSet\Services\NlaSvc\Parameters\Internet'
New-ItemProperty -Path $ncsi -Name PassivePollPeriod -PropertyType DWord -Value 0 -Force | Out-Null
```

### REG ADD equivalent

```text
reg add "HKLM\SYSTEM\CurrentControlSet\Services\NlaSvc\Parameters\Internet" /v PassivePollPeriod /t REG_DWORD /d 0 /f
```

Use this setting only after testing VPN, Wi-Fi roaming, DirectAccess, firewall, proxy, and application behavior.

## 6. Disable automatic network sign-in launch where supported

The following machine policy values are useful where the installed Windows build and policy processing support them. They are not a guarantee that every Edge launch path is disabled; browser startup, OEM utilities, and third-party agents can be independent of NCSI.

### PowerShell

```powershell
$policy = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\NetworkConnectivityStatusIndicator'
New-Item -Path $policy -Force | Out-Null
New-ItemProperty -Path $policy -Name DisableAutoLaunch -PropertyType DWord -Value 1 -Force | Out-Null
New-ItemProperty -Path $policy -Name NoWebProbe -PropertyType DWord -Value 1 -Force | Out-Null
```

### REG ADD equivalent

```text
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\NetworkConnectivityStatusIndicator" /v DisableAutoLaunch /t REG_DWORD /d 1 /f
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\NetworkConnectivityStatusIndicator" /v NoWebProbe /t REG_DWORD /d 1 /f
```

After changing policy, restart the computer or restart the affected networking components during a maintenance window. Avoid repeatedly restarting NlaSvc on production systems without understanding the impact on network profiles and dependent services.

## 7. Deployment script

Save the following as `Disable-NCSI.ps1` and run it as Administrator. The script makes the conservative change by default and enables the more disruptive passive and browser-policy settings only when explicitly requested.

```powershell
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$DisablePassivePolling,
    [switch]$DisableAutomaticLaunch,
    [switch]$NeutralizeProbeTarget
)

$ErrorActionPreference = 'Stop'
$ncsi = 'HKLM:\SYSTEM\CurrentControlSet\Services\NlaSvc\Parameters\Internet'
$policy = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\NetworkConnectivityStatusIndicator'

if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this script from an elevated PowerShell session.'
}

New-Item -Path $ncsi -Force | Out-Null

if ($PSCmdlet.ShouldProcess($ncsi, 'Disable active NCSI probing')) {
    New-ItemProperty -Path $ncsi -Name EnableActiveProbing -PropertyType DWord -Value 0 -Force | Out-Null
}

if ($NeutralizeProbeTarget -and $PSCmdlet.ShouldProcess($ncsi, 'Clear active probe host and path')) {
    New-ItemProperty -Path $ncsi -Name ActiveWebProbeHost -PropertyType String -Value '' -Force | Out-Null
    New-ItemProperty -Path $ncsi -Name ActiveWebProbePath -PropertyType String -Value '' -Force | Out-Null
}

if ($DisablePassivePolling -and $PSCmdlet.ShouldProcess($ncsi, 'Disable passive polling')) {
    New-ItemProperty -Path $ncsi -Name PassivePollPeriod -PropertyType DWord -Value 0 -Force | Out-Null
}

if ($DisableAutomaticLaunch -and $PSCmdlet.ShouldProcess($policy, 'Disable NCSI automatic launch and web probe')) {
    New-Item -Path $policy -Force | Out-Null
    New-ItemProperty -Path $policy -Name DisableAutoLaunch -PropertyType DWord -Value 1 -Force | Out-Null
    New-ItemProperty -Path $policy -Name NoWebProbe -PropertyType DWord -Value 1 -Force | Out-Null
}

Write-Host 'NCSI configuration written. Restart Windows during a maintenance window.'
```

Example deployment:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\Disable-NCSI.ps1 -DisableAutomaticLaunch -WhatIf
.\Disable-NCSI.ps1 -DisableAutomaticLaunch
```

Use Intune, Group Policy, Configuration Manager, or another managed deployment system to distribute the script. The registry commands require local administrative rights.

## 8. Verification and diagnostics

Read the effective values:

```powershell
$ncsi = 'HKLM:\SYSTEM\CurrentControlSet\Services\NlaSvc\Parameters\Internet'
$policy = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\NetworkConnectivityStatusIndicator'

Get-ItemProperty -Path $ncsi |
    Select-Object EnableActiveProbing, ActiveWebProbeHost, ActiveWebProbePath, PassivePollPeriod

Get-ItemProperty -Path $policy -ErrorAction SilentlyContinue |
    Select-Object DisableAutoLaunch, NoWebProbe

Get-NetConnectionProfile
Get-NetIPConfiguration
Get-Service NlaSvc
```

Confirm that active probing is disabled:

```powershell
(Get-ItemPropertyValue -Path $ncsi -Name EnableActiveProbing) -eq 0
```

For packet-level confirmation, capture traffic while reconnecting the interface and inspect DNS and HTTP traffic with an approved diagnostic tool. Do not infer probe activity solely from the taskbar icon; the icon reflects state and policy, not a packet capture.

## 9. Reversion

Delete only values managed by this guide so Windows can fall back to its build defaults. A reboot is recommended.

### PowerShell

```powershell
$ncsi = 'HKLM:\SYSTEM\CurrentControlSet\Services\NlaSvc\Parameters\Internet'
$policy = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\NetworkConnectivityStatusIndicator'

'EnableActiveProbing','ActiveWebProbeHost','ActiveWebProbePath','PassivePollPeriod' |
    ForEach-Object { Remove-ItemProperty -Path $ncsi -Name $_ -ErrorAction SilentlyContinue }

'DisableAutoLaunch','NoWebProbe' |
    ForEach-Object { Remove-ItemProperty -Path $policy -Name $_ -ErrorAction SilentlyContinue }
```

### REG DELETE equivalent

```text
reg delete "HKLM\SYSTEM\CurrentControlSet\Services\NlaSvc\Parameters\Internet" /v EnableActiveProbing /f
reg delete "HKLM\SYSTEM\CurrentControlSet\Services\NlaSvc\Parameters\Internet" /v ActiveWebProbeHost /f
reg delete "HKLM\SYSTEM\CurrentControlSet\Services\NlaSvc\Parameters\Internet" /v ActiveWebProbePath /f
reg delete "HKLM\SYSTEM\CurrentControlSet\Services\NlaSvc\Parameters\Internet" /v PassivePollPeriod /f
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\NetworkConnectivityStatusIndicator" /v DisableAutoLaunch /f
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\NetworkConnectivityStatusIndicator" /v NoWebProbe /f
```

## 10. Windows 11 Home versus Pro

- **Windows 11 Home:** Registry changes and elevated PowerShell are available, but local Group Policy Editor is not included by default. Use a managed policy mechanism, provisioning package, MDM, or the registry script if appropriate.
- **Windows 11 Pro and higher editions:** Local Group Policy and domain policy can be used where the applicable administrative templates expose the relevant NCSI settings. Policy precedence can overwrite local registry changes.
- **All editions:** Verify the actual result on the installed build. Feature updates, security baselines, MDM policy, and third-party endpoint controls can change behavior.

## 11. Troubleshooting

### Edge still opens

1. Confirm `EnableActiveProbing` is actually `0` in the 64-bit machine registry view.
2. Check the policy values and run `gpresult /h "$env:TEMP\gp.html"` on Pro or managed systems.
3. Determine whether the launch occurs only after Wi-Fi association, VPN connection, or user sign-in.
4. Inspect Task Scheduler, startup entries, OEM network utilities, endpoint security software, and browser policies.
5. Capture the process tree when Edge starts. If the parent is not a Windows network sign-in component, NCSI is probably not the trigger.

### DNS rewrite behavior

Captive portals often answer the probe hostname with a gateway address or rewrite DNS only for unauthenticated clients. Compare:

```powershell
Resolve-DnsName www.msftconnecttest.com
Resolve-DnsName dns.msftncsi.com
Get-DnsClientServerAddress
```

Do not hard-code public DNS as a workaround without authorization: the portal may require its DNS interception, and encrypted DNS, split DNS, VPN, or enterprise resolvers can change the result.

### Captive portal quirks

Some portals require a specific User-Agent, block HTTPS until authentication, use a nonstandard redirect, or permit only selected destinations. Disabling NCSI can stop automatic discovery, but it cannot authenticate the portal. Open the portal's approved login URL manually, or use the organization's supported network-access workflow.

### Connectivity icon says “No Internet” but traffic works

This is expected when probes are disabled or intercepted. Test the actual path with approved targets, not only the taskbar indicator. Applications that gate features on Windows' connectivity state may behave differently.

## 12. Hardening Profile

Recommended baseline for systems where automatic captive-portal browser launches are unacceptable:

```text
EnableActiveProbing = 0
ActiveWebProbeHost  = unset (use empty only if required by a tested baseline)
ActiveWebProbePath  = unset (use empty only if required by a tested baseline)
PassivePollPeriod   = unchanged unless passive polling is specifically harmful
DisableAutoLaunch   = 1, if supported and validated on the target build
NoWebProbe          = 1, if supported and validated on the target build
```

Apply `EnableActiveProbing=0` first, validate VPN, Wi-Fi, proxy, firewall, and application behavior, and then consider the optional settings. Document the change in the organization's baseline and retain the reversion commands. The primary trade-off is predictable suppression of automatic probe-triggered launches versus less accurate Windows connectivity status and reduced captive-portal discovery.
