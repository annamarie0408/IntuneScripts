# Autodesk Access — Allow Standard Users to Install Updates (Intune Remediation)

An Intune detection/remediation script pair that sets `AllowSystemContextInstall` so standard
users can install Autodesk product updates through **Autodesk Access** without local admin
rights and without a UAC prompt.

---

## Background

Autodesk Access does not perform the install itself. The **Autodesk Access Service Host**
(`AdskAccessServiceHost.exe`, in `C:\Program Files\Autodesk\AdODIS\V1\Setup`) already runs as
SYSTEM. Access simply refuses to hand the job to that service unless it believes the signed-in
user is permitted to install software — which is where the **"Permission required"** prompt
comes from.

Setting the following machine-wide value tells Access to perform the update in system context
using the service it already owns:

```
HKEY_LOCAL_MACHINE\SOFTWARE\Autodesk\ODIS
    AllowSystemContextInstall    REG_DWORD    1
```

Users see no change in the Access interface, but they are no longer prompted for UAC
credentials when installing updates. Scope is limited to **Autodesk product updates delivered
through Access** — it does not grant install rights to anything else, and does not cover new
product installs or major-version upgrades.

### Why not Endpoint Privilege Management?

EPM can be made to work, but it fits poorly here:

- Access is a per-user app tied to the user's Autodesk sign-in and HKCU, so EPM's default
  virtual-account elevation breaks it. You would need the *Elevate as current user* elevation
  type, which cannot be an automatic rule — the user gets a credential prompt every time.
- The install is a chain (bootstrapper → `msiexec` → component installers) with binary names
  that change each release, forcing **Allow all child processes to run elevated**.
- Payloads land in `%ProgramData%\Autodesk\ODIS\...`, a user-writable path, which violates
  Microsoft's guidance to path-restrict elevation rules to locations standard users cannot
  modify.

Keep EPM in reserve for the handful of products that fail under system-context install.

---

## Contents

| File | Purpose |
|---|---|
| `Detect-AutodeskAllowSystemContextInstall.ps1` | Detection script. Exit `0` = compliant, exit `1` = triggers remediation. |
| `Remediate-AutodeskAllowSystemContextInstall.ps1` | Remediation script. Creates the key and sets the value. Exit `0` = success. |

---

## Deployment

**Microsoft Intune admin center** → **Devices** → **Scripts and remediations** →
**Remediations** → **Create script package**

Upload both scripts, then configure:

| Setting | Value |
|---|---|
| Run this script using the logged-on credentials | **No** (SYSTEM is required for HKLM) |
| Enforce script signature check | **No** |
| Run script in 64-bit PowerShell | **Yes** |
| Schedule | Daily (hourly is unnecessary; this rarely drifts) |

> **The 64-bit setting is not optional.** In a 32-bit host the write is redirected to
> `HKLM\SOFTWARE\WOW6432Node\Autodesk\ODIS`, which Autodesk Access does not read.

Assign to the device group that has Autodesk products installed. Device-targeted is correct
here — the value is machine-wide, not per-user.

---

## Implementation notes

Both scripts open the registry through
`[Microsoft.Win32.RegistryKey]::OpenBaseKey(..., RegistryView::Registry64)` rather than the
`HKLM:` PSDrive, so they behave identically regardless of which PowerShell host they land in.

Detection validates the **value type**, not just the value. If `AllowSystemContextInstall`
exists as a `REG_SZ` of `"1"`, Access ignores it, but a naive `-eq 1` comparison in PowerShell
would coerce the string and report compliant. Detection also fails toward remediation on any
unexpected error rather than silently passing.

Remediation deletes a wrong-typed value before rewriting it as `DWord`, verifies the write by
reading the value back, and removes a stray `Wow6432Node` copy if an earlier 32-bit script left
one behind.

---

## Related registry values

These live alongside `AllowSystemContextInstall` and will quietly defeat it if set:

| Value | Hive | Effect |
|---|---|---|
| `DisableManualUpdateInstall` | `HKCU\Software\Autodesk\ODIS` | `1` blocks the user from installing updates at all. Must be absent or `0`. |
| `DisableAutoUpdate` | `HKLM\SOFTWARE\Autodesk\ODIS` | `1` disables background auto-updates. Independent of the above; set it to taste. |

`DisableManualUpdateInstall` is in **HKCU**, so a SYSTEM-context remediation cannot reach it.
If it is set anywhere in your environment from a legacy GPO or logon script, users will remain
blocked. That requires a separate user-context script or Group Policy Preferences cleanup.

---

## Known limitations

- **Not every Autodesk product updates successfully under system context.** Vault Client and a
  handful of others have historically been exceptions. Pilot before broad rollout and check the
  current exclusion list from Autodesk or your reseller.
- Covers **updates only** — new installs and major version upgrades still belong in your Win32
  app pipeline.
- Older Autodesk Access / AdODIS builds honor this value inconsistently. Make sure the Access
  components are current before troubleshooting.

---

## Verification

On a target device:

```powershell
Get-ItemProperty -Path 'HKLM:\SOFTWARE\Autodesk\ODIS' -Name 'AllowSystemContextInstall'
```

Then sign in as a standard user, open Autodesk Access, and install an available update. It
should complete with no UAC prompt and no "Permission required" dialog.

Autodesk Access logs are under `%LOCALAPPDATA%\Autodesk\ODIS\` if an install still fails.

---

## References

- [Give users permission to install updates from Autodesk Access](https://resources.imaginit.com/support-blog/give-users-permission-to-install-updates-from-autodesk-access)
- ["Permission required" when installing an update from Autodesk Access](https://www.autodesk.com/support/technical/article/caas/sfdcarticles/sfdcarticles/Permission-required-when-trying-to-install-an-update-from-Autodesk-Access.html)
- [Creating elevation rules with Endpoint Privilege Management](https://learn.microsoft.com/en-us/intune/epm/create-elevation-rules)

---

## License

MIT — use at your own risk. Test in a pilot ring before deploying to production.
