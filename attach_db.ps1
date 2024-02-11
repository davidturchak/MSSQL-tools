param (
    [string]$DatabaseName = "david"
)

# File paths
$filePaths = @("E:\DATA\$DatabaseName.mdf", "L:\LOG\$DatabaseName.ldf")

# Specify the new owner
$newOwner = "flexadm"

foreach ($filePath in $filePaths) {
    # Attempt to get the current file security descriptor
    try {
        $fileSecurity = Get-Acl -Path $filePath
    }
    catch {
        Write-Error "Failed to retrieve file security descriptor for ${filePath}: $_"
        Continue
    }

    # Create a new System.Security.Principal.NTAccount object representing the new owner
    try {
        $ntAccount = New-Object System.Security.Principal.NTAccount($newOwner)
    }
    catch {
        Write-Error "Failed to create NTAccount for ${newOwner}: $_"
        Continue
    }

    # Set the owner
    try {
        $fileSecurity.SetOwner($ntAccount)
    }
    catch {
        Write-Error "Failed to set owner for ${filePath}: $_"
        Continue
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
        Continue
    }

    Write-Host "Successfully updated security settings for $filePath"
}
