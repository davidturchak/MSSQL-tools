# Connection
$connection = New-Object System.Data.SqlClient.SqlConnection
$connection.ConnectionString = "Server=localhost;Database=master;User ID=sa;Password=P@ssword;"
$connection.Open()

# Add to sysadmin if not already
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
Write-Host "BUILTIN\Administrators added to sysadmin (if not already)."
