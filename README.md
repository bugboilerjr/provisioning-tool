# Windows Provisioning Tool

Plug in a Rubber Ducky (or Flipper Zero Bad USB) → an elevated PowerShell opens → a one-line bootstrap pulls this repo from GitHub → apps install, policies apply, Microsoft 365 deploys.

---

## Supported Operating Systems

| OS | Version | Status |
|----|---------|--------|
| Windows 11 | 23H2 | ✅ Tested |
| Windows 10 | 22H2 | ✅ Tested |
| Windows 10 | Older builds | ⚠️ May work — increase `DELAY` values in the payload |
| Windows Server | 2019 / 2022 | ⚠️ Untested — winget and ODT should work but the Win+X shortcut may not open the right menu |

> **Note:** The DuckyScript payload uses `GUI x` → `a` to open Terminal (Admin) / PowerShell (Admin). This relies on the standard Win+X power-user menu, which is present on Windows 10 (1809+) and all Windows 11 builds.

---

## How It Fits Together

```
ducky/payload.txt          # DuckyScript - typed by the USB device
bootstrap.ps1              # Pulled by the Ducky's one-liner; orchestrates everything
apps.json                  # winget package IDs to install
policies/
  secedit.inf              # Local security policy (passwords, lockout, audit)
  defender.ps1             # Microsoft Defender hardening
  firewall.ps1             # Windows Firewall hardening
office/
  configuration.xml        # Office Deployment Tool config for M365
  setup.exe                # ODT executable - download once and commit (see below)
```

---

## What It Does By Default

The bootstrap runs five phases in order. Each phase can be skipped individually — see [Bootstrap Switches](#bootstrap-switches) below.

### Phase 1 — Elevation & winget check
Verifies the script is running as Administrator and that `winget` (App Installer) is present. If winget is missing, it attempts to download and install it automatically from `https://aka.ms/getwinget`.

### Phase 2 — App installation
Reads `apps.json` and installs each entry silently via `winget install --silent --scope machine`.

The default app list is:

| App | winget ID |
|-----|-----------|
| Google Chrome | `Google.Chrome` |
| Zoom | `Zoom.Zoom` |
| 7-Zip | `7zip.7zip` |
| Notepad++ | `Notepad++.Notepad++` |
| Visual Studio Code | `Microsoft.VisualStudioCode` |
| PowerToys | `Microsoft.PowerToys` |
| VLC | `VideoLAN.VLC` |
| Git | `Git.Git` |

### Phase 3 — Local security policy (secedit)
Applies `policies/secedit.inf` via `secedit /configure`. The default settings are:

**Password policy**
- Minimum length: 12 characters
- Complexity required: yes
- Maximum age: 90 days / Minimum age: 1 day
- History: last 10 passwords remembered
- Plaintext storage: disabled

**Account lockout**
- Lockout after: 5 bad attempts
- Observation window / reset counter: 30 minutes
- Lockout duration: 30 minutes

**Miscellaneous**
- Guest account: disabled
- Built-in Administrator account: enabled

**Registry / UAC / sign-in**
- Ctrl+Alt+Del required at sign-in
- Last signed-in username not displayed on lock screen
- UAC prompts admin for consent on the secure desktop
- LM password hash not stored

**Event auditing** (1 = success, 2 = failure, 3 = both)

| Category | Setting |
|----------|---------|
| System events | Both |
| Logon events | Both |
| Object access | Failure |
| Privilege use | Failure |
| Policy change | Both |
| Account management | Both |
| Process tracking | None |
| DS access | Failure |
| Account logon | Both |

### Phase 4 — Defender & Firewall hardening

`policies/defender.ps1` enables:
- Real-time, behavior, IOAV, script, archive, and email scanning
- Cloud reporting (Advanced) and sample submission (safe samples)
- PUA (potentially unwanted app) protection
- Cloud block level: High with 50-second extended timeout
- Weekly full scan every Sunday at 02:00
- Signature auto-update on run

> ⚠️ **Controlled Folder Access** and **Network Protection** are set to `AuditMode` by default. Flip them to `Enabled` in `policies/defender.ps1` once you've confirmed no legitimate apps are being blocked.

`policies/firewall.ps1` applies:
- Firewall enabled on all profiles (Domain, Private, Public)
- Default inbound action: **Block** on Public and Private profiles
- Default outbound action: **Allow** on all profiles
- Dropped-packet logging to `%SystemRoot%\System32\LogFiles\Firewall\pfirewall.log` (16 MB cap)
- File and Printer Sharing rules disabled on the Public profile

### Phase 5 — Microsoft 365 (Office Deployment Tool)
Downloads `office/setup.exe` and `office/configuration.xml` from the repo and runs `setup.exe /configure configuration.xml`.

The default `configuration.xml` installs **Microsoft 365 Apps for Business**, 64-bit, Current channel, English (US), and **excludes**: Access, Lync (Skype for Business), Publisher, Bing, OneDrive, and Groove (OneDrive for Business legacy).

> Auto-activation is off (`AUTOACTIVATE=0`) — the user signs in on first launch. Set to `1` for device-based licensing.

All phases write a full transcript to `C:\ProgramData\Provisioning\logs\provision-<timestamp>.log`.

---

## Where to Edit Things

### Adding or removing apps — `apps.json`

Open `apps.json` and edit the `"winget"` array. Each entry needs an `"id"` and a `"name"` (used in logs):

```json
{ "id": "Slack.Slack", "name": "Slack" }
```

To find a winget ID, run `winget search <app name>` in PowerShell, or browse **https://winget.run**.

### Changing which Office apps install — `office/configuration.xml`

Edit or remove `<ExcludeApp>` lines. Valid app IDs: `Access`, `Excel`, `Groove`, `Lync`, `OneDrive`, `OneNote`, `Outlook`, `PowerPoint`, `Publisher`, `Teams`, `Word`.

The easiest way to build a fresh config is the **Office Customization Tool** at **https://config.office.com**.

### Changing password and lockout policy — `policies/secedit.inf`

Edit values under `[System Access]`, `[Event Audit]`, and `[Registry Values]`. Changes take effect via `secedit` on next run. Full key reference: https://learn.microsoft.com/en-us/windows/security/threat-protection/security-policy-settings/security-policy-settings

### Changing Defender settings — `policies/defender.ps1`

Each `Set-MpPreference` call is wrapped in a `try/catch`, so commenting one out or changing a value is safe. Key settings:

| Line | Default | Notes |
|------|---------|-------|
| `EnableControlledFolderAccess` | `AuditMode` | Change to `Enabled` to enforce |
| `EnableNetworkProtection` | `AuditMode` | Change to `Enabled` to enforce |
| `CloudBlockLevel` | `High` | Options: `Default`, `Moderate`, `High`, `ZeroTolerance` |
| `ScanScheduleDay` | `Sunday` | Any day of the week |

Full reference: https://learn.microsoft.com/en-us/powershell/module/defender/set-mppreference

### Changing firewall rules — `policies/firewall.ps1`

Edit `Set-NetFirewallProfile` calls to adjust inbound/outbound defaults per profile. To add custom inbound rules, append `New-NetFirewallRule` calls, for example:

```powershell
New-NetFirewallRule -DisplayName "Allow RDP" -Direction Inbound -Protocol TCP -LocalPort 3389 -Action Allow
```

Full reference: https://learn.microsoft.com/en-us/powershell/module/netsecurity/set-netfirewallprofile

---

## Bootstrap Switches

Call `bootstrap.ps1` with any combination of the parameters below. When running via a USB payload, append switches to the end of the `iex (irm ...)` line.

| Switch | Type | Default | Description |
|--------|------|---------|-------------|
| `-BaseUrl` | `string` | `https://raw.githubusercontent.com/bugboilerjr/provisioning-tool/main` | Base URL all companion files are downloaded from. Override to point at a different fork, branch, or host. |
| `-SkipApps` | switch | off | Skip Phase 2 — do not install any apps from `apps.json`. |
| `-SkipPolicies` | switch | off | Skip Phases 3 & 4 — do not apply secedit, Defender, or firewall settings. |
| `-SkipOffice` | switch | off | Skip Phase 5 — do not install Microsoft 365. |

**Examples**

Install apps only, skip policies and Office:
```powershell
iex "& { $(irm $url) } -SkipPolicies -SkipOffice"
```

Apply policies only, skip apps and Office:
```powershell
iex "& { $(irm $url) } -SkipApps -SkipOffice"
```

Point at a different branch:
```powershell
iex "& { $(irm $url) } -BaseUrl 'https://raw.githubusercontent.com/myorg/myrepo/staging'"
```

---

## Testing Without a USB Device

From an elevated PowerShell, paste (replacing the URL with your repo):

```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
iex (irm https://raw.githubusercontent.com/bugboilerjr/provisioning-tool/main/bootstrap.ps1)
```

This is the exact command the Ducky or Flipper types. Running it manually is the fastest way to iterate and debug before flashing any device.

---

## Logs

Each run writes a full PowerShell transcript to:
```
C:\ProgramData\Provisioning\logs\provision-<timestamp>.log
```
`secedit` also writes its own log to `%windir%\security\logs\scesrv.log`.

---

## Gotchas

- **UAC timing.** If the Ducky races the UAC prompt on slow machines or fresh installs, increase the `DELAY 3500` after the Win+X sequence in `payload.txt`.
- **Defender / SmartScreen.** Scripts pulled from `raw.githubusercontent.com` and executed via `iex` (never saved to disk) typically bypass SmartScreen. If you get blocked, sign the script or host it on a domain in your AppLocker allowlist.
- **EDR on corporate machines.** Endpoint detection products may flag rapid keystroke injection. Test on a target machine before relying on this in the field.
- **Controlled Folder Access + Network Protection** start in `AuditMode`. Flip to `Enabled` in `defender.ps1` after confirming no legitimate apps are blocked.
- **M365 license activation.** `AUTOACTIVATE=0` requires the user to sign in manually on first launch. Set to `1` for device-based / volume licenses.
- **ODT download time.** The Office install (Phase 5) downloads ~2 GB from Microsoft CDN and takes 10–20 minutes depending on connection speed.

---

## Flashing the Payload to a USB Device

### Hak5 USB Rubber Ducky (Gen 2 / DuckyScript 3.x)

The payload in `ducky/payload.txt` is written in DuckyScript and is compatible with the Gen 2 Rubber Ducky.

**Option A — Payload Studio (browser-based IDE)**
1. Go to **https://payloadstudio.hak5.org**
2. Paste or open `ducky/payload.txt`
3. Click **Compile** → download `inject.bin`
4. Copy `inject.bin` to the root of the Ducky's micro-SD card
5. Safely eject and plug in the Ducky

**Option B — DuckEncoder CLI**
```bash
java -jar duckencoder.jar -i payload.txt -o inject.bin
```
Copy `inject.bin` to the SD card.

> **Gen 1 Ducky note:** If you have a first-generation Ducky, use the older `duckencoder.jar`. Some DuckyScript 3.x syntax (`LEFTARROW`, `RIGHTARROW`) may not be supported — test carefully.

**Resources**
- Payload Studio: https://payloadstudio.hak5.org
- DuckyScript 3.x language reference: https://docs.hak5.org/hak5-usb-rubber-ducky
- Hak5 community payload library: https://github.com/hak5/usbrubberducky-payloads

---

### Flipper Zero — Bad USB

The Flipper Zero has a built-in Bad USB app that executes DuckyScript-compatible payloads from its SD card. The payload in `ducky/payload.txt` should work with minimal or no changes, as Flipper's Bad USB implementation supports the core DuckyScript instruction set.

> ⚠️ **Untested on Flipper Zero.** UAC navigation (`LEFTARROW` + `ENTER`) is timing-sensitive — test on a target machine and tune `DELAY` values as needed before deploying.

**Steps**
1. Copy `ducky/payload.txt` to your Flipper's SD card under `badusb/`
   - Use **qFlipper** (https://flipperzero.one/update) to drag and drop over USB, or the Flipper Mobile App
2. On the Flipper: navigate to **Applications → Bad USB**
3. Select your payload file and press the center button to run

**Tips for Flipper**
- Flipper types at HID speed; if UAC is slow to appear, add an extra `DELAY 2000` before the `LEFTARROW` / `ENTER` lines in the payload
- Some Flipper firmware builds (Unleashed, RogueMaster) add extra DuckyScript extensions — the standard commands used here are supported on all builds
- The Flipper can also act as a Bad USB over Bluetooth via the mobile app, which is useful for wireless deployment scenarios

**Resources**
- Official Bad USB docs: https://docs.flipper.net/bad-usb
- Flipper DuckyScript compatibility notes: https://github.com/flipperdevices/flipperzero-firmware/blob/dev/documentation/bad_usb/BadUSB-Ducky-script.md
- qFlipper desktop tool: https://flipperzero.one/update
- Flipper community payload library: https://github.com/UberGuidoZ/Flipper/tree/main/Bad_USB
- Flipper app store: https://lab.flipper.net/apps

---

## Quick Reference — All Resources

| Resource | URL |
|----------|-----|
| winget package search | https://winget.run |
| winget documentation | https://learn.microsoft.com/en-us/windows/package-manager/winget |
| Office Customization Tool | https://config.office.com |
| Office Deployment Tool download | https://aka.ms/ODT |
| secedit policy reference | https://learn.microsoft.com/en-us/windows/security/threat-protection/security-policy-settings/security-policy-settings |
| Set-MpPreference (Defender) | https://learn.microsoft.com/en-us/powershell/module/defender/set-mppreference |
| Set-NetFirewallProfile | https://learn.microsoft.com/en-us/powershell/module/netsecurity/set-netfirewallprofile |
| Hak5 Rubber Ducky docs | https://docs.hak5.org/hak5-usb-rubber-ducky |
| Hak5 Payload Studio | https://payloadstudio.hak5.org |
| Hak5 community payloads | https://github.com/hak5/usbrubberducky-payloads |
| Flipper Zero Bad USB docs | https://docs.flipper.net/bad-usb |
| Flipper DuckyScript compat | https://github.com/flipperdevices/flipperzero-firmware/blob/dev/documentation/bad_usb/BadUSB-Ducky-script.md |
| qFlipper desktop tool | https://flipperzero.one/update |
| Flipper community payloads | https://github.com/UberGuidoZ/Flipper/tree/main/Bad_USB |
