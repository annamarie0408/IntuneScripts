<#
.SYNOPSIS
    Intune Remediations - REMEDIATION script.
    Creates HKLM\SOFTWARE\Autodesk\ODIS and sets AllowSystemContextInstall = 1 (REG_DWORD).

.DESCRIPTION
    Lets standard users install Autodesk product updates via Autodesk Access with no
    admin rights and no UAC prompt. Also clears a stray value under Wow6432Node if a
    previous 32-bit script wrote one there, since Access reads the 64-bit view.

.NOTES
    Exit 0 = remediation succeeded
    Exit 1 = remediation failed

    Run as:                        SYSTEM (Run this script using the logged-on credentials = No)
    Run in 64-bit PowerShell host: Yes
    Enforce signature check:       No
#>

$subKey    = 'SOFTWARE\Autodesk\ODIS'
$valueName = 'AllowSystemContextInstall'
$desired   = 1

$baseKey = $null
$odis    = $null

try {
    $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
        [Microsoft.Win32.RegistryHive]::LocalMachine,
        [Microsoft.Win32.RegistryView]::Registry64
    )

    # CreateSubKey returns the existing key if it is already there
    $odis = $baseKey.CreateSubKey($subKey, $true)

    if ($null -eq $odis) {
        throw "Unable to create or open HKLM\$subKey."
    }

    # If the value exists with the wrong type, remove it so we can rewrite it as DWord
    if ($null -ne $odis.GetValue($valueName, $null)) {
        if ($odis.GetValueKind($valueName) -ne [Microsoft.Win32.RegistryValueKind]::DWord) {
            $odis.DeleteValue($valueName, $false)
        }
    }

    $odis.SetValue($valueName, $desired, [Microsoft.Win32.RegistryValueKind]::DWord)

    # Verify the write actually took
    $verify = $odis.GetValue($valueName, $null)
    if ([int]$verify -ne $desired) {
        throw "Write verification failed. $valueName = $verify."
    }

    Write-Output "Set HKLM\$subKey\$valueName = $verify (DWord)."

    # Clean up a stray 32-bit copy, which Autodesk Access does not read
    $wowKey = 'HKLM:\SOFTWARE\WOW6432Node\Autodesk\ODIS'
    if (Test-Path $wowKey) {
        $wowVal = Get-ItemProperty -Path $wowKey -Name $valueName -ErrorAction SilentlyContinue
        if ($null -ne $wowVal) {
            Remove-ItemProperty -Path $wowKey -Name $valueName -Force -ErrorAction SilentlyContinue
            Write-Output "Removed stray $valueName from $wowKey."
        }
    }

    exit 0
}
catch {
    Write-Output "Remediation failed: $($_.Exception.Message)"
    exit 1
}
finally {
    if ($odis)    { $odis.Dispose() }
    if ($baseKey) { $baseKey.Dispose() }
}
