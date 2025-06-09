# Define DSN parameters
$DSNName = "noSSLTest"
$DriverName = "SQL Server"
$Server = "localhost"
$UID = "sa"
$SUPWD = "P@ssword"

# Registry paths (64-bit ODBC)
$regPath = "HKLM:\SOFTWARE\ODBC\ODBC.INI\$DSNName"
$odbcDataSourcesPath = "HKLM:\SOFTWARE\ODBC\ODBC.INI\ODBC Data Sources"

# Create the DSN registry key
New-Item -Path $regPath -Force | Out-Null

# Set required DSN properties
Set-ItemProperty -Path $regPath -Name "Server" -Value $Server
Set-ItemProperty -Path $regPath -Name "Database" -Value ""
Set-ItemProperty -Path $regPath -Name "LastUser" -Value $UID
Set-ItemProperty -Path $regPath -Name "Trusted_Connection" -Value "No"
Set-ItemProperty -Path $regPath -Name "UID" -Value $UID
Set-ItemProperty -Path $regPath -Name "PWD" -Value $SUPWD
Set-ItemProperty -Path $regPath -Name "Driver" -Value "C:\Windows\System32\SQLSRV32.dll"

# Register the DSN under the list of ODBC Data Sources
New-Item -Path $odbcDataSourcesPath -Force | Out-Null
Set-ItemProperty -Path $odbcDataSourcesPath -Name $DSNName -Value $DriverName

Write-Host "64-bit System DSN '$DSNName' created successfully using driver '$DriverName'."