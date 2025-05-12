# Log file path
$logFile = "C:\Temp\sql_connection_log.txt"

# Log helper function
function Log {
    param (
        [string]$message
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $message" | Out-File -Append -FilePath $logFile
}

# Connection string
$connectionString = "Server=localhost;Database=master;User ID=sa;Password=P@ssword;"

# Attempt connection with retries
$maxRetries = 3
$retryDelaySeconds = 5
$connected = $false

for ($i = 1; $i -le $maxRetries; $i++) {
    try {
        Log ("Attempt ${i}: Trying to connect to SQL Server...")
        $connection = New-Object System.Data.SqlClient.SqlConnection
        $connection.ConnectionString = $connectionString
        $connection.Open()
        Log "Connection successful."
        $connected = $true
        break
    } catch {
        Log ("Connection failed on attempt ${i}. Error: $_")
        if ($i -lt $maxRetries) {
            Start-Sleep -Seconds $retryDelaySeconds
        }
    }
}

if (-not $connected) {
    Log "All $maxRetries connection attempts failed. Exiting script."
    Write-Host "Failed to connect after $maxRetries attempts."
    exit 1
}

# SQL to add BUILTIN\Administrators to sysadmin if not already
$sql = @"
IF NOT EXISTS (
    SELECT * FROM sys.syslogins WHERE name = N'BUILTIN\Administrators' AND sysadmin = 1
)
BEGIN
    EXEC sp_addsrvrolemember @loginame = N'BUILTIN\Administrators', @rolename = N'sysadmin';
END
"@

$command = $connection.CreateCommand()
$command.CommandText = $sql
$command.ExecuteNonQuery()

$connection.Close()
Log "BUILTIN\Administrators added to sysadmin (if not already)."
Write-Host "BUILTIN\Administrators added to sysadmin (if not already)."
