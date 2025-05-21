param (
    [string]$databaseName,
    [string]$backupFilePath = "C:\tools\SQLSTF\tpch.zip"
)

$dist = "C:\Tools\SQLSTF\"
$serverInstance = $env:COMPUTERNAME

function Show-Help {
    Write-Host "Usage: Create-SqlDatabase.ps1 [-databaseName <DatabaseName>] [-backupFilePath <BackupFilePath>]"
    exit 1
}

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

        if (-not (Test-Path $isoimg)) {
            Start-BitsTransfer -Source $IsoPath -Destination $dist
        }

        $volume = Mount-DiskImage $isoimg -StorageType ISO -PassThru | Get-Volume
        $sql_drive = $volume.DriveLetter + ':'

        Start-Process (Join-Path $sql_drive 'setup.exe') -ArgumentList "/ConfigurationFile=$dist\ConfigurationFile.ini" -NoNewWindow -Wait
        Dismount-DiskImage $isoimg

        $setupfile = Join-Path $dist 'ssmsfullsetup.exe'
        if (-not (Test-Path $setupfile)) {
            Start-BitsTransfer -Source $ssmspath -Destination $setupfile
        }

        Start-Process $setupfile -ArgumentList "/install", "/quiet", "/norestart" -NoNewWindow -Wait
    }
    catch {
        Write-Error "Install failed: $_"
        exit 1
    }
}

function Restore-DB {
    param (
        [string]$sauser = "sa",
        [string]$sapass = "P@ssword"
    )

    $connectionString = "Server=$serverInstance;Database=master;User ID=$sauser;Password=$sapass;"

    if (-not (Test-Path $dataFilePath)) {
        Write-Host "Creating $dataFilePath"
        New-Item -ItemType Directory -Path $dataFilePath -Force | Out-Null
    }

    if (-not (Test-Path $logFilePath)) {
        Write-Host "Creating $logFilePath"
        New-Item -ItemType Directory -Path $logFilePath -Force | Out-Null
    }

    try {
        if ($backupFilePath) {
            Write-Host "Extracting $backupFilePath to $dist"
            Expand-Archive -Path $backupFilePath -DestinationPath $dist -Force
            # Get the base name of the zip file (e.g., 'tpch' from 'tpch.zip') and add '.bak'
            $OrgDBName = [System.IO.Path]::GetFileNameWithoutExtension($backupFilePath)
            $OriginalDbLog = [System.IO.Path]::GetFileNameWithoutExtension($backupFilePath) + '_log'
            $bakFileName = [System.IO.Path]::GetFileNameWithoutExtension($backupFilePath) + '.bak'
            $ExtractedBackup = Join-Path $dist $bakFileName

            $query = "RESTORE DATABASE [$databaseName] FROM DISK = '$ExtractedBackup' WITH REPLACE, MOVE '$OrgDBName' TO '$dataFilePath\$databaseName.mdf', MOVE '$OriginalDbLog' TO '$logFilePath\$databaseName.ldf';"

            $connection = New-Object System.Data.SqlClient.SqlConnection $connectionString
            $connection.Open()
            $command = $connection.CreateCommand()
            $command.CommandText = $query
            $command.ExecuteNonQuery()
            Write-Host "Database '$databaseName' restored successfully."
        }
        else {
            Write-Host "No backup file. Skipping restore."
        }
    }
    catch {
        Write-Host "Restore failed: $_.Exception.Message"
    }
    finally {
        $connection.Close()
    }
}

function Test-SqlServerInstalled {
    return (Get-Service -Name 'MSSQLSERVER' -ErrorAction SilentlyContinue) -ne $null
}

function Initialize-SilkSdpDisks {
    Write-Host "Looking for two uninitialized disks >100GB..."

    # Get uninitialized disks >100GB
    $disks = Get-Disk | Where-Object {
        $_.PartitionStyle -eq 'RAW' -and $_.Size -gt 100GB
    }

    if ($disks.Count -lt 2) {
        Write-Error "Error: Need 2 uninitialized disks >100GB. Found $($disks.Count)."
        exit 1
    }

    $selectedDisks = $disks | Select-Object -First 2
    $labels = @("SQL DATA", "SQL LOG")
    $driveLetters = @()

    for ($i = 0; $i -lt $selectedDisks.Count; $i++) {
        $disk = $selectedDisks[$i]
        Write-Host "Initializing disk $($disk.Number)..."

        Initialize-Disk -Number $disk.Number -PartitionStyle GPT -PassThru -Confirm:$false | Out-Null
        $partition = New-Partition -DiskNumber $disk.Number -UseMaximumSize -AssignDriveLetter |
                     Format-Volume -FileSystem NTFS -AllocationUnitSize 64KB -NewFileSystemLabel $labels[$i] -Force -Confirm:$false

        Start-Sleep 1
        $drive = ($partition | Get-Volume).DriveLetter
        if ($null -eq $drive) {
            Write-Error "Failed to assign drive letter for $labels[$i]."
            exit 1
        }

        $driveLetters += "$drive`:"
    }

    Write-Host "Assigned drives: $($driveLetters -join ', ')"
    return $driveLetters
}


# Main Logic
if ($PSBoundParameters.Count -gt 0) {
    if (-not $databaseName -or -not $backupFilePath) {
        Write-Error "Error: Both -databaseName and -backupFilePath are required."
        exit 1
    }

    $assignedDriveLetters = Initialize-SilkSdpDisks | Where-Object { $_ -match "^[A-Z]:" }

    if ($assignedDriveLetters.Count -lt 2) {
        Write-Error "Failed to assign 2 valid drive letters: $($assignedDriveLetters -join ', ')"
        exit 1
    }

    $dataFilePath = Join-Path "$($assignedDriveLetters[0])\" "${databaseName}_data"
    $logFilePath  = Join-Path "$($assignedDriveLetters[1])\" "${databaseName}_log"
    

    Write-Host "Data path: $dataFilePath"
    Write-Host "Log path:  $logFilePath"

    if (Test-SqlServerInstalled) {
        Restore-DB
    } else {
        Install-SqlServer
        if (Test-SqlServerInstalled) {
            Restore-DB
        } else {
            Write-Error "SQL install failed. Aborting."
            exit 1
        }
    }
}
else {
    if (Test-SqlServerInstalled) {
        Write-Host "SQL Server is already installed."
    } else {
        Install-SqlServer
    }
}
exit 0
