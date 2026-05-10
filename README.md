# Windows Provisioning Tool

Plug in a Rubber Ducky → an elevated PowerShell opens → a one-line bootstrap pulls this repo from GitHub → apps install, policies apply, Microsoft 365 deploys.

## How it fits together

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

## Customizing

- **Apps:** edit `apps.json`. Find IDs with `winget search <name>`.
- **Office apps included:** edit the `<ExcludeApp>` lines in `office/configuration.xml`, or generate a fresh one at <https://config.office.com>.
- **Security baseline:** edit `policies/secedit.inf` and the two `policies/*.ps1` scripts. They're idempotent — safe to re-run.
- **Skip a phase on a given run:** call the bootstrap with switches, e.g. `iex "& { $(irm $url) } -SkipOffice"`.

## Testing without the Ducky

From an elevated PowerShell, paste:

```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
iex (irm https://raw.githubusercontent.com/YOUR-USERNAME/provisioning/main/bootstrap.ps1)
```

This is the exact line the Ducky types — running it manually is the fastest way to debug.

## Logs

Each run writes a transcript to `C:\ProgramData\Provisioning\logs\provision-<timestamp>.log`.

## Gotchas

- **UAC timing.** If the Ducky races the UAC prompt on slow machines, increase the `DELAY 3500` after the Win+X sequence in `payload.txt`.
- **Defender / SmartScreen.** Scripts pulled from `raw.githubusercontent.com` usually run cleanly because they're invoked via `iex`, not saved as files. If you get blocked, sign the script or host on a custom domain in your AppLocker allowlist.
- **Endpoint detection (corp machines).** EDR products may flag fast keystroke injection. Test on a target machine before relying on this in the field.
- **Controlled Folder Access + Network Protection** start in `AuditMode` in `defender.ps1`. Flip to `Enabled` once you've confirmed nothing legitimate is being blocked.
- **M365 license activation.** The XML sets `AUTOACTIVATE=0` so the user signs in on first launch. Set to `1` if you have a device-based license.
