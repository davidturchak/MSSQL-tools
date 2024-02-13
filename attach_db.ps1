param (
    [string]$DatabaseName = "david"
)

# File paths
$dataFilePath = "E:\DATA\$DatabaseName.mdf"
$logFilePath = "F:\LOG\$DatabaseName.ldf"

# Specify the new owner
$newOwner = "flexadm"

function Update-DiskOnline {
    Get-Disk -Number 2 | Set-Disk -IsOffline $false
    Get-Disk -Number 3 | Set-Disk -IsOffline $false

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