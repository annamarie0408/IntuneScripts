<#
.SYNOPSIS
    Intune Remediations - DETECTION script.
    Checks for HKLM\SOFTWARE\Autodesk\ODIS\AllowSystemContextInstall = 1 (REG_DWORD).

.DESCRIPTION
    This value allows standard users to install Autodesk product updates through
    Autodesk Access without admin rights or a UAC prompt. The install is performed
    in system context by the Autodesk Access Service Host.

.NOTES
    Exit 0 = compliant   (no remediation runs)
    Exit 1 = non-compliant (remediation runs)

    Run as:                        SYSTEM (Run this script using the logged-on credentials = No)
    Run in 64-bit PowerShell host: Yes
    Enforce signature check:       No
#>

$subKey    = 'SOFTWARE\Autodesk\ODIS'
$valueName = 'AllowSystemContextInstall'
$expected  = 1

try {
    # Open the 64-bit view explicitly so we never land in Wow6432Node
    $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
        [Microsoft.Win32.RegistryHive]::LocalMachine,
        [Microsoft.Win32.RegistryView]::Registry64
    )

    $odis = $baseKey.OpenSubKey($subKey)

    if ($null -eq $odis) {
        Write-Output "Non-compliant: HKLM\$subKey does not exist."
        exit 1
    }

    $current = $odis.GetValue($valueName, $null)

    if ($null -eq $current) {
        Write-Output "Non-compliant: $valueName is not present under HKLM\$subKey."
        exit 1
    }

    $kind = $odis.GetValueKind($valueName)

    if ($kind -ne [Microsoft.Win32.RegistryValueKind]::DWord) {
        Write-Output "Non-compliant: $valueName exists but is $kind, expected DWord (current value: $current)."
        exit 1
    }

    if ([int]$current -ne $expected) {
        Write-Output "Non-compliant: $valueName = $current, expected $expected."
        exit 1
    }

    Write-Output "Compliant: $valueName = $current (DWord)."
    exit 0
}
catch {
    # Fail toward remediation rather than silently passing
    Write-Output "Non-compliant: detection error - $($_.Exception.Message)"
    exit 1
}
finally {
    if ($odis)    { $odis.Dispose() }
    if ($baseKey) { $baseKey.Dispose() }
}
