param (
    [string]$DatabaseName = "david"
)

# File paths
$dataFilePath = "E:\DATA\$DatabaseName.mdf"
$logFilePath = "F:\LOG\$DatabaseName.ldf"

# Specify the new owner
$newOwner = "flexadm"


function Set-AssignDriveLetter {
    param(
        [string]$DiskNumber,
        [string]$PartitionNumber,
        [string]$DriveLetter
    )

    Write-Host "Assigning drive letter $DriveLetter to Disk $DiskNumber, Partition $PartitionNumber"
    
    $scriptBlock = @"
select disk $DiskNumber
select partition $PartitionNumber
assign letter=$DriveLetter
select volume 3
attribute volume clear readonly
select volume 4
attribute volume clear readonly
"@

    Execute-DiskpartScriptBlock -ScriptBlock $scriptBlock
}

# Function to remove a drive letter using Diskpart
function Remove-DriveLetter {
    param(
        [string]$DiskNumber,
        [string]$PartitionNumber
    )

    Write-Host "Removing drive letter from Disk $DiskNumber, Partition $PartitionNumber"
    
    $scriptBlock = @"
select disk $DiskNumber
select partition $PartitionNumber
remove
"@

    Execute-DiskpartScriptBlock -ScriptBlock $scriptBlock
}

# Function to execute a Diskpart script block
function Execute-DiskpartScriptBlock {
    param(
        [string]$ScriptBlock
    )

    $scriptFilePath = [System.IO.Path]::GetTempFileName()
    $ScriptBlock | Out-File -FilePath $scriptFilePath -Encoding ascii
    $process = Start-Process diskpart -ArgumentList "/s `"$scriptFilePath`"" -PassThru -WindowStyle Hidden
    $process.WaitForExit()
}

# Function to search for *.mdf and *.ldf files and reassign drive letters accordingly
function Update-ReassignDriveLetters {
    param(
        [string]$DriveLetter,
        [string]$DiskNumber
    )

    $mdfFiles = Get-ChildItem -Path "$DriveLetter\*" -Recurse -Filter *.mdf
    if ($mdfFiles) {
        Write-Host "Found *.mdf file: $($mdfFiles[0].FullName)"
        Remove-DriveLetter -DiskNumber $DiskNumber -PartitionNumber 2
        Set-AssignDriveLetter -DiskNumber $DiskNumber -PartitionNumber 2 -DriveLetter "E"
        return
    }

    $ldfFiles = Get-ChildItem -Path "$DriveLetter\*" -Recurse -Filter *.ldf
    if ($ldfFiles) {
        Write-Host "Found *.ldf file: $($ldfFiles[0].FullName)"
        Remove-DriveLetter -DiskNumber $DiskNumber -PartitionNumber 2
        Set-AssignDriveLetter -DiskNumber $DiskNumber -PartitionNumber 2 -DriveLetter "F"
        return
    }
}

# Function to attach the database
function Set-AttachSqlDatabase {
    try {
        if ($dataFilePath) {
            # Connection string using Windows authentication
            $connectionString = "Server=$serverInstance;Database=master;Integrated Security=True;"
            # SQL query to restore database from backup
            $query = "CREATE DATABASE [$DatabaseName] ON ( FILENAME = N'$dataFilePath' ), ( FILENAME = N'$logFilePath' ) FOR ATTACH;"
            # Create SQL connection
            $connection = New-Object System.Data.SqlClient.SqlConnection
            $connection.ConnectionString = $connectionString
            $connection.Open()

            # Execute the query
            $command = $connection.CreateCommand()
            $command.CommandText = $query
            $command.ExecuteNonQuery()
            Write-Host "Database '$DatabaseName' attached successfully."
        }
    } catch {
        Write-Error "Failed to attach database '$DatabaseName': $_"
    }
}

foreach ($disk in 2, 3) {
    Get-Disk -Number $disk | Set-Disk -IsOffline $false
    Set-AssignDriveLetter -DiskNumber $disk -PartitionNumber 2 -DriveLetter "Z"
    Update-ReassignDriveLetters -DriveLetter "Z:" -DiskNumber $disk
}


if ($dataFilePath -and $logFilePath) {
    foreach ($filePath in $dataFilePath, $logFilePath) {
        # Attempt to get the current file security descriptor
        try {
            $fileSecurity = Get-Acl -Path $filePath
        }
        catch {
            Write-Error "Failed to retrieve file security descriptor for ${filePath}: $_"
            Exit 1
        }

        # Create a new System.Security.Principal.NTAccount object representing the new owner
        try {
            $ntAccount = New-Object System.Security.Principal.NTAccount($newOwner)
        }
        catch {
            Write-Error "Failed to create NTAccount for ${newOwner}: $_"
            Exit 1
        }

        # Set the owner
        try {
            $fileSecurity.SetOwner($ntAccount)
        }
        catch {
            Write-Error "Failed to set owner for ${filePath}: $_"
            Exit 1
        }

        # Create a new Access Control Entry (ACE) for granting full control to everyone
        $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule("Everyone", "FullControl", "None", "None", "Allow")

        # Add the Access Rule to the security descriptor
        $fileSecurity.AddAccessRule($accessRule)

        # Apply the modified security descriptor to the file
        try {
            Set-Acl -Path $filePath -AclObject $fileSecurity
        }
        catch {
            Write-Error "Failed to apply modified security descriptor for ${filePath}: $_"
            Exit 1
        }

        Write-Host "Successfully updated security settings for $filePath"
    }
    Set-AttachSqlDatabase
}