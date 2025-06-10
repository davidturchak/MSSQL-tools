<#
.SYNOPSIS
Runs a parameterized Ostress.exe command to execute a SQL Server load test.

.DESCRIPTION
This script constructs and runs an Ostress.exe command using input parameters
for test duration, read ratio, number of users, and repeat count.

.PARAMETER TestDuration
Specifies the test duration in minutes for the @TestDuration_Minutes parameter.

.PARAMETER ReadRatio
Specifies the read ratio for the @ReadRatio parameter.

.PARAMETER NumberOfUsers
Specifies the number of users for the -n parameter.

.PARAMETER Repeat
Specifies how many times the test should repeat, passed to the -r parameter.

.EXAMPLE
.\Run-OstressTest.ps1 -TestDuration 5 -ReadRatio 50 -NumberOfUsers 200 -Repeat 2

.NOTES
Ostress.exe must be installed in "C:\Program Files\Microsoft Corporation\RMLUtils"
#>

param (
    [Parameter(Mandatory=$true)]
    [int]$TestDuration,

    [Parameter(Mandatory=$true)]
    [int]$ReadRatio,

    [Parameter(Mandatory=$true)]
    [int]$NumberOfUsers,

    [Parameter(Mandatory=$true)]
    [int]$Repeat
)

# Path to OStress executable
$ostressPath = "C:\Program Files\Microsoft Corporation\RMLUtils\Ostress.exe"

# Validate that the executable exists
if (-not (Test-Path $ostressPath)) {
    Write-Error "Ostress.exe not found at '$ostressPath'. Please verify the installation path."
    exit 1
}

# Construct the SQL query
$sqlQuery = "EXECUTE dbo.RunTest @ReadRatio = $ReadRatio , @TestDuration_Minutes = $TestDuration;"

# Build the command string
$command = "`"$ostressPath`" -DNoSSLTest -E -dTestDB_2GB -Q`"$sqlQuery`" -n$NumberOfUsers -r$Repeat"

# Output the command
Write-Host "Running command:"
Write-Host $command

# Run the command
Invoke-Expression $command
