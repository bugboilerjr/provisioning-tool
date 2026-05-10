# =============================================================
# firewall.ps1 - Windows Firewall hardening
# =============================================================

Write-Host '  Enabling firewall on all profiles'
Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True

Write-Host '  Default actions: block inbound, allow outbound (Public + Private)'
Set-NetFirewallProfile -Profile Public,Private `
    -DefaultInboundAction  Block `
    -DefaultOutboundAction Allow `
    -AllowInboundRules     True `
    -NotifyOnListen        False `
    -AllowUnicastResponseToMulticast False

Write-Host '  Domain profile: keep inbound rules but allow domain traffic'
Set-NetFirewallProfile -Profile Domain `
    -DefaultInboundAction  Block `
    -DefaultOutboundAction Allow

Write-Host '  Logging dropped packets'
$logPath = "$env:SystemRoot\System32\LogFiles\Firewall\pfirewall.log"
Set-NetFirewallProfile -Profile Domain,Public,Private `
    -LogFileName        $logPath `
    -LogMaxSizeKilobytes 16384 `
    -LogBlocked         True `
    -LogAllowed         False

Write-Host '  Disabling File and Printer Sharing on Public profile'
Get-NetFirewallRule -DisplayGroup 'File and Printer Sharing' -ErrorAction SilentlyContinue |
    Where-Object { $_.Profile -match 'Public' } |
    Disable-NetFirewallRule -ErrorAction SilentlyContinue

Write-Host '  Done.'
