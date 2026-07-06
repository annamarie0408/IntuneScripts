$PrinterName = "What you want printer named"
$PrinterIP = "what the IP is"
$DriverName = "Microsoft IPP Class Driver" #leave this as this is required to install a printer with the IPP printer class, this is required for printers being added by IP

$ExistingPort = Get-PrinterPort | Where-Object {
    $_.PrinterHostAddress -eq $PrinterIP
} | Select-Object -First 1

if ($ExistingPort) {
    Write-Host "Found printer port with host address $PrinterIP. Port name: $($ExistingPort.Name)"

    $ExistingPrinter = Get-Printer -Name $PrinterName -ErrorAction SilentlyContinue

    if ($ExistingPrinter) {
        Write-Host "Printer '$PrinterName' already exists. No action needed."
    }
    else {
        Write-Host "Adding printer '$PrinterName' using port '$($ExistingPort.Name)'."

        Add-Printer -Name $PrinterName `
            -DriverName $DriverName `
            -PortName $ExistingPort.Name

        Write-Host "Printer '$PrinterName' added successfully."
    }
}
else {
    Write-Host "No printer port found with host address $PrinterIP. Printer was not added."
}
