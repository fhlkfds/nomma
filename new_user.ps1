# Check if running as administrator
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Warning "Please run this script as Administrator!"
    Write-Warning "Script will exit in 5 seconds..."
    Start-Sleep -Seconds 5
    exit
}

# Prompt for domain credentials
$domainCreds = Get-Credential

# Function to check and install required features
function Install-RequiredFeatures {
    Write-Host "Checking and installing required features..."
    
    # Check if RSAT AD PowerShell module is installed
    $rsatAdFeature = Get-WindowsCapability -Name "Rsat.ActiveDirectory*" -Online

    if ($rsatAdFeature.State -ne "Installed") {
        Write-Host "Installing RSAT Active Directory PowerShell tools..."
        try {
            Add-WindowsCapability -Online -Name "Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0"
            Write-Host "RSAT tools installed successfully. A system restart may be required."
        } catch {
            Write-Error "Failed to install RSAT tools: $_"
            Write-Warning "Script will exit in 5 seconds..."
            Start-Sleep -Seconds 5
            exit
        }
    } else {
        Write-Host "RSAT Active Directory PowerShell tools are already installed."
    }

    # Import the AD module
    try {
        Import-Module ActiveDirectory -ErrorAction Stop
        Write-Host "ActiveDirectory PowerShell module imported successfully."
    } catch {
        Write-Error "Failed to import ActiveDirectory module: $_"
        Write-Warning "Please restart your computer if you just installed the RSAT tools."
        Write-Warning "Script will exit in 5 seconds..."
        Start-Sleep -Seconds 5
        exit
    }
}

# Run the installation check
Install-RequiredFeatures

# Get user input and capitalize first letter of each name
$firstName = Read-Host "Enter teacher's first name"
$lastName = Read-Host "Enter teacher's last name"

# Capitalize first letter and make rest lowercase
$firstName = (Get-Culture).TextInfo.ToTitleCase($firstName.ToLower())
$lastName = (Get-Culture).TextInfo.ToTitleCase($lastName.ToLower())

# Create username in format flastname (first letter + lastname)
$username = "$($firstName.Substring(0,1))$lastName"

$password = ConvertTo-SecureString "password" -AsPlainText -Force


# Display the information before creating
Write-Host "`nCreating user with the following details:"
Write-Host "Full Name: $firstName $lastName"
Write-Host "Username: $username"
Write-Host "OU Path: $ouPath`n"

# Create the user account
try {
    New-ADUser -Name "$firstName $lastName" `
               -GivenName $firstName `
               -Surname $lastName `
               -SamAccountName $username `
               -UserPrincipalName "$username@test.lan" `
               -Path $ouPath `
               -AccountPassword $password `
               -Enabled $true `
               -ChangePasswordAtLogon $true `
               -Server "test-DC2019.test.lan" `
               -Credential $domainCreds

    Write-Host "User $username created successfully in Teachers OU"
    Write-Host "Password will be: password"
} catch {
    Write-Host "Error creating user: $_"
}


