param (
    [string]$databaseName,
    [string]$backupFilePath = "C:\tools\SQLSTF\tpch.zip"
)

$dist = "C:\Tools\SQLSTF\"

function Show-Help {
    Write-Host "Usage: Create-SqlDatabase.ps1 [-databaseName <DatabaseName>] [-backupFilePath <BackupFilePath>]"
    Write-Host "If no arguments provided will install SQL and SMS only"
    Write-Host "  -databaseName     : The name of the database to create or restore"
    Write-Host "  -backupFilePath   : Path to the backup file for restore (required for restore)"
    exit 1
}

$serverInstance = $env:COMPUTERNAME
function Install-SqlServer {
    param (
        [string]$ssmspath = "https://aka.ms/ssmsfullsetup",
        [string]$IsoPath = "https://download.microsoft.com/download/7/c/1/7c14e92e-bdcb-4f89-b7cf-93543e7112d1/SQLServer2019-x64-ENU-Dev.iso",
        [string]$flexuser = "flexadm",
        [string]$hostname = "`"$(hostname)`"",
        [string]$admuser = "$hostname\$flexuser"
    )


    try {
        Add-Content -Path (Join-Path $dist 'ConfigurationFile.ini') -Value "`r`nSQLSYSADMINACCOUNTS=$admuser"
        Start-Sleep -Seconds 2
        $isoimg = Join-Path $dist 'SQLServer2019-x64-ENU-Dev.iso'
        if (Test-Path $isoimg) {
            Write-Host "iso file exists. Continue"
        } else {
            Write-Host "iso file does not exist. Downloading.."
            Start-BitsTransfer -Source $IsoPath -Destination $dist
            Start-Sleep -Seconds 2
        }
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
        if (Test-Path $setupfile) {
            Write-Host "Setup SQL SMS file exist. Continue "
        } else {
            Write-Host "Setup SQL SMS file does not exist. Downloading.."
            Start-BitsTransfer -Source $ssmspath -Destination $setupfile
            Start-Sleep -Seconds 2
        }
        Write-Host "Starting SQL SMS installation"
        Start-Process $setupfile -ArgumentList "/install", "/quiet", "/norestart" -NoNewWindow -Wait
    }
    catch {
        Write-Error "An error occurred: $_"
        exit 1
    }
}

function Restore-DB {
    param (
        [string]$sauser = "sa",
        [string]$sapass = "P@ssword"
    )
    # Connection string using SQL authentication
    $connectionString = "Server=$serverInstance;Database=master;User ID=$sauser;Password=$sapass;"
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
            Write-Host "Backup file path not provided. Skipping restore."
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
    if ($null -eq $service) {
        return $false
    }
    return $true
}


function Initialize-SilkSdpDisks {
        # Define the registry key path
    $regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer"

    # Check if the Explorer key exists, if not, create it
    if (-not (Test-Path $regPath)) {
        New-Item -Path $regPath -Force | Out-Null
    }

    # Set the value of NoDriveTypeAutoRun to disable the popup
    Set-ItemProperty -Path $regPath -Name "NoDriveTypeAutoRun" -Value 0xFF

    # Get disks with FriendlyName 'SILK SDP' and size greater than 100GB
    $disksOver100GB = Get-Disk -FriendlyName 'SILK SDP' | Where-Object { $_.Size -gt (100GB) }

    # Check if exactly 2 disks are detected, exit with an error message if not
    if ($disksOver100GB.Count -ne 2) {
        Write-Error "Exactly 2 disks with FriendlyName 'SILK SDP' and size greater than 100GB are required."
        exit 1
    }

    # Define labels
    $labels = @("SQL DATA", "SQL LOG")

    # Initialize counter
    $counter = 0

    # Array to store drive letters
    $driveLetters = @()

    # Iterate through each disk
    foreach ($disk in $disksOver100GB) {
        # Check if the disk is already initialized
        
        if ($disk | Get-Partition) {
            # Clean disk if have partitions
            Clear-Disk -InputObject $disk -RemoveData -Confirm:$false
        }
        Initialize-Disk -Number $disk.Number -PartitionStyle GPT -PassThru
        # Get the disk number again to make sure it's updated after initialization
        $disk = Get-Disk -Number $disk.Number

        # Create a partition, format with NTFS 64K allocation unit size, and assign label
        $partition = New-Partition -DiskNumber $disk.Number -AssignDriveLetter -UseMaximumSize | 
        Format-Volume -FileSystem NTFS -AllocationUnitSize 64KB -NewFileSystemLabel $labels[$counter] -Force -Confirm:$false
        Start-Sleep 1
        # Increment counter
        $counter++
    }

    # Get the last two partitions created above from Win32_DiskPartition class
    $lastTwoPartitions = Get-WmiObject -Class Win32_DiskPartition | Select-Object -Last 2

    # Iterate through each partition and extract the drive letter
    foreach ($partition in $lastTwoPartitions) {
        $driveLetter = (Get-WmiObject -Query "ASSOCIATORS OF {Win32_DiskPartition.DeviceID='$($partition.DeviceID)'} WHERE AssocClass=Win32_LogicalDiskToPartition" | Select-Object -ExpandProperty DeviceID) -replace '\\.*'
        $driveLetters += $driveLetter
    }
    # Return drive letters on success
    return $driveLetters
}

# Check if any parameter is provided, if yes, make all parameters mandatory
if ($PSBoundParameters.Count -gt 0) {
    if (-not $databaseName -or -not $backupFilePath) {
        Write-Host "Error: If any parameter is provided, both -databaseName and -backupFilePath are mandatory."
        exit 1
    }
    $dataFilePath = "E:\DATA\"
    $logFilePath = "F:\LOG\"
    if (Test-Path $dataFilePath) {
        Write-Host "$dataFilePath Folder exists."
    } else {
        Write-Host "$dataFilePath Folder does not exist. Creating"
        $assignedDriveLetters = Initialize-SilkSdpDisks
        #$dataFilePath = "{0}\DATA\" -f $assignedDriveLetters[2].ToString()
        #$logFilePath = "{0}\LOG\" -f $assignedDriveLetters[3].ToString()
        Write-Host $dataFilePath $logFilePath
    }

    if (Test-SqlServerInstalled) {
        Write-Host "SQL Server is installed."
        Restore-DB
    } else {
        Write-Host "SQL Server is not installed. Installing it first"
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

}
else {
    if (Test-SqlServerInstalled) {
        Write-Host "SQL Server is installed and running"

    }
    else {
        Write-Host "SQL Server is not installed. Installing..."
        Install-SqlServer
    }
}
exit 0