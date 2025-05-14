# Log file path
$logFile = "C:\Temp\sql_connection_log.txt"

# Log helper function
function Log {
    param ([string]$message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $message" | Out-File -Append -FilePath $logFile
}

# Wait for SQL Server service to be running
function Wait-ForSqlService {
    param (
        [string]$serviceName = "MSSQLSERVER",
        [int]$timeoutSeconds = 60
    )

    $startTime = Get-Date
    while ((Get-Date) -lt $startTime.AddSeconds($timeoutSeconds)) {
        $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
        if ($service -and $service.Status -eq 'Running') {
            Log "SQL Server service '$serviceName' is running."
            return $true
        }
        Log "Waiting for SQL Server service '$serviceName' to start..."
        Start-Sleep -Seconds 5
    }

    Log "Timeout waiting for SQL Server service '$serviceName'."
    return $false
}

# Wait for SQL Server readiness event in event log
function Wait-ForSqlReadyEventLog {
    param (
        [string]$instance = "MSSQLSERVER",
        [int]$timeoutSeconds = 60
    )

    $startTime = Get-Date
    while ((Get-Date) -lt $startTime.AddSeconds($timeoutSeconds)) {
        $event = Get-WinEvent -LogName "Application" -MaxEvents 1000 |
            Where-Object {
                $_.ProviderName -eq $instance -and
                $_.Message -like "*SQL Server is now ready for client connections*"
            }

        if ($event) {
            Log "SQL Server readiness event detected."
            return $true
        }

        Log "Waiting for SQL Server 'ready for client connections' event..."
        Start-Sleep -Seconds 5
    }

    Log "Timeout waiting for SQL Server readiness event."
    return $false
}

# Main logic wrapped in a function
function Main {
    $connectionString = "Server=localhost;Database=master;User ID=sa;Password=P@ssword;"
    $maxRetries = 30
    $retryDelaySeconds = 3
    $connected = $false

    # Step 1: Wait for SQL Server service
    if (-not (Wait-ForSqlService -serviceName "MSSQLSERVER" -timeoutSeconds 60)) {
        Log "SQL Server service not running. Exiting script."
        exit 1
    }

    # Step 2: Wait for SQL Server to be ready (event log)
    if (-not (Wait-ForSqlReadyEventLog -instance "MSSQLSERVER" -timeoutSeconds 60)) {
        Log "SQL Server not ready for connections (event log). Exiting script."
        exit 1
    }

    # Step 3: Attempt to connect with retry
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
            Log ("Connection failed on attempt $i. Error: $_")
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

    # Step 4: Ensure BUILTIN\Administrators is sysadmin
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
}

# Run main logic
Main
exit $LASTEXITCODE
