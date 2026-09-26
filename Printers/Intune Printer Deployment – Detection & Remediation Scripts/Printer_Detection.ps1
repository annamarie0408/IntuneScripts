$printerName = "Office Printer"
$ipAddress   = "192.168.1.100"
$portName    = "IP_$ipAddress"
$driverName  = "Microsoft PCL6 Class Driver"

$existingPrinter = Get-Printer -Name $printerName -ErrorAction SilentlyContinue

if ($existingPrinter -and $existingPrinter.PortName -eq $portName -and $existingPrinter.DriverName -eq $driverName) {
    Write-Host "Compliant: Printer '$printerName' exists with correct port and driver."
    exit 0   # 0 = compliant, remediation script will NOT run
} else {
    Write-Host "Non-compliant: Printer missing or misconfigured."
    exit 1   # 1 = non-compliant, triggers remediation script
}
