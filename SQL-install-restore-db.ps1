param (
    [Parameter(Mandatory=$true)]
    [string]$databaseName,
    [string]$serverInstance = $env:COMPUTERNAME,
    [Parameter(Mandatory=$true)]
    [string]$dataFilePath = "C:\Program Files\Microsoft SQL Server\MSSQL15.SQLEXPRESS\MSSQL\DATA\",
    [Parameter(Mandatory=$true)]
    [string]$logFilePath = "C:\Program Files\Microsoft SQL Server\MSSQL15.SQLEXPRESS\MSSQL\DATA\",
    [string]$backupFilePath = "C:\tools\SQLSTF\tpch.zip",
    [string]$dist = "C:\Tools\SQLSTF\"
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
        [string]$admuser = "`"$(whoami)`""
    )

    try {
        Add-Content -Path (Join-Path $dist 'ConfigurationFile.ini') -Value "`r`nSQLSYSADMINACCOUNTS=$admuser"
        Start-Sleep -Seconds 2

        # Download SQL ISO
        Write-Host "Starting download SQL server iso image"
        Start-BitsTransfer -Source $IsoPath -Destination $dist
        $isoimg = Join-Path $dist 'SQLServer2019-x64-ENU-Dev.iso'
        Start-Sleep -Seconds 2
        Write-Host "Mounting ISO"
        $volume = Mount-DiskImage $isoimg -StorageType ISO -PassThru | Get-Volume
        $sql_drive = $volume.DriveLetter + ':'
        Start-Sleep -Seconds 2

        # Start SQL server installation
        Write-Host "Starting SQL server installation"
        Start-Process (Join-Path $sql_drive 'setup.exe') -ArgumentList "/ConfigurationFile=$dist\ConfigurationFile.ini" -NoNewWindow -Wait
        Write-Host "Dismounting ISO"
        Dismount-DiskImage $isoimg

        # Start Studio installation
        $setupfile = Join-Path $dist 'ssmsfullsetup.exe'
        Write-Host "Starting download of SQL SMS"
        Start-BitsTransfer -Source $ssmspath -Destination $setupfile
        Start-Sleep -Seconds 2
        Write-Host "Starting SQL SMS installation"
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
        Write-Host "Path $dataFilePath does not exist. Creating"
        New-Item -ItemType Directory -Path $dataFilePath -Force | Out-Null
    }

    if (-not (Test-Path $logFilePath)) {
        Write-Host "Path $logFilePath does not exist. Creating"
        New-Item -ItemType Directory -Path $logFilePath -Force | Out-Null
    }
    try {
        # Check if backup file path is provided for restore
        if ($backupFilePath) {
        # Extracting the backup zip file
        Write-Host "Extracting the backup archive: $backupFilePath to $dist"
        Expand-Archive -Path $backupFilePath -DestinationPath $dist -Force
        $ExtractedBackup = (Join-Path $dist 'tpch.bak')
        Write-Host $ExtractedBackup
        # SQL query to restore database from backup
        $query = "RESTORE DATABASE [$databaseName] FROM DISK = '$ExtractedBackup' WITH REPLACE, MOVE 'tpch' TO '$dataFilePath\$databaseName.mdf', MOVE 'tpch_log' TO '$logFilePath\$databaseName.ldf';"

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
            Write-Error "File  '$backupFilePath' can't ne found! Exiting"
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

function Test-SqlServerInstalled {

    $service = Get-Service -Name 'MSSQLSERVER' -ErrorAction SilentlyContinue
    if ($service -eq $null) {
        return $false
    }
    return $true
}

if (Test-SqlServerInstalled) {
    Write-Host "SQL Server is installed. Going to restore DB"
    Restore-DB
} else {
    Write-Host "SQL Server is no installed. Installing it first"
    Install-SqlServer
    if (Test-SqlServerInstalled) {
        Write-Host "Now when the SQL Server is running going to restore DB"
        Restore-DB
    }
    else {
        Write-Host "Can't detect SQL service after installation. Exiting"
        exit 1
    }
}

exit 0

