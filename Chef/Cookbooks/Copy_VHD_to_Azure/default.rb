#
# Cookbook Name:: Copy_VHD_to_Azure
# Recipe:: default
#
# Copyright (c) 2015 Ryan Irujo, All Rights Reserved.

# Chef Variables
secret_key                       = Chef::EncryptedDataBagItem.load_secret("http://lxubuchefwfs122.scom.local/Chef/SecretKeys/encrypted_scvmm_2012R2_data_bag_secret")
scvmm_server_name                = "SCVMM175.scom.local"
scvmm_usernames                  = data_bag_item('SCVMM2012R2', 'scvmm_usernames')
scvmm_passwords                  = Chef::EncryptedDataBagItem.load('SCVMM2012R2', 'scvmm_passwords', secret_key)
scvmm_console_username           = scvmm_usernames['scvmm_console_username']
scvmm_console_password           = scvmm_passwords['scvmm_console_password']
azure_migration_files            = "http://lxubuchefwfs122.scom.local/MigrateToAzure/MigrateToAzure.zip"
azure_storage_account            = data_bag_item('Azure','azure_storage_accounts')['infrontdemoeu']
azure_publishsettings_filename   = data_bag_item('Azure','azure_publishsettings_filenames')['publishsettings_filename_eu']


# Hyper-V VM Pre-checks
powershell_script 'Copy VHD to Azure' do
	code <<-EOH
		# [---START---] Try-Catch Wrapper for Entire Script.
		try {
		
			# Declaring PowerShell Variables.
			$VMName              = $ENV:COMPUTERNAME	
			$VMMServerName       = "#{scvmm_server_name}"
			$VMMPassword         = ConvertTo-SecureString "#{scvmm_console_password}" -AsPlainText -Force
			$VMMCreds            = New-Object System.Management.Automation.PSCredential("#{scvmm_console_username}",$VMMPassword)
			$AzureStorageAccount = "#{azure_storage_account}"
			$PublishSettingsFile = "#{azure_publishsettings_filename}"
			$NetworkDriveLetter  = "V:"
			
			
			# Verifying that the System Center 2012 R2 Virtual Machine Manager (CU6) Console Binaries are available.
			$TestPath = ([System.IO.FileInfo]("C:\\MigrateToAzure\\MigrationFiles\\VMM\\Microsoft.SystemCenter.VirtualMachineManager.dll")).Exists

			If($TestPath -ne $true)
				{
					Write-Host "The VMM 2012 R2 Console Binaries are missing from $($env:COMPUTERNAME)."
					exit 2
				}

			# Importing the System Center 2012 R2 Virtual Machine Manager (CU6) DLL Files.
			Import-Module "C:\\MigrateToAzure\\MigrationFiles\\VMM\\Microsoft.SystemCenter.VirtualMachineManager.dll"
			Import-Module "C:\\MigrateToAzure\\MigrationFiles\\VMM\\Remoting.dll"
			Import-Module "C:\\MigrateToAzure\\MigrationFiles\\VMM\\Utils.dll"
			Import-Module "C:\\MigrateToAzure\\MigrationFiles\\VMM\\Errors.dll"

		  
			# Verifying that the Windows Azure PowerShell SDK is installed by locating the Microsoft.WindowsAzure.Commands.dll file.
			$TestPath = ([System.IO.FileInfo]("C:\\MigrateToAzure\\MigrationFiles\\AzureSDK\\Azure\\PowerShell\\ServiceManagement\\Azure\\Services\\Microsoft.WindowsAzure.Commands.dll")).Exists
			If($TestPath -ne $true) 
				{
					Write-Host "The Windows Azure PowerShell SDK Files are missing from $($env:COMPUTERNAME) and must be available before the Migration can continue."
					exit 2
				}

			# Importing the Windows Azure PowerShell DLL Files.
			Import-Module "C:\\MigrateToAzure\\MigrationFiles\\AzureSDK\\Azure\\PowerShell\\ServiceManagement\\Azure\\Azure.psd1"

			
			# Setting the Working Directory where Azure Configuration and Subscription Files are located and verifying it exists.
			$WorkingDir = "C:\\MigrateToAzure\\MigrationFiles\\AzureCreds"
			$TestPath = ([System.IO.DirectoryInfo]($WorkingDir)).Exists
			
			If($TestPath -ne $true)
				{
					Write-Host "The $($WorkingDir) Path is missing on $($env:COMPUTERNAME) and must be created before $($VMName) can be copied to Azure."
					exit 2;
				}	
			Write-Host "Current Location of the Azure Configuration and Subscription Files: $($WorkingDir)"


			# Setting the location of the Azure '.publishsettings' File and verifying it exists.
			$MyPublishedSettingsFile = $WorkingDir + "\\" + $PublishSettingsFile
			$TestPath = ([System.IO.FileInfo]($MyPublishedSettingsFile)).Exists
			
			If($TestPath -ne $true) 
				{
					Write-Host "You must download your Azure .publishsettings File using Get-AzurePublishSettingsFile, and copy it to the $($WorkingDir) Folder."
					exit 2;
				}
			Write-Host "Current Location of the Azure .publishsettings File: $($MyPublishedSettingsFile)"
			
			
			# Importing the Azure Publish Settings from the '.publishsettings' File and retrieving the Azure Subscription Name and ID.
			$AzurePublishSettings = Import-AzurePublishSettingsFile $MyPublishedSettingsFile
			$SubscriptionName     = $AzurePublishSettings.Name
			$SubscriptionID       = $AzurePublishSettings.Id.ToString()
			
			# Explicitly choosing the Azure Subscription to Use.
			$SelectASzureSubscription = Select-AzureSubscription -SubscriptionName "Visual Studio Ultimate with MSDN"
			
			# Setting the Azure Subscription based upon the Subscription Name and Storage Account.
			Set-AzureSubscription -SubscriptionName $SubscriptionName -CurrentStorageAccount $AzureStorageAccount

			Write-Host "Successfully set The Azure Subscription - $($SubscriptionName)"
			Write-Host "Successfully set The Azure Storage Account - $($AzureStorageAccount)"

			# Retrieving the Virtual Machine that we are Migrating to Azure.
			$VM = Get-SCVirtualMachine -VMMServer $VMMServerName -Name $VMName | Where-Object {$_.Status -ne "Missing"}
			Write-Host "$($VMName)'s current state is [$($VM.Status)]"
			
			# Creating the Path to the respective Hyper-V Host Azure Migration Folder.
			$VM_Parent_HyperVHost = $VM.get_VMHost().Name.ToString()
			$HyperVHost_Migration_Folder = "\\\\" + $VM_Parent_HyperVHost + "\\VMs\\AzureMigration"

			# Verifying that the respective Hyper-V Host Azure Migration Folder exists.
			$TestPath = ([System.IO.Directory]::Exists("$($HyperVHost_Migration_Folder)"))

			If($TestPath -ne $true)
				{
					Write-Host "The AzureMigration Folder is missing from $($VM_Parent_HyperVHost)."
					exit 2;
				}		
			
			Write-Host "AzureMigration Folder Path: $($HyperVHost_Migration_Folder)"
			
			# Creating an Empty Network Drive Instance.
			$NetworkDrive = New-Object -ComObject Wscript.Network

			# Mapping a Network Drive to where the VHD Files will be stored.
			$NetworkDrive.MapNetworkDrive($NetworkDriveLetter, $HyperVHost_Migration_Folder)

			# Network location of the converted VHD File of the VM that is being Migrated to Azure.
			$VHDNetworkPath = "$($NetworkDriveLetter)\\$($VMName).vhd"
					
			Write-Host "Network Share Path for VHD: $($VHDNetworkPath)"			
			
					
			# Verifying that the VHD File of the VM is in the Hyper-V Host Migration Folder.
			$TestFile = ([System.IO.File]::Exists("$($VHDNetworkPath)"))

			If($TestFile -ne $true)
				{
					Write-Host "The $($VMName).vhd File from the VHDX to VHD Conversion is missing from $($VM_Parent_HyperVHost)."
					$NetworkDrive.RemoveNetworkDrive($NetworkDriveLetter)
					exit 2;
				}
			
			Write-Host "Verified the existence of the $($VMName).vhd File from the VHDX to VHD Conversion on $($VM_Parent_HyperVHost)."


			# Storage Container Path where VHD Disks are being stored in Azure.
			$StorageContainer = "https://" + $AzureStorageAccount + ".blob.core.windows.net/vhds/"

			Write-Host "Azure Storage Container: $($StorageContainer)."
			
			# Creating the Remote VHD Filename by using the Name of the VHD File in the LocalVHDPath variable.
			$RemoteVHDFileName = (Split-Path $VHDNetworkPath -Leaf)

			Write-Host "Remote VHD File Name: $($RemoteVHDFileName)."
			
			# Creating the Final Destination of the VHD File by combining the Storage Container Path with the Remote VHD Filename.
			$RemoteVHDPath = $StorageContainer + $RemoteVHDFileName

			Write-Host "Remote VHD Path: $($RemoteVHDPath)."	
			Write-Host "Attempting to Upload the VHD for $($VMName) to Azure."
			
			# Uploading VHD Disk(s) to Azure
			Add-AzureVhd -LocalFilePath $VHDNetworkPath -Destination $RemoteVHDPath -NumberOfUploaderThreads 5 -OverWrite -EA SilentlyContinue -EV VHDUploadFailed
			
			if ($VHDUploadFailed)
				{
					Write-Host "There was a problem uploading the VHD for $($VMName) to Azure."
					Write-Host $VHDUploadFailed
					$NetworkDrive.RemoveNetworkDrive($NetworkDriveLetter)
					exit 2
				}

			Write-Host "Successfully Uploaded the VHD for $($VMName) to Azure."


			# Registering Disk in Azure as an OS or Data Disk based upon the Name of the VHD.
			if ($RemoteVHDFileName -match ".Data(.*)") 
				{
					Add-AzureDisk -DiskName $RemoteVHDFileName -MediaLocation $RemoteVHDPath -Label $RemoteVHDFileName
					Write-Host "$($RemoteVHDFileName) was Successfully Registered as a Data Disk in Azure."
				}
					
			if ($RemoteVHDFileName -match "^CHEF(.*)") 
				{
					Add-AzureDisk -DiskName $RemoteVHDFileName -MediaLocation $RemoteVHDPath -Label $RemoteVHDFileName -OS "Windows"
					Write-Host "$($RemoteVHDFileName) was Successfully Registered as a Windows OS Disk in Azure."
				}

			Write-Host "$($VMName) has been Successfully copied to Azure."
			$NetworkDrive.RemoveNetworkDrive($NetworkDriveLetter)
			exit 0
		# [---END---] Try-Catch Wrapper for Entire Script.
			}
		catch [System.Exception]
			{
				echo $_.Exception
				$NetworkDrive.RemoveNetworkDrive($NetworkDriveLetter)
				exit 2
			}		
		EOH
	guard_interpreter :powershell_script
	only_if {File.exists?("C:\\MigrateToAzure\\HyperV_VM_to_VHD_Conversion_Complete.txt")}
	not_if {File.exists?("C:\\MigrateToAzure\\Copy_VHD_to_Azure_Complete.txt")}
end
