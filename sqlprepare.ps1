param (
    [string]$databaseName,
    [string]$serverInstance = $env:COMPUTERNAME,
    [string]$dataFilePath = "C:\Program Files\Microsoft SQL Server\MSSQL15.SQLEXPRESS\MSSQL\DATA\",
    [string]$logFilePath = "C:\Program Files\Microsoft SQL Server\MSSQL15.SQLEXPRESS\MSSQL\DATA\",
    [string]$backupFilePath = "C:\tools\SQLSTF\tpch.bak"
)

function Show-Help {
    Write-Host "Usage: Create-SqlDatabase.ps1 -databaseName <DatabaseName> [-serverInstance <ServerInstance>] [-dataFilePath <DataFilePath>] [-logFilePath <LogFilePath>] [-backupFilePath <BackupFilePath>]"
    Write-Host "  -databaseName     : The name of the database to create or restore (required)"
    Write-Host "  -serverInstance   : SQL Server instance name (default: %HOSTNAME%)"
    Write-Host "  -dataFilePath     : Path for the data file (default: C:\Program Files\Microsoft SQL Server\MSSQL15.SQLEXPRESS\MSSQL\DATA\)"
    Write-Host "  -logFilePath      : Path for the log file (default: C:\Program Files\Microsoft SQL Server\MSSQL15.SQLEXPRESS\MSSQL\DATA\)"
    Write-Host "  -backupFilePath   : Path to the backup file for restore (required for restore)"
    exit 1
}

function Install-SqlServer {
    param (
        [string]$ssmspath = "https://aka.ms/ssmsfullsetup",
        [string]$IsoPath = "https://download.microsoft.com/download/7/c/1/7c14e92e-bdcb-4f89-b7cf-93543e7112d1/SQLServer2019-x64-ENU-Dev.iso",
        [string]$dist = "C:\Tools\SQLSTF\",
        [string]$admuser = "`"$(whoami)`""
    )

    try {
        Add-Content -Path (Join-Path $dist 'ConfigurationFile.ini') -Value "`r`nSQLSYSADMINACCOUNTS=$admuser"
        Start-Sleep -Seconds 2

        # Download SQL ISO
        Start-BitsTransfer -Source $IsoPath -Destination $dist
        $isoimg = Join-Path $dist 'SQLServer2019-x64-ENU-Dev.iso'
        Start-Sleep -Seconds 2

        $volume = Mount-DiskImage $isoimg -StorageType ISO -PassThru | Get-Volume
        $sql_drive = $volume.DriveLetter + ':'
        Start-Sleep -Seconds 2

        # Start SQL server installation
        Start-Process (Join-Path $sql_drive 'setup.exe') -ArgumentList "/ConfigurationFile=$dist\ConfigurationFile.ini" -NoNewWindow -Wait
        Dismount-DiskImage $isoimg

        # Start Studio installation
        $setupfile = Join-Path $dist 'ssmsfullsetup.exe'
        Start-BitsTransfer -Source $ssmspath -Destination $setupfile
        Start-Sleep -Seconds 2
        Start-Process $setupfile -ArgumentList "/install", "/quiet", "/norestart" -NoNewWindow -Wait
    }
    catch {
        Write-Error "An error occurred: $_"
        exit 1
    }
}

# Check if required parameters are provided
if (-not $databaseName) {
    Show-Help
}

function Restore-DB {

    # Connection string using Windows authentication
    $connectionString = "Server=$serverInstance;Database=master;Integrated Security=True;"

    # Check if data and log directories exist, create them if not
    if (-not (Test-Path $dataFilePath)) {
        New-Item -ItemType Directory -Path $dataFilePath -Force | Out-Null
    }

    if (-not (Test-Path $logFilePath)) {
        New-Item -ItemType Directory -Path $logFilePath -Force | Out-Null
    }
    try {
        # Check if backup file path is provided for restore
        if ($backupFilePath) {
            # SQL query to restore database from backup
            $query = "RESTORE DATABASE [$databaseName] FROM DISK = '$backupFilePath' WITH REPLACE, MOVE 'tpch' TO '$dataFilePath\$databaseName.mdf', MOVE 'tpch_log' TO '$logFilePath\$databaseName.ldf';"

        # Create SQL connection
        $connection = New-Object System.Data.SqlClient.SqlConnection
        $connection.ConnectionString = $connectionString
        $connection.Open()

        # Execute the query
        $command = $connection.CreateCommand()
        $command.CommandText = $query
        $command.ExecuteNonQuery()

        Write-Host "Database '$databaseName' restored successfully on '$serverInstance' from backup file '$backupFilePath'."
        }
        else {
            Write-Error "File  '$backupFilePath' can't ne found!"
            exit 1
        }
    }
    catch {
        Write-Host "Error: $_.Exception.Message"
    }
    finally {
        # Close the connection
        $connection.Close()
    }
}

# Call SQL Setup
Install-SqlServer
# Call DB restore
Restore-DB
exit 0

