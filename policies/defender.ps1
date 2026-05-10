# =============================================================
# defender.ps1 - Microsoft Defender hardening
# =============================================================
# Sourced by bootstrap.ps1 after the apps install.
# Each setting is wrapped in try/catch so one failure doesn't
# abort the rest (some prefs are unavailable on certain SKUs).
# =============================================================

function Try-Set($block, $label) {
    try { & $block; Write-Host "    ok   $label" }
    catch { Write-Warning "    fail $label - $_" }
}

Write-Host '  Defender preferences'

Try-Set { Set-MpPreference -DisableRealtimeMonitoring  $false } 'realtime monitoring on'
Try-Set { Set-MpPreference -DisableBehaviorMonitoring  $false } 'behavior monitoring on'
Try-Set { Set-MpPreference -DisableIOAVProtection      $false } 'IOAV scan on'
Try-Set { Set-MpPreference -DisableScriptScanning      $false } 'script scanning on'
Try-Set { Set-MpPreference -DisableArchiveScanning     $false } 'archive scanning on'
Try-Set { Set-MpPreference -DisableEmailScanning       $false } 'email scanning on'

Try-Set { Set-MpPreference -MAPSReporting Advanced }              'cloud reporting (Advanced)'
Try-Set { Set-MpPreference -SubmitSamplesConsent SendSafeSamples } 'sample submission (safe)'
Try-Set { Set-MpPreference -PUAProtection Enabled }                'PUA protection on'
Try-Set { Set-MpPreference -CloudBlockLevel High }                 'cloud block level high'
Try-Set { Set-MpPreference -CloudExtendedTimeout 50 }              'cloud extended timeout 50s'

# Controlled Folder Access in audit mode first - flip to Enabled once you've
# confirmed it doesn't block apps you actually use.
Try-Set { Set-MpPreference -EnableControlledFolderAccess AuditMode } 'controlled folder access (audit)'

# Network protection in audit mode for the same reason.
Try-Set { Set-MpPreference -EnableNetworkProtection AuditMode } 'network protection (audit)'

# Weekly full scan, Sunday at 02:00 (120 = minutes after midnight)
Try-Set { Set-MpPreference -ScanScheduleDay Sunday } 'scan day Sunday'
Try-Set { Set-MpPreference -ScanScheduleTime 120 }   'scan time 02:00'

Write-Host '  Updating signatures'
Try-Set { Update-MpSignature } 'signature update'
