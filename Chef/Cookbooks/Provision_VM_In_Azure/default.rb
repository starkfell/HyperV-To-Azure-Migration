#
# Cookbook Name:: Provision_VM_In_Azure
# Recipe:: default
#
# Copyright (c) 2015 Ryan Irujo, All Rights Reserved.

# Chef Variables
azure_storage_account            = data_bag_item('Azure','azure_storage_accounts')['[AZURE_STORAGE_ACCOUNT_NAME]']
azure_publishsettings_filename   = data_bag_item('Azure','azure_publishsettings_filenames')['[PUBLISHSETTINGS_FILENAME]']
azure_subscription_name          = data_bag_item('Azure','azure_subscriptions')['[AZURE_SUBSCRIPTION_NAME]']
azure_vnet_name                  = data_bag_item('Azure','azure_vnet_names')['[AZURE_VNET_NAME]']
azure_vm_instance_size           = data_bag_item('Azure','azure_vm_instance_sizes')['Small']
azure_service_name               = data_bag_item('Azure','azure_service_names')['[AZURE_SERVICE_NAME]']

# Hyper-V VM Pre-checks
powershell_script 'Provision VM In Azure' do
	code <<-EOH
		# [---START---] Try-Catch Wrapper for Entire Script.
		try {
		
			# Declaring PowerShell Variables.
			$VMName                = $ENV:COMPUTERNAME
			$VNetName              = "#{azure_vnet_name}"
			$VMSize                = "#{azure_vm_instance_size}"
			$ServiceName           = "#{azure_service_name}"
			$AzureStorageAccount   = "#{azure_storage_account}"
			$AzureSubscriptionName = "#{azure_subscription_name}"
			$PublishSettingsFile   = "#{azure_publishsettings_filename}"
			

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
			$SelectASzureSubscription = Select-AzureSubscription -SubscriptionName $AzureSubscriptionName
			
			# Setting the Azure Subscription based upon the Subscription Name and Storage Account.
			Set-AzureSubscription -SubscriptionName $SubscriptionName -CurrentStorageAccount $AzureStorageAccount

			Write-Host "Successfully set The Azure Subscription - $($SubscriptionName)"
			Write-Host "Successfully set The Azure Storage Account - $($AzureStorageAccount)"

			# Determining the VM's OS Disk Name based on the VM's Name
			$OSDiskName = $VMName + ".vhd"
			
			# Provisioning New Azure VM.
			$NewAzureVM = New-AzureVMConfig -DiskName $OSDiskName -Name $VMName -InstanceSize $VMSize | New-AzureVM -ServiceName $ServiceName -ErrorVariable AzureVMError -ErrorAction SilentlyContinue
			If ($AzureVMError -ne $null) {
				Write-Host "There was a problem creating the Azure VM for $($VMName)."
				Write-Host $AzureVMError
				exit 2
			}
			
			Write-Host "$($VMName) has been Successfully provisioned in Azure."
			Write-Host "Adding an RDP Endpoint to $($VMName)."

			# Retrieving the Azure VM.
			$AzureVM = Get-AzureVM -Name $VMName -ServiceName $ServiceName -ErrorVariable GetAzureVMError -ErrorAction SilentlyContinue
			If ($GetAzureVMError -ne $null) 
				{
					Write-Host "There was a problem retrieving the VM $($VMName) in Azure."
					Write-Host $GetAzureVMError
					exit 2
				}	

			# Creating the 5-Digit Public Port Number based upon the Numbers in the Name of the VM. 
			Write-Host "Creating a Public Port to listen for traffic on based on the last three numbers contained in the name of the VM."
			$VMNameNumbers = [regex]::Match($VMName,'\\d{3}')
			$PublicPortNumber = "62" + $VMNameNumbers.Value			
						
			# Adding the New Endpoint to the Azure VM.
			$AddRDPEndPoint = Add-AzureEndpoint -Name "RDP" -LocalPort "3389" -PublicPort $PublicPortNumber -Protocol TCP -VM $AzureVM -EV AzureEndpointError -EA SilentlyContinue | Update-AzureVM 
			If ($AzureEndpointError -ne $null) 
				{
					Write-Host "There was a problem Adding the RDP Endpoint to the Azure VM for $($VMName)."
					Write-Host $AzureEndpointError
					exit 2
				}
			Write-Host "Azure Endpoint(s) for $($VMName) have been Successfully added, RDP Access is available via Port $($PublicPortNumber)."	
			
			$ProvisionAzureVMCompleteFile = [System.IO.File]::Create("C:\\MigrateToAzure\\Provision_VM_In_Azure_Complete.txt").Close()
			Write-Host "Azure Provisioning of $($VMName) is Complete."
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
	only_if {File.exists?("C:\\MigrateToAzure\\Copy_VHD_to_Azure_Complete.txt")}
	not_if {File.exists?("C:\\MigrateToAzure\\Provision_VM_In_Azure_Complete.txt")}
end
