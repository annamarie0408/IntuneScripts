# Deploying Network Printers by IP via PowerShell + Intune

A reusable PowerShell approach for adding IP-based network printers using Windows' built-in generic class drivers — no vendor driver required — with idempotent checks and Intune Proactive Remediation support for reporting.

## Why use this approach

Vendor printer drivers are a pain at scale: they need to be downloaded, staged, and kept updated per model. Windows ships built-in **class drivers** that work with most modern network printers without any vendor software:

| Driver Name | Best For |
|---|---|
| `Microsoft PCL6 Class Driver` | Most network printers (PCL6-capable) — recommended default |
| `Microsoft PS Class Driver` | PostScript printers |
| `Microsoft IPP Class Driver` | Printers advertising IPP / "IPP Everywhere" / AirPrint support |
| `Microsoft XPS Class Driver` | XPS-capable printers |
| `Generic / Text Only` | Raw text printing only, no graphics/formatting |

This guide uses `Microsoft PCL6 Class Driver` with a **Standard TCP/IP port**, which is the most broadly compatible option and works well as a "just get it working" default across mixed-vendor printer fleets.

> **IPP vs. PCL6 note:** IPP is a full protocol (runs over HTTP, typically port 631) and gives richer status/queue feedback, while PCL6 pairs with a raw TCP/IP port (typically port 9100). If you're not certain a printer supports IPP well, PCL6 + Standard TCP/IP Port is the safer, more universal choice.

## The script

This script is idempotent — it checks whether the printer already exists with the correct port and driver before doing anything. If everything already matches, it exits cleanly with no changes.

```powershell
$printerName = "PRINTER_NAME_HERE"
$ipAddress   = "PRINTER_IP_HERE"
$portName    = "IP_$ipAddress"
$driverName  = "Microsoft PCL6 Class Driver"

# Check if the printer already exists and matches everything
$existingPrinter = Get-Printer -Name $printerName -ErrorAction SilentlyContinue

if ($existingPrinter -and
    $existingPrinter.PortName -eq $portName -and
    $existingPrinter.DriverName -eq $driverName) {

    Write-Host "Printer '$printerName' already exists and matches (Port: $portName, Driver: $driverName). No action needed." -ForegroundColor Green
    exit
}

Write-Host "Printer '$printerName' is missing or misconfigured. Proceeding with setup..." -ForegroundColor Yellow

# Ensure the port exists
if (-not (Get-PrinterPort -Name $portName -ErrorAction SilentlyContinue)) {
    Write-Host "Creating port '$portName'..."
    Add-PrinterPort -Name $portName -PrinterHostAddress $ipAddress
} else {
    Write-Host "Port '$portName' already exists."
}

# Ensure the driver exists
if (-not (Get-PrinterDriver -Name $driverName -ErrorAction SilentlyContinue)) {
    Write-Host "Installing driver '$driverName'..."
    Add-PrinterDriver -Name $driverName
} else {
    Write-Host "Driver '$driverName' already exists."
}

# If the printer exists but is misconfigured (wrong port/driver), remove it first
if ($existingPrinter) {
    Write-Host "Removing existing misconfigured printer '$printerName'..."
    Remove-Printer -Name $printerName
}

# Add the printer
Write-Host "Adding printer '$printerName'..."
Add-Printer -Name $printerName -DriverName $driverName -PortName $portName

Write-Host "Setup complete for '$printerName'." -ForegroundColor Green
```

Just replace `PRINTER_NAME_HERE` and `PRINTER_IP_HERE` at the top and run.

## Constrained Language Mode note

If your environment runs PowerShell in **Constrained Language Mode** (common under AppLocker/WDAC), you may hit:

```
Cannot convert value to type "System.Management.Automation.LanguagePrimitives+InternalPSCustomObject".
Only core types are supported in this language mode.
```

This happens whenever a script tries to build `[PSCustomObject]@{...}` output. Check your mode with:

```powershell
$ExecutionContext.SessionState.LanguageMode
```

The install script above avoids this entirely since it doesn't construct custom objects. If you're also pulling a **report of printers and IPs** (see below), use `Select-Object` with calculated properties instead of `[PSCustomObject]`, since it's Constrained Language Mode-safe:

```powershell
Get-Printer | Select-Object Name, PortName, `
    @{Name="IPAddress"; Expression={ (Get-PrinterPort -Name $_.PortName -ErrorAction SilentlyContinue).PrinterHostAddress }} |
    Where-Object { $_.IPAddress }
```

## Deploying via Microsoft Intune

Intune offers two ways to run this, with very different reporting capabilities.

### Option A: Platform Script (basic pass/fail)

Deployed under **Devices > Scripts**, this only reports an exit code back to Intune — `Write-Host` output is *not* visible in the console. You get a green check or red X per device, nothing more. Add explicit exit codes if you use this route:

```powershell
# ... setup logic ...

$check = Get-Printer -Name $printerName -ErrorAction SilentlyContinue
if ($check -and $check.PortName -eq $portName -and $check.DriverName -eq $driverName) {
    exit 0
} else {
    exit 1
}
```

### Option B: Proactive Remediation (detailed reporting) — recommended

Under **Devices > Scripts and remediations**, remediations pair a **detection script** with a **remediation script**. Critically, `Write-Host` output from both scripts *is* captured and shown per-device in the Intune console under the remediation's device status report.

**Detection script:**

```powershell
$printerName = "PRINTER_NAME_HERE"
$ipAddress   = "PRINTER_IP_HERE"
$portName    = "IP_$ipAddress"
$driverName  = "Microsoft PCL6 Class Driver"

$existingPrinter = Get-Printer -Name $printerName -ErrorAction SilentlyContinue

if ($existingPrinter -and $existingPrinter.PortName -eq $portName -and $existingPrinter.DriverName -eq $driverName) {
    Write-Host "Compliant: Printer '$printerName' exists with correct port and driver."
    exit 0   # Compliant — remediation script will NOT run
} else {
    Write-Host "Non-compliant: Printer missing or misconfigured."
    exit 1   # Non-compliant — triggers remediation script
}
```

**Remediation script:**

```powershell
$printerName = "PRINTER_NAME_HERE"
$ipAddress   = "PRINTER_IP_HERE"
$portName    = "IP_$ipAddress"
$driverName  = "Microsoft PCL6 Class Driver"

try {
    if (-not (Get-PrinterPort -Name $portName -ErrorAction SilentlyContinue)) {
        Add-PrinterPort -Name $portName -PrinterHostAddress $ipAddress
    }

    if (-not (Get-PrinterDriver -Name $driverName -ErrorAction SilentlyContinue)) {
        Add-PrinterDriver -Name $driverName
    }

    $existingPrinter = Get-Printer -Name $printerName -ErrorAction SilentlyContinue
    if ($existingPrinter) {
        Remove-Printer -Name $printerName
    }

    Add-Printer -Name $printerName -DriverName $driverName -PortName $portName

    Write-Host "Remediation successful: Printer '$printerName' installed."
    exit 0
} catch {
    Write-Host "Remediation failed: $($_.Exception.Message)"
    exit 1
}
```

With this setup, you get actual text output per device — detection result, remediation result, and pre/post state — instead of just a pass/fail flag.

### Gotchas to plan for

- **Runs as SYSTEM by default.** Printers added in the SYSTEM context may not automatically appear for the logged-in user. Either configure the script to run in user context (both script types have this toggle) or push the printer connection separately via GPP or an Intune printer policy.
- **32-bit vs. 64-bit PowerShell.** Intune defaults to 64-bit unless you enable "Run script in 64-bit PowerShell Host." Confirm this is checked for consistent `Add-Printer` behavior.
- **Script signing.** If your tenant enforces signed scripts, both detection and remediation scripts must comply.
- **Remediation scheduling.** Remediations run on whatever schedule you configure (hourly, daily, etc.) — not just once. This is useful for ongoing enforcement but plan accordingly if you only want a one-time deployment.

## Getting a list of printers and IPs on a machine

Handy for auditing before or after deployment:

```powershell
Get-Printer | Select-Object Name, DriverName, PortName, `
    @{Name="IPAddress"; Expression={ (Get-PrinterPort -Name $_.PortName -ErrorAction SilentlyContinue).PrinterHostAddress }}
```

Filtered to network printers only:

```powershell
Get-Printer | Select-Object Name, PortName, `
    @{Name="IPAddress"; Expression={ (Get-PrinterPort -Name $_.PortName -ErrorAction SilentlyContinue).PrinterHostAddress }} |
    Where-Object { $_.IPAddress }
```

Exported to CSV, tagged with computer name (useful when collected across a fleet):

```powershell
Get-Printer | Select-Object `
    @{Name="ComputerName"; Expression={ $env:COMPUTERNAME }},
    Name,
    DriverName,
    @{Name="IPAddress"; Expression={ (Get-PrinterPort -Name $_.PortName -ErrorAction SilentlyContinue).PrinterHostAddress }} |
    Export-Csv -Path "C:\Temp\PrinterList.csv" -NoTypeInformation -Append
```

## Summary

- Use `Microsoft PCL6 Class Driver` with a Standard TCP/IP port for the broadest, driver-free compatibility.
- Make install scripts idempotent — check before you act, so re-runs are safe and no-ops when nothing's wrong.
- For real per-device visibility in Intune, use **Proactive Remediations**, not a plain platform script.
- Avoid `[PSCustomObject]` in any script that might run in Constrained Language Mode environments; use `Select-Object` with calculated properties instead.
