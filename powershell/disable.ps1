# Check if running as administrator
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Warning "Please run this script as Administrator!"
    Write-Warning "Script will exit in 5 seconds..."
    Start-Sleep -Seconds 5
    exit
}

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
            $restart = Read-Host "Do you want to restart your computer now? (Y/N)"
            if ($restart -eq 'Y' -or $restart -eq 'y') {
                Restart-Computer -Force
            } else {
                Write-Warning "Please restart your computer before running this script again."
                exit
            }
        } catch {
            Write-Error "Failed to install RSAT tools: $_"
            exit
        }
    } else {
        Write-Host "RSAT Active Directory PowerShell tools are already installed."
    }
}

# Install required features
Install-RequiredFeatures

# Import AD Module
try {
    Import-Module ActiveDirectory -ErrorAction Stop
} catch {
    Write-Error "Failed to import ActiveDirectory module. Please ensure RSAT tools are installed and computer has been restarted."
    exit
}

# Test Domain Controller connectivity for test.lan
Write-Host "Testing connection to test.lan domain..."
try {
    $testDomain = Get-ADDomain -Identity "test.lan" -ErrorAction Stop
    $domainController = $testDomain.PDCEmulator
    Write-Host "Successfully connected to test.lan domain controller: $domainController" -ForegroundColor Green
} catch {
    Write-Error "Cannot connect to test.lan domain. Please check:
    1. Your machine is connected to the network
    2. Your machine is domain-joined to test.lan
    3. DNS settings are correct
    4. Domain controller is online"
    exit
}

function Disable-SingleUser {
    param (
        [string]$username
    )
    
    try {
        # Check if user exists in test.lan domain
        $user = Get-ADUser -Identity $username -Server $domainController
        
        # Show user details before disabling
        Write-Host "`nUser found:"
        Write-Host "Username: $($user.SamAccountName)"
        Write-Host "Full Name: $($user.Name)"
        Write-Host "Distinguished Name: $($user.DistinguishedName)"
        
        $confirm = Read-Host "`nDo you want to disable this account? (Y/N)"
        if ($confirm -ne 'Y' -and $confirm -ne 'y') {
            Write-Host "Skipping user: $username" -ForegroundColor Yellow
            return
        }
        
        # Disable the user account
        Disable-ADAccount -Identity $username -Server $domainController
        
        # Get current timestamp
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        
        # Add description indicating when the account was disabled
        Set-ADUser -Identity $username -Description "Account disabled on $timestamp" -Server $domainController
        
        Write-Host "Successfully disabled user: $username" -ForegroundColor Green
        
    } catch {
        Write-Host "Error processing user $username : $_" -ForegroundColor Red
    }
}

# Main script
Clear-Host
Write-Host "=== AD User Account Disable Tool for test.lan ===`n"
Write-Host "1. Disable single user"
Write-Host "2. Disable users from text file"
Write-Host "3. Exit`n"

$choice = Read-Host "Enter your choice (1-3)"

switch ($choice) {
    "1" {
        # Single user mode
        $firstName = Read-Host "Enter user's first name"
        $lastName = Read-Host "Enter user's last name"
        
        # Format to flast format
        $username = "$($firstName.Substring(0,1))$lastName".ToLower()
        
        Write-Host "`nProcessing user: $username in test.lan domain"
        Disable-SingleUser -username $username
    }
    "2" {
        # File mode
        Write-Host "`nFile should contain one username per line in 'flast' format"
        Write-Host "Example file content:"
        Write-Host "jsmith"
        Write-Host "jdoe"
        Write-Host "awhite`n"
        
        $filePath = Read-Host "Enter the path to your text file containing usernames"
        
        if (Test-Path $filePath) {
            $users = Get-Content $filePath
            
            Write-Host "`nFound $($users.Count) users in file."
            Write-Host "Domain: test.lan"
            Write-Host "Domain Controller: $domainController`n"
            
            $users | ForEach-Object {
                Write-Host "`nUsername to process: $_"
            }
            
            $confirm = Read-Host "`nDo you want to proceed with disabling these accounts? (Y/N)"
            
            if ($confirm -eq 'Y' -or $confirm -eq 'y') {
                foreach ($user in $users) {
                    Write-Host "`nProcessing user: $user"
                    Disable-SingleUser -username $user.Trim()
                }
            } else {
                Write-Host "Operation cancelled." -ForegroundColor Yellow
            }
        } else {
            Write-Host "File not found: $filePath" -ForegroundColor Red
        }
    }
    "3" {
        Write-Host "Exiting script..."
        exit
    }
    default {
        Write-Host "Invalid choice. Exiting script..." -ForegroundColor Red
        exit
    }
}

Write-Host "`nOperation completed. Check above for any errors."
Write-Host "Domain: test.lan"
Write-Host "Domain Controller: $domainController`n"


