param (
    [int]$commitCount = 1,                 
    [string]$database = "full_db_1"        
)

$server = "localhost"
$user = "sa"
$password = "P@ssword"

# Build the stored procedure name based on the database
$procedureName = "UpdateCustomerBalances$database"

while ($true) {
    try {
        Invoke-Sqlcmd -ServerInstance $server `
                      -Username $user `
                      -Password $password `
                      -Database $database `
                      -Query "EXEC [dbo].[$procedureName] @commitCount = $commitCount"
    } catch {
        Write-Host "Error: $($_.Exception.Message)"
    }
}
