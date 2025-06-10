<#
.SYNOPSIS
Runs Ostress.exe using cmd.exe with correct parameter quoting.

.DESCRIPTION
This script builds and runs a properly quoted Ostress.exe command inside cmd.exe.

.PARAMETER TestDuration
Test duration in minutes.

.PARAMETER ReadRatio
Read ratio to simulate read/write mix.

.PARAMETER NumberOfUsers
Number of concurrent users (-n).

.PARAMETER Repeat
Repeat count for the load test (-r).

.EXAMPLE
.\Run-OstressTest.ps1 -TestDuration 1 -ReadRatio 0 -NumberOfUsers 1 -Repeat 1
#>

param (
    [Parameter(Mandatory = $true)]
    [int]$TestDuration,

    [Parameter(Mandatory = $true)]
    [int]$ReadRatio,

    [Parameter(Mandatory = $true)]
    [int]$NumberOfUsers,

    [Parameter(Mandatory = $true)]
    [int]$Repeat
)

$DSNName = "noSSLTest"
# Registry paths (64-bit ODBC)
$regPath = "HKLM:\SOFTWARE\ODBC\ODBC.INI\$DSNName"

# Check if DSN  exists
if (-not (Test-Path $regPath)) {
    Write-Error "DSN '$DSNName' does not exist. Run create_odbc_noSSL.ps1 to create it."
    exit 1
} else {

# Define variables
$ostressExe = 'C:\Program Files\Microsoft Corporation\RMLUtils\Ostress.exe'
$sqlQuery = "EXECUTE dbo.RunTest @ReadRatio = $ReadRatio , @TestDuration_Minutes = $TestDuration;"

# Properly quote the full command for CMD
$quotedCommand = "`"$ostressExe`" -D$DSNName -E -dTestDB_2G -Q`"$sqlQuery`" -n$NumberOfUsers -r$Repeat"

# Wrap the entire command again for cmd.exe
$finalCommand = "/c `"$quotedCommand`""

# Print for debugging
Write-Host "Executing command via cmd.exe:"
Write-Host $finalCommand

# Run in cmd
Start-Process -FilePath "cmd.exe" -ArgumentList $finalCommand -Wait
}