<#
.SYNOPSIS
Runs a stored procedure in a SQL Server database and optionally performs a full backup.

.DESCRIPTION
This script executes the stored procedure named "UpdateCustomerBalances<DatabaseName>" in the given database.
If the -DoBackup switch is provided, it performs a full backup of the database after running the stored procedure.

.PARAMETER commitCount
Number of commits to perform in the stored procedure. Default is 1.

.PARAMETER database
Name of the SQL Server database. Default is "full_db_1".

.PARAMETER DoBackup
Switch to trigger a full database backup. If omitted, no backup is performed.

.EXAMPLE
.\trigger_store_procedure.ps1 -commitCount 5 -database "full_db_1"
Runs the stored procedure without performing a backup.

.EXAMPLE
.\trigger_store_procedure.ps1 -commitCount 5 -database "full_db_1" -DoBackup
Runs the stored procedure and then performs a full backup.

.NOTES
Author: David Turchak
Date: 2025-05-19
#>

param (
    [int]$commitCount = 1,
    [string]$database = "full_db_1",
    [switch]$DoBackup
)

$server = "localhost"
$user = "sa"
$password = "P@ssword"
$procedureName = "UpdateCustomerBalances$database"

while ($true) {
    try {
        # Run the stored procedure
        Invoke-Sqlcmd -ServerInstance $server `
                      -Username $user `
                      -Password $password `
                      -Database $database `
                      -Query "EXEC [dbo].[$procedureName] @commitCount = $commitCount"

        if ($DoBackup) {
            # Get the database file path (data file)
            $dataFileQuery = @"
SELECT physical_name 
FROM sys.master_files 
WHERE database_id = DB_ID('$database') AND type_desc = 'ROWS'
"@

            $dataFilePath = Invoke-Sqlcmd -ServerInstance $server `
                                         -Username $user `
                                         -Password $password `
                                         -Database "master" `
                                         -Query $dataFileQuery | Select-Object -ExpandProperty physical_name

            # Get the folder of the data file
            $backupFolder = Split-Path -Path $dataFilePath

            # Define backup file path (overwrite if exists)
            $backupFile = Join-Path $backupFolder "$database-Full.bak"

            # Delete existing backup file if it exists
            if (Test-Path $backupFile) {
                Remove-Item $backupFile -Force
            }

            # Backup the database
            $backupQuery = "BACKUP DATABASE [$database] TO DISK = N'$backupFile' WITH INIT, FORMAT"

            Invoke-Sqlcmd -ServerInstance $server `
                          -Username $user `
                          -Password $password `
                          -Database "master" `
                          -Query $backupQuery

            Write-Host "Backup completed at $(Get-Date) to $backupFile"
        }
    }
    catch {
        Write-Host "Error: $($_.Exception.Message)"
    }
}