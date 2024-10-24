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
            Write-Warning "Script will exit in 5 seconds..."
            Start-Sleep -Seconds 5
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
$domainController = "DC=test,DC=lan"
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

function Reset-UserPassword {
    param (
        [string]$searchTerm
    )
    
    try {
        # Search for users matching the search term in test.lan domain
        $users = Get-ADUser -Filter {(SamAccountName -like $searchTerm) -or (Name -like $searchTerm) -or (UserPrincipalName -like $searchTerm)} `
                           -Properties Name, SamAccountName, UserPrincipalName, Enabled `
                           -Server $domainController

        if ($users -eq $null) {
            Write-Host "No users found matching '$searchTerm' in test.lan domain" -ForegroundColor Yellow
            return
        }

        # If multiple users found, display them and let admin choose
        if (@($users).Count -gt 1) {
            Write-Host "`nMultiple users found in test.lan:`n" -ForegroundColor Yellow
            $index = 1
            $users | ForEach-Object {
                Write-Host "$index. Username: $($_.SamAccountName)"
                Write-Host "   Full Name: $($_.Name)"
                Write-Host "   Email: $($_.UserPrincipalName)"
                Write-Host "   Status: $(if ($_.Enabled) {'Enabled'} else {'Disabled'})`n"
                $index++
            }

            $selection = Read-Host "Enter the number of the user to reset password (1-$(@($users).Count)) or 'C' to cancel"
            if ($selection -eq 'C' -or $selection -eq 'c') {
                Write-Host "Operation cancelled." -ForegroundColor Yellow
                return
            }

            $selectedUser = $users[$selection - 1]
        } else {
            $selectedUser = $users
            Write-Host "`nFound user in test.lan:"
            Write-Host "Username: $($selectedUser.SamAccountName)"
            Write-Host "Full Name: $($selectedUser.Name)"
            Write-Host "Email: $($selectedUser.UserPrincipalName)"
            Write-Host "Status: $(if ($selectedUser.Enabled) {'Enabled'} else {'Disabled'})`n"

            $confirm = Read-Host "Is this the correct user? (Y/N)"
            if ($confirm -ne 'Y' -and $confirm -ne 'y') {
                Write-Host "Operation cancelled." -ForegroundColor Yellow
                return
            }
        }

        # Reset the password
        $newPassword = ConvertTo-SecureString "Password@1" -AsPlainText -Force
        Set-ADAccountPassword -Identity $selectedUser.SamAccountName -NewPassword $newPassword -Reset -Server $domainController
        Set-ADUser -Identity $selectedUser.SamAccountName -ChangePasswordAtLogon $true -Server $domainController

        # Get current timestamp
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        
        # Update description to include password reset timestamp
        Set-ADUser -Identity $selectedUser.SamAccountName -Description "Password reset on $timestamp" -Server $domainController

        Write-Host "`nPassword successfully reset for user: $($selectedUser.SamAccountName)" -ForegroundColor Green
        Write-Host "Domain: test.lan"
        Write-Host "New password is: Password@1"
        Write-Host "User will be required to change password at next logon" -ForegroundColor Yellow

    } catch {
        Write-Host "Error: $_" -ForegroundColor Red
    }
}

# Main script
Clear-Host
Write-Host "=== AD User Password Reset Tool for test.lan ===`n"
Write-Host "You can search by:"
Write-Host "- Username (e.g., jsmith)"
Write-Host "- Full name (e.g., John Smith)"
Write-Host "- Email address"
Write-Host "You can also use wildcards (e.g., j* or *smith)`n"

$searchTerm = Read-Host "Enter search term"
Reset-UserPassword -searchTerm "*$searchTerm*"


