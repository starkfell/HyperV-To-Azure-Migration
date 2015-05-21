#
# Cookbook Name:: HyperV_VM_PreChecks
# Recipe:: default
#
# Copyright (c) 2015 The Authors, All Rights Reserved.
 
# Chef Variables
secret_key             = Chef::EncryptedDataBagItem.load_secret("http://[UBUNTU_WEB_SERVER]/encrypted_scvmm_2012R2_data_bag_secret")
scvmm_server_name      = "[SCVMM_SERVER_NAME]"
scvmm_usernames        = data_bag_item('SCVMM2012R2', 'scvmm_usernames')
scvmm_passwords        = Chef::EncryptedDataBagItem.load('SCVMM2012R2', 'scvmm_passwords', secret_key)
scvmm_console_username = scvmm_usernames['scvmm_console_username']
scvmm_console_password = scvmm_passwords['scvmm_console_password']
azure_migration_files  = "http://[UBUNTU_WEB_SERVER]/MigrateToAzure/MigrateToAzure.zip"
 
# Hyper-V VM Pre-checks
powershell_script 'Run Hyper-V VM Pre-checks' do
    code <<-EOH
        # [---START---] Try-Catch Wrapper for Entire Script.
        try {
 
            # Declaring PowerShell Variables.
            $VMName        = $ENV:COMPUTERNAME
            $VMMServerName = "#{scvmm_server_name}"
            $VMMPassword   = ConvertTo-SecureString "#{scvmm_console_password}" -AsPlainText -Force
            $VMMCreds      = New-Object System.Management.Automation.PSCredential("#{scvmm_console_username}",$VMMPassword)
 
            # Verifying that there is a Migration Text File for the VM being migrated to Azure.
            $TestFile = ([System.IO.FileInfo]("C:\\$($VMName).txt")).Exists
 
            If($TestFile -ne $true)
                {
                    Write-Host "The Migration Text File for $($VMName) is missing."
                    exit 0
                }
            Write-Host "Found the Migration Text File for $($VMName)."                 
 
            # Reading the Migration Text File of the VM being migrated to Azure.
            $ReadFile = [System.IO.File]::ReadAllText("C:\\$($VMName).txt")
 
            If ($ReadFile -match "MigrateToAzure")
                {
                    Write-Host "Marking the Migration File as [AzureMigrationInProgress] for $($VMName). Continuing with Migration Pre-Checks."
                    $UpdateMigrationFile = [System.IO.StreamWriter] "C:\\$($VMName).txt"
                    $UpdateMigrationFile.WriteLine("AzureMigrationInProgress")
                    $UpdateMigrationFile.Close()
                }
 
            If ($ReadFile -match "AzureMigrationInProgress")
                {
                    Write-Host "Migration File is currently marked as [AzureMigrationInProgress] for $($VMName). Skipping Checks."
                    exit 0
                }
 
            If ($ReadFile -match "AzureMigrationComplete")
                {
                    Write-Host "Migration File is currently marked as [AzureMigrationComplete] for $($VMName). Skipping Checks."
                    exit 0
                }
 
            If (!$ReadFile)
                {
                    Write-Host "The Migration File entry for $($VMName) is currently empty. Exiting."
                    exit 0
                }
 
            # Source and Destination of the where the Migration Files are being downloaded from and copied to.
            $MigrationFilesShare = "#{azure_migration_files}"
            $MigrationFilesDest  = "C:\\MigrateToAzure.zip"
 
            # Downloading the Migration Files from the Network Share (website))
            Invoke-WebRequest $MigrationFilesShare -OutFile $MigrationFilesDest -EA SilentlyContinue -EV DownloadFailed
 
            If ($DownloadFailed)
                {
                    Write-Host "There was a problem downloading the Migration Files - $($MigrationFilesZipped)."
                    Write-Host $DownloadFailed
                    exit 2
                }
 
            Write-Host "Successfully Downloaded the Migration Files to C:\ on $($VMName)"
 
            # Unzipping the MigrationFiles.zip File and Copying them to 'C:\'
            $AppShell    = New-Object -ComObject shell.application
            $ZippedFiles = $AppShell.NameSpace("C:\\MigrateToAzure.zip")
 
            ForEach($Item in $ZippedFiles.items())
                {
                    $AppShell.Namespace("C:\\").copyhere($Item)
                }           
 
            Write-Host "Successfully Extracted All Migration Files on $($VMName)"
 
            # Verifying that the System Center 2012 R2 Virtual Machine Manager Console Binaries are now available.
            $TestPath = ([System.IO.FileInfo]("C:\\MigrateToAzure\\MigrationFiles\\VMM\\Microsoft.SystemCenter.VirtualMachineManager.dll")).Exists
 
            If($TestPath -ne $true)
                {
                    Write-Host "The VMM 2012 R2 Console Binaries are missing from $($ENV:COMPUTERNAME)."
                    exit 2;
                }
 
                Import-Module "C:\\MigrateToAzure\\MigrationFiles\\VMM\\Microsoft.SystemCenter.VirtualMachineManager.dll"
                Import-Module "C:\\MigrateToAzure\\MigrationFiles\\VMM\\Remoting.dll"
                Import-Module "C:\\MigrateToAzure\\MigrationFiles\\VMM\\Utils.dll"
                Import-Module "C:\\MigrateToAzure\\MigrationFiles\\VMM\\Errors.dll"
 
            Write-Host "Successfully Imported the SCVMM Modules"
 
            # Connecting to the VMM Server as a VMM Console Administrator.
            $VMMServer = Get-SCVMMServer -ComputerName $VMMServerName -Credential $VMMCreds -EA SilentlyContinue -EV ConnectToVMMError
 
            If ($ConnectToVMMError -ne $null)
                {
                    Write-Host "There was a problem connecting to the VMM Server - $($VMMServer). The Migration To Azure is aborting."
                    Write-Host $ConnectToVMMError
                    exit 2;
                }
 
            Write-Host "Successfully Connect to VMM Server - $($VMMServerName)"
 
            # Retrieving the Virtual Machine that we are performing the PreChecks on.
            $VM = Get-SCVirtualMachine -VMMServer $VMMServer -Name $VMName | Where-Object {$_.Status -ne "Missing"} -EA SilentlyContinue -EV GetVMError
 
            If ($GetVMError -ne $null)
                {
                    Write-Host "There was a problem retrieving the VM $($VMName) from VMM Server $($VMMServer). The Migration To Azure is aborting."
                    Write-Host $GetVMError
                    exit 2;
                }
 
            Write-Host "Successfully Retrieved ($VMName)'s Information from VMM"
 
            # Refreshing the Virtual Machine in VMM to account for any last minute changes.
            Read-SCVirtualMachine $VM -JobVariable RefreshVM | Out-Null
 
            If ($RefreshVM.StatusString -ne "Completed")
                {
                    Write-Host "The Properties for $($VMName) were unable to be refreshed in VMM."
                }
            Else
                {
                    Write-Host "The Properties for $($VMName) were Successfully refreshed in VMM."
                }
 
            # Retrieving Network Adapter Information on the VM.
            $VMNetworkAdapterInfo = $VM.VirtualNetworkAdapters | FL SlotId,ID,Name,DeviceID,LogicalNetwork,VMNetwork,Description
 
            # Retrieving the number of current Network Adapters on the VM.
            $VMNetworkAdapterCount = $VM.VirtualNetworkAdapters.Count
 
            If ($VMNetworkAdapterCount -eq "0")
                {
                    Write-Host "The $($VMName) must be assigned at least one network adapter before being Migrated to Azure. The Migration To Azure is aborting."
                    exit 2
                }
 
            If ($VMNetworkAdapterCount -gt "1")
                {
                    Write-Host "The $($VMName) cannot be Migrated to Azure while it has more than one network adapter. The Migration To Azure is aborting."
                    Write-Host "Additional Information about the Network Adapters is below:"
                    echo $VMNetworkAdapterInfo
                    exit 2
                }
 
            If ($VMNetworkAdapterCount -eq "1")
                {
                    Write-Host "The $($VMName) currently has one network adapter."
                }       
 
            # Opening up the Registry on the VM.
            $OpenRemoteRegistry = [Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey('LocalMachine',$VMName)
 
            # Checking to see if RDP is enabled on the VM.
            $RDPRegKeyPath = $OpenRemoteRegistry.OpenSubKey("SYSTEM\\CurrentControlSet\\Control\\Terminal Server")
            $RDPAccess = $RDPRegKeyPath.GetValue("fDenyTSConnections")
 
            If ($RDPAccess -eq "0")
                {
                    Write-Host "RDP Access is enabled on $($VMName)."
                }
 
            If ($RDPAccess -ne "0")
                {
                    Write-Host "RDP Access is not enabled on $($VMName). The Migration To Azure is aborting."
                    $OpenRemoteRegistry.Close()
                    exit 2
                }
 
            # Checking Which Port Number RDP is Listening on.
            $RDPPortRegKeyPath = $OpenRemoteRegistry.OpenSubKey("SYSTEM\\CurrentControlSet\\Control\\Terminal Server\\WinStations\\RDP-Tcp")
            $RDPPort = $RDPPortRegKeyPath.GetValue("PortNumber")
            $OpenRemoteRegistry.Close()
 
            Write-Host "$($VMName) is listening on Port $($RDPPort) for RDP Access."
 
            # All Pre-Checks Completed, Script exits after Closing the Network Drives.
            $PreCheckCompleteFile = [System.IO.File]::Create("C:\\MigrateToAzure\\HyperV_VM_PreCheck_Complete.txt").Close()
 
            Write-Host "The Hyper-V VM Pre-check Process for $($VMName) completed Successfully."
            exit 0
 
        # [---END---] Try-Catch Wrapper for Entire Script.
            }
        catch [System.Exception]
            {
                    echo $_.Exception
                    exit 2;
            }
        EOH
    guard_interpreter :powershell_script
    not_if {File.exists?("C:\\MigrateToAzure\\HyperV_VM_PreCheck_Complete.txt")}
end
