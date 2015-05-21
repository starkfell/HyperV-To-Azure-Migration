#
# Cookbook Name:: Convert_VM_to_VHD
# Recipe:: default
#
# Copyright (c) 2015 Ryan Irujo, All Rights Reserved.
 
secret_key             = Chef::EncryptedDataBagItem.load_secret("http://[UBUNTU_WEB_SERVER]/encrypted_scvmm_2012R2_data_bag_secret")
scvmm_server_name      = "[SCVMM_SERVER_NAME]"
scvmm_usernames        = data_bag_item('SCVMM2012R2', 'scvmm_usernames')
scvmm_passwords        = Chef::EncryptedDataBagItem.load('SCVMM2012R2', 'scvmm_passwords', secret_key)
scvmm_console_username = scvmm_usernames['scvmm_console_username']
scvmm_console_password = scvmm_passwords['scvmm_console_password']
azure_migration_files  = "http://[UBUNTU_WEB_SERVER]/MigrateToAzure/MigrateToAzure.zip"
 
# Hyper-V VM Pre-checks
powershell_script 'Convert Hyper-V VM to VHD' do
    code <<-EOH
        # [---START---] Try-Catch Wrapper for Entire Script.
        try {
             
            # Declaring PowerShell Variables.
            $VMName        = $ENV:COMPUTERNAME 
            $VMMServerName = "#{scvmm_server_name}"
            $VMMPassword   = ConvertTo-SecureString "#{scvmm_console_password}" -AsPlainText -Force
            $VMMCreds      = New-Object System.Management.Automation.PSCredential("#{scvmm_console_username}",$VMMPassword)
             
            # Location of the Disk2VHD Conversion Tool and declaring the Network Share Drive Letter to map to the Hyper-V Host Migration Share.
            $TargetVMLocalScriptPath             = "C:\\MigrateToAzure\\MigrationFiles\\Disk2VHD"
            $HyperVHostMigrationShareDriveLetter = "V:"
             
            # Verifying that the System Center 2012 R2 Virtual Machine Manager Console Binaries are available.
            $TestPath = ([System.IO.FileInfo]("C:\\MigrateToAzure\\MigrationFiles\\VMM\\Microsoft.SystemCenter.VirtualMachineManager.dll")).Exists
 
            If($TestPath -ne $true)
                {
                    Write-Host "The VMM 2012 R2 Console Binaries are missing from $($env:COMPUTERNAME)."
                    exit 2;
                }
 
            Import-Module "C:\\MigrateToAzure\\MigrationFiles\\VMM\\Microsoft.SystemCenter.VirtualMachineManager.dll"
            Import-Module "C:\\MigrateToAzure\\MigrationFiles\\VMM\\Remoting.dll"
            Import-Module "C:\\MigrateToAzure\\MigrationFiles\\VMM\\Utils.dll"
            Import-Module "C:\\MigrateToAzure\\MigrationFiles\\VMM\\Errors.dll"
 
            Write-Host "Successfully Imported the SCVMM Modules"
             
            # Connecting to the VMM Server as a VMM Console Administrator.
            $VMMServer = Get-SCVMMServer -ComputerName $VMMServerName -Credential $VMMCreds
 
            # Retrieving the Virtual Machine that we are modifying Disk(s) on.
            $VM = Get-SCVirtualMachine -VMMServer $VMMServer -Name $VMName | Where-Object {$_.Status -ne "Missing"}
            Write-Host "$($VMName)'s current state is [$($VM.Status)]"
             
             
            # Creating the Path to the respective Hyper-V Host Migration Folder.
            $VM_Parent_HyperVHost = $VM.get_VMHost().Name.ToString()
            $HyperVHost_Migration_Folder = "\\\\" + $VM_Parent_HyperVHost + "\\VMs\\AzureMigration"
 
            Write-Host "Hyper-V Host [$($VM_Parent_HyperVHost)] Migration Folder Path: $($HyperVHost_Migration_Folder)"
             
            # Verifying that the respective Hyper-V Host Migration Folder exists.
            $TestPath = ([System.IO.Directory]::Exists("$($HyperVHost_Migration_Folder)"))
 
            If($TestPath -ne $true)
                {
                    Write-Host "The AzureMigration Folder is missing from $($VM_Parent_HyperVHost)."
                    exit 2;
                }   
             
                 
            # Checking if the Local Script Path on the VM exists.
            $Test_TargetVMLocalScriptPath = [System.IO.Directory]::Exists($TargetVMLocalScriptPath)
 
            # If the Local Script Path is found, the script continues.
            If($Test_TargetVMLocalScriptPath -eq $true) 
                {
                    Write-Host "The Local Script Path on $($ENV:COMPUTERNAME) was found - '$($TargetVMLocalScriptPath)'."
                }     
          
            # If the Local Script Path does not exist, the script exits.
            If($Test_TargetVMLocalScriptPath -eq $false) 
                {
                    Write-Host "The Local Script Path on $($ENV:COMPUTERNAME) was not found - '$($TargetVMLocalScriptPath)'."
                    Write-Host "Migration to Azure is aborting."
                    exit 2;
                }       
 
                 
            # Checking for Registry Entry REG_DWORD 'EulaAccepted' for the Disk2vhd.exe Application.
            $RegistryCurrentUser = [Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey("CurrentUser","localhost")
             
            Write-Host "Opened up Current User Registry Path on localhost"
             
            $Create_Sysinternals_SubKey = $RegistryCurrentUser.OpenSubKey("Software",$true).CreateSubKey("Sysinternals")
             
            Write-Host "Created Sysinternals Sub-key"
             
            $Create_Disk2VHD_SubKey = $RegistryCurrentUser.OpenSubKey("Software\\Sysinternals",$true).CreateSubKey("Disk2Vhd")
             
            Write-Host "Created the Disk2VHD Sub-key"
             
            $OpenRegKey = $RegistryCurrentUser.OpenSubKey("Software\\Sysinternals\\Disk2Vhd", $true)
             
            Write-Host "Opened up the Disk2VHD Sub-key"
             
            $GetEulaAcceptedValue = $OpenRegKey.GetValue("EulaAccepted")
             
            Write-Host "Checking if the EulaAccepted Value exists."
             
            # Adding the REG_DWORD 'EulaAccepted' to the Registry of the VM if it doesn't exist. Script will exit if adding the REG_DWORD fails.
            If($GetEulaAcceptedValue -eq $null) 
                {
                    Write-Host "Adding the REG_DWORD 'EulaAccepted' for the Disk2VHD.exe Application to the Registry of $($ENV:COMPUTERNAME)."
                     
                    $OpenRegKey.SetValue("EulaAccepted","1","DWord")
                     
                    If (!$?) 
                        {
                            Write-Host "There was a problem adding the new REG_DWORD 'EulaAccepted' with a Value of '1' to $($ENV:COMPUTERNAME)." 
                            Write-Host "Migration From EC2 To Azure is aborting."
                            exit 2;
                        }
                    Else
                        {
                            Write-Host "The REG_DWORD 'EulaAccepted' with a Value of '1' has been added to $($ENV:COMPUTERNAME)."
                        }
                }   
 
 
            # Creating an Empty Network Drive Instance.
            $NetworkDrive = New-Object -ComObject Wscript.Network
 
            # Mapping a Network Drive to where the VHD Files will be stored.
            $NetworkDrive.MapNetworkDrive($HyperVHostMigrationShareDriveLetter, $HyperVHost_Migration_Folder)
 
            # Starting the VHD Conversion Process of all Drives on the VM using the Disk2VHD Program.
            Write-Host "Starting the Disk to VHD Conversion process for $($ENV:COMPUTERNAME)."
 
             
            # Converting the Drive(s) on the VM to VHD and copying them to the Hyper-V Host Network Share.
            $ConvertDrives = New-Object System.Diagnostics.Process
            $ConvertDrives.StartInfo.Filename = "$($TargetVMLocalScriptPath)\\disk2vhd.exe"
            $ConvertDrives.StartInfo.Arguments = " -c * $($HyperVHostMigrationShareDriveLetter)\\$($ENV:COMPUTERNAME).vhd"
            $ConvertDrives.EnableRaisingEvents = $true
            $ConvertDrives.StartInfo.UseShellExecute = $false
            $ConvertDrives.Start()
            $ConvertDrives.WaitForExit()
             
             
            If ($ConvertDrives.ExitCode -ne "0") {
                Write-Host "The Disk to VHD Conversion Process for $($ENV:COMPUTERNAME) did not complete."
                $NetworkDrive.RemoveNetworkDrive($HyperVHostMigrationShareDriveLetter)
                exit 2;
                }
 
            If ($ConvertDrives.ExitCode -eq "0") {
                $VMConversionCompleteFile = [System.IO.File]::Create("C:\\MigrateToAzure\\HyperV_VM_to_VHD_Conversion_Complete.txt").Close()
                Write-Host "The Hyper-V VM to VHD Conversion Process for $($ENV:COMPUTERNAME) Completed Successfully at $($ConvertDrives.ExitTime)."
                $NetworkDrive.RemoveNetworkDrive($HyperVHostMigrationShareDriveLetter)
                exit 0;
                }           
                 
        # [---END---] Try-Catch Wrapper for Entire Script.
            }
        catch [System.Exception]
            {
                    echo $_.Exception
                    $NetworkDrive.RemoveNetworkDrive($HyperVHostMigrationShareDriveLetter)
                    exit 2;
            }       
        EOH
    guard_interpreter :powershell_script
    only_if {File.exists?("C:\\MigrateToAzure\\HyperV_VM_PreCheck_Complete.txt")}
    not_if {File.exists?("C:\\MigrateToAzure\\HyperV_VM_to_VHD_Conversion_Complete.txt")}
end
