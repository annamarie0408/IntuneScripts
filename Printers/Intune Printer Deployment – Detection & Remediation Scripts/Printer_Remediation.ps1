$printerName = "Office Printer"
$ipAddress   = "192.168.1.100"
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
