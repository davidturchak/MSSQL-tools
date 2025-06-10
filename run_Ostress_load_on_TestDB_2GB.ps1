<#
.SYNOPSIS
Runs Ostress.exe via cmd.exe with specified parameters.

.DESCRIPTION
This script builds a command line for Ostress.exe and launches it through cmd.exe.

.PARAMETER TestDuration
Test duration in minutes for @TestDuration_Minutes.

.PARAMETER ReadRatio
Read ratio for @ReadRatio.

.PARAMETER NumberOfUsers
Number of users passed to -n.

.PARAMETER Repeat
Number of repetitions passed to -r.

.EXAMPLE
.\Run-OstressTest.ps1 -TestDuration 5 -ReadRatio 50 -NumberOfUsers 200 -Repeat 2
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

# Path to OStress executable
$ostressPath = '"C:\Program Files\Microsoft Corporation\RMLUtils\Ostress.exe"'

# Construct SQL query string (escaped for cmd)
$sqlQuery = "EXECUTE dbo.RunTest @ReadRatio = $ReadRatio , @TestDuration_Minutes = $TestDuration;"

# Build the full command line for cmd.exe
$cmdCommand = "$ostressPath -DNoSSLTest -E -dTestDB_2G -Q`"$sqlQuery`" -n$NumberOfUsers -r$Repeat"

# Output the command to verify
Write-Host "Running in cmd.exe:"
Write-Host $cmdCommand

# Start cmd.exe and run the command
Start-Process cmd.exe -ArgumentList "/c $cmdCommand" -Wait
