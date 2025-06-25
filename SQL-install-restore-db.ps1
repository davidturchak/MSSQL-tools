<#
.SYNOPSIS
    Automates SQL Server installation and database restoration with 2 SDP disks initialization.

.DESCRIPTION
    This script installs SQL Server if not present, initializes disks for SQL data and logs,
    and restores a specified database from a backup file. Logs are saved to a file and output to the console at the end.

.PARAMETER DatabaseName
    The name of the database to restore.

.PARAMETER BackupFilePath
    Path to the database backup file (.zip). Default: C:\tools\SQLSTF\tpch.zip

.EXAMPLE
    .\Create-SqlDatabase.ps1 -DatabaseName "MyDatabase" -BackupFilePath "C:\Backups\MyDatabase.zip"

.NOTES
    Author: David Turchak
    Date: June 25, 2025
    Version: 2.1
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory=$false)]
    [ValidateNotNullOrEmpty()]
    [string]$DatabaseName,

    [Parameter(Mandatory=$false)]
    [ValidateScript({Test-Path $_ -PathType Leaf})]
    [string]$BackupFilePath = "C:\tools\SQLSTF\tpch.zip"
)

# Global variables
$script:LogFile = Join-Path $env:TEMP "SqlSetup_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$script:DistPath = "C:\Tools\SQLSTF\"
$script:ServerInstance = $env:COMPUTERNAME

# Logging function
function Write-Log {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Message,
        [ValidateSet("INFO", "WARNING", "ERROR")]
        [string]$Level = "INFO"
    )
    $logMessage = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] $Message"
    Write-Verbose $logMessage
    Add-Content -Path $script:LogFile -Value $logMessage
}

# Help display function
function Show-Help {
    Get-Help $PSCommandPath
    exit 1
}

# SQL Server installation function
function Install-SqlServer {
    [CmdletBinding()]
    param (
        [string]$SsmsUrl = "https://aka.ms/ssmsfullsetup",
        [string]$IsoUrl = "https://download.microsoft.com/download/7/c/1/7c14e92e-bdcb-4f89-b7cf-93543e7112d1/SQLServer2019-x64-ENU-Dev.iso",
        [string]$FlexUser = "flexadm"
    )

    Write-Log "Starting SQL Server installation"
    
    try {
        # Create distribution directory if it doesn't exist
        New-Item -ItemType Directory -Path $script:DistPath -Force | Out-Null
        
        # Prepare configuration file
        $configFile = Join-Path $script:DistPath 'ConfigurationFile.ini'
        $admUser = "$($env:COMPUTERNAME)\$FlexUser"
        Add-Content -Path $configFile -Value "`r`nSQLSYSADMINACCOUNTS=$admUser" -ErrorAction Stop

        # Download and mount SQL Server ISO
        $isoPath = Join-Path $script:DistPath 'SQLServer2019-x64-ENU-Dev.iso'
        if (-not (Test-Path $isoPath)) {
            Write-Log "Downloading SQL Server ISO"
            Start-BitsTransfer -Source $IsoUrl -Destination $isoPath -ErrorAction Stop
        }

        Write-Log "Mounting ISO image"
        $volume = Mount-DiskImage $isoPath -StorageType ISO -PassThru -ErrorAction Stop | Get-Volume
        $sqlDrive = "$($volume.DriveLetter):"

        # Install SQL Server
        Write-Log "Installing SQL Server"
        Start-Process -FilePath (Join-Path $sqlDrive 'setup.exe') `
            -ArgumentList "/ConfigurationFile=$configFile /QUIET /IACCEPTSQLSERVERLICENSETERMS" `
            -NoNewWindow -Wait -ErrorAction Stop

        # Cleanup
        Dismount-DiskImage $isoPath -ErrorAction Stop

        # Install SSMS
        $ssmsPath = Join-Path $script:DistPath 'ssmsfullsetup.exe'
        if (-not (Test-Path $ssmsPath)) {
            Write-Log "Downloading SSMS"
            Start-BitsTransfer -Source $SsmsUrl -Destination $ssmsPath -ErrorAction Stop
        }

        Write-Log "Installing SSMS"
        Start-Process -FilePath $ssmsPath -ArgumentList "/install /quiet /norestart" `
            -NoNewWindow -Wait -ErrorAction Stop

        Write-Log "SQL Server installation completed successfully"
    }
    catch {
        Write-Log "Installation failed: $($_.Exception.Message)" -Level ERROR
        throw
    }
}

# Database restoration function
function Restore-Database {
    [CmdletBinding()]
    param (
        [string]$SaUser = "sa",
        [string]$SaPassword = "P@ssword",
        [string]$DataPath,
        [string]$LogPath
    )

    Write-Log "Starting database restore for '$DatabaseName'"

    try {
        $connectionString = "Server=$script:ServerInstance;Database=master;User ID=$SaUser;Password=$SaPassword;"
        
        # Create data and log directories
        foreach ($path in @($DataPath, $LogPath)) {
            if (-not (Test-Path $path)) {
                Write-Log "Creating directory: $path"
                New-Item -ItemType Directory -Path $path -Force -ErrorAction Stop | Out-Null
            }
        }

        if (Test-Path $BackupFilePath) {
            Write-Log "Extracting backup file: $BackupFilePath"
            $extractPath = Join-Path $script:DistPath ([System.IO.Path]::GetFileNameWithoutExtension($BackupFilePath))
            Expand-Archive -Path $BackupFilePath -DestinationPath $script:DistPath -Force -ErrorAction Stop

            $bakFileName = [System.IO.Path]::GetFileNameWithoutExtension($BackupFilePath) + '.bak'
            $extractedBackup = Join-Path $script:DistPath $bakFileName
            $orgDbName = [System.IO.Path]::GetFileNameWithoutExtension($BackupFilePath)
            $orgDbLog = "${orgDbName}_log"

            $restoreQuery = @"
RESTORE DATABASE [$DatabaseName] 
FROM DISK = '$extractedBackup' 
WITH REPLACE, 
MOVE '$orgDbName' TO '$DataPath\$DatabaseName.mdf', 
MOVE '$orgDbLog' TO '$LogPath\$DatabaseName.ldf';
"@

            Write-Log "Executing database restore"
            $connection = New-Object System.Data.SqlClient.SqlConnection $connectionString
            $connection.Open()
            $command = $connection.CreateCommand()
            $command.CommandText = $restoreQuery
            $command.ExecuteNonQuery() | Out-Null
            Write-Log "Database '$DatabaseName' restored successfully"
        }
        else {
            Write-Log "No backup file provided. Skipping restore" -Level WARNING
        }
    }
    catch {
        Write-Log "Restore failed: $($_.Exception.Message)" -Level ERROR
        throw
    }
    finally {
        if ($connection.State -eq 'Open') {
            $connection.Close()
            $connection.Dispose()
        }
    }
}

# SQL Server installation check function
function Test-SqlServerInstallation {
    return (Get-Service -Name 'MSSQLSERVER' -ErrorAction SilentlyContinue) -ne $null
}

# Disk initialization function
function Initialize-SilkSdpDisks {
    Write-Log "Initializing disks for SQL Server"

    try {
        $disks = Get-Disk | Where-Object {
            $_.PartitionStyle -eq 'RAW' -and $_.Size -gt 100GB
        } | Select-Object -First 2

        if ($disks.Count -lt 2) {
            Write-Log "Insufficient uninitialized disks (>100GB). Found: $($disks.Count)" -Level ERROR
            throw "Need 2 uninitialized disks >100GB"
        }

        $labels = @("${DatabaseName}_data", "${DatabaseName}_log")
        $driveLetters = @()

        foreach ($i in 0..1) {
            $disk = $disks[$i]
            Write-Log "Initializing disk $($disk.Number)"
            
            Initialize-Disk -Number $disk.Number -PartitionStyle GPT -PassThru -ErrorAction Stop | Out-Null
            $partition = New-Partition -DiskNumber $disk.Number -UseMaximumSize -AssignDriveLetter -ErrorAction Stop |
                Format-Volume -FileSystem NTFS -AllocationUnitSize 64KB -NewFileSystemLabel $labels[$i] -Force -ErrorAction Stop

            $drive = ($partition | Get-Volume).DriveLetter
            if (-not $drive) {
                Write-Log "Failed to assign drive letter for $($labels[$i])" -Level ERROR
                throw "Drive letter assignment failed"
            }
            $driveLetters += "$drive`:"
        }

        Write-Log "Assigned drives: $($driveLetters -join ', ')"
        return $driveLetters
    }
    catch {
        Write-Log "Disk initialization failed: $($_.Exception.Message)" -Level ERROR
        throw
    }
}

# Main execution
try {
    Write-Log "Script execution started"

    if (-not $PSBoundParameters.ContainsKey('DatabaseName')) {
        Show-Help
    }

    # Validate parameters
    if (-not $DatabaseName -or -not $BackupFilePath) {
        Write-Log "Missing required parameters" -Level ERROR
        throw "Both DatabaseName and BackupFilePath are required"
    }

    # Initialize disks
    $driveLetters = Initialize-SilkSdpDisks
    $dataPath = Join-Path $driveLetters[0] "${DatabaseName}_data"
    $logPath = Join-Path $driveLetters[1] "${DatabaseName}_log"
    
    Write-Log "Data path: $dataPath"
    Write-Log "Log path: $logPath"

    # Install and restore
    if (Test-SqlServerInstallation) {
        Write-Log "SQL Server already installed"
        Restore-Database -DataPath $dataPath -LogPath $logPath
    }
    else {
        Install-SqlServer
        if (Test-SqlServerInstallation) {
            Restore-Database -DataPath $dataPath -LogPath $logPath
        }
        else {
            Write-Log "SQL Server installation verification failed" -Level ERROR
            throw "SQL Server installation failed"
        }
    }

    Write-Log "Script execution completed successfully"
    exit 0
}
catch {
    Write-Log "Script execution failed: $($_.Exception.Message)" -Level ERROR
    exit 1
}
finally {
    Write-Log "Script execution ended"
    # Output log file contents to console
    if (Test-Path $script:LogFile) {
        Write-Host "`n=== Log File Contents ($($script:LogFile)) ==="
        Get-Content -Path $script:LogFile | ForEach-Object { Write-Host $_ }
        Write-Host "=== End of Log ==="
    }
    else {
        Write-Host "`nNo log file found at $($script:LogFile)"
    }
}