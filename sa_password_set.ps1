param (
    [string]$newPassword = 'P@ssword'
)

# Define the SQL Server instance name
$serverInstance = "localhost"

# Construct the connection string
$connectionString = "Server=$serverInstance;Database=master;Integrated Security=True"

# Create a connection to the SQL Server
$connection = New-Object System.Data.SqlClient.SqlConnection
$connection.ConnectionString = $connectionString

try {
    # Open the connection
    $connection.Open()

    # Create a command to change the 'sa' password
    $query = "ALTER LOGIN sa WITH PASSWORD = '$newPassword'"
    $command = $connection.CreateCommand()
    $command.CommandText = $query

    # Execute the command
    $command.ExecuteNonQuery()

    Write-Host "Password for 'sa' user changed successfully."

    # Modify authentication mode to both Windows and SQL Server Authentication
    $authModeQuery = "EXEC xp_instance_regwrite N'HKEY_LOCAL_MACHINE', N'Software\Microsoft\MSSQLServer\MSSQLServer', N'LoginMode', REG_DWORD, 2"
    $authModeCommand = $connection.CreateCommand()
    $authModeCommand.CommandText = $authModeQuery
    $authModeCommand.ExecuteNonQuery()

    Write-Host "Authentication mode changed to both Windows and SQL Server Authentication."
} catch {
    Write-Host "Error occurred: $_"
} finally {
    # Close the connection
    $connection.Close()
}
