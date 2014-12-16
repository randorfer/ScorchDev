<#
    .SYNOPSIS
        Deploys a PowerShell module to the local PSModulePath of all SMA Runbook workers in an
        environment
    
    .Description
        Deploy module to a network share
        Get a listing of all SMA Runbook workers by querying the current SMA environment's
        web service
            Foreach Runbook Worker
                Attempt to delete all files in the old 'cleanup' folder (ignore errors)
                Check / Set PSModule path
                Delete the existing PowerShell module
                    If error occurs (files in use) copy files to a cleanup directory
                Copy new version of PowerShell module into the correct folder path

        All PowerShell modules must follow the following structure

         ContainingFolder\
            ModuleName\
                ModuleName.psd1
                ModuleName.psm1
                Dependencies
    
    .PARAMETER ModuleName
        The Name of the module to import

    .PARAMETER ModuleRootPath
        The path to the root of the Module Directory
    
    .PARAMETER WebServiceEndpoint
        The web service endpoint of the SMA environment to use for accessing variables
        Defaults to https://localhost

    
#>
Workflow Deploy-LocalPowerShellModule
{
    Param( [Parameter(Mandatory=$true) ][string] $ModuleName,
           [Parameter(Mandatory=$true) ][string] $ModuleRootPath,
           [Parameter(Mandatory=$false)][string] $WebServiceEndpoint = "https://localhost")
    
    Function Update-NetworkPowerShellModule
    {
        Param([Parameter(Mandatory=$true)][string] $NetworkPowerShellModulePath,
              [Parameter(Mandatory=$true)][string] $ModuleName,
              [Parameter(Mandatory=$true)][string] $ModuleRootPath)
        
        Write-Verbose -Message "Starting Function Update-NetworkPowerShellModule"

        $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
        
        $null = $(
            $ModuleNetworkPath = "$NetworkPowerShellModulePath\$ModuleName"
            $CleanupFolder     = "$NetworkPowerShellModulePath\Cleanup"
            
            if(Test-Path $CleanupFolder)
            {
                $itemsToCleanup = Get-ChildItem -Path $CleanupFolder
                try
                {
                    foreach($item in $itemsToCleanup)
                    {
                        Remove-Item -Path $item.FullName `
                                    -Recurse `
                                    -Force `
                                    -Confirm:$false
                    }
                }
                catch
                {
                    # Do nothing probably an open file. Future passes will attempt
                }

            }
            else
            {
                New-Item -Path $CleanupFolder `
                            -ItemType Directory `
                            -Force `
                            -Confirm:$false
            }
            if(Test-Path -Path $ModuleNetworkPath)
            {
                # Move the old folder to the cleanup directory
                # it will be cleaned up on the next deploy
                Move-Item -Path $ModuleNetworkPath `
                            -Destination $CleanupFolder `
                            -Confirm:$false `
                            -Force
            }
            Copy-Item -Path $ModuleRootPath `
                      -Destination $ModuleNetworkPath `
                      -Recurse `
                      -Force `
                      -Confirm:$false
        )
        Write-Verbose "`$ModuleNetworkPath [$ModuleNetworkPath]"
        Write-Verbose -Message "Finished Function Update-NetworkPowerShellModule"
        return $ModuleNetworkPath
    }
    
    Write-Debug -Message "Starting Deploy-LocalPowerShellModule for [$ModuleName]"

    # Load variables from variables store
    $CredName = (Get-SmaVariable -Name "SMAContinuousIntegration-CredName" -WebServiceEndpoint $WebServiceEndpoint).Value
	Write-Verbose -Message "Accessing Credential Store for Cred $CredName"
	$Cred = Get-AutomationPSCredential -Name $CredName
    
    $LocalPowerShellModulePath   = (Get-SmaVariable -Name "SMAContinuousIntegration-LocalPowerShellModulePath" -WebServiceEndpoint $WebServiceEndpoint).Value
    $NetworkPowerShellModulePath = (Get-SmaVariable -Name "SMAContinuousIntegration-NetworkPowerShellModulePath" -WebServiceEndpoint $WebServiceEndpoint).Value
    Write-Verbose -Message "`$LocalPowerShellModulePath [$LocalPowerShellModulePath]"
    Write-Verbose -Message "`$NetworkPowerShellModulePath [$NetworkPowerShellModulePath]"

    $ModuleNetworkPath = Update-NetworkPowerShellModule -NetworkPowerShellModulePath $NetworkPowerShellModulePath `
                                                        -ModuleName $ModuleName `
                                                        -ModuleRootPath $ModuleRootPath

    # Get listing of the current environment workers
    $WorkerList = (Get-SmaRunbookWorkerDeployment -WebServiceEndpoint $WebServiceEndpoint).ComputerName

    # Deploy the local module on all the runbook workers in the current deployment
    inlinescript
    {
        $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Continue
		& {
			$null = $(
				$DebugPreference       = [System.Management.Automation.ActionPreference]$Using:DebugPreference
				$VerbosePreference     = [System.Management.Automation.ActionPreference]$Using:VerbosePreference
				$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

                $ModuleNetworkPath         = $Using:ModuleNetworkPath
                $ModuleName                = $Using:ModuleName
                $LocalPowerShellModulePath = $Using:LocalPowerShellModulePath

				$DestinationLocalPath      = "$LocalPowerShellModulePath\$ModuleName"
                        
                Write-Verbose -Message "Starting Local Deployment"
                        
                # Ensure that the LocalPowerShellModulePath exists on the system
                if(-not (Test-Path -Path $LocalPowerShellModulePath))
                {
                    New-Item -Path $LocalPowerShellModulePath `
                                -ItemType Directory `
                                -Force `
                                -Confirm:$false
                }

                # Create and / or cleanup the local cleanup folder
                $CleanupFolder = "$($LocalPowerShellModulePath.SubString(0,$LocalPowerShellModulePath.LastIndexOf('\')))\PowerShellModuleCleanup"
                if(Test-Path $CleanupFolder)
                {
                    $itemsToCleanup = Get-ChildItem -Path $CleanupFolder
                    try
                    {
                        foreach($item in $itemsToCleanup)
                        {
                            Remove-Item -Path $item.FullName `
                                        -Recurse `
                                        -Force `
                                        -Confirm:$false
                        }
                    }
                    catch
                    {
                        # Do nothing probably an open file. Future passes will attempt
                    }

                }
                else
                {
                    New-Item -Path $CleanupFolder `
                                -ItemType Directory `
                                -Force `
                                -Confirm:$false
                }

                # Confirm that the LocalPowerShellModule path is in the Environment PS Module Path
                $machinePSModulePath = [Environment]::GetEnvironmentVariable('PSModulePath','Machine')
                if (@($machinePSModulePath -split ';') -notcontains $LocalPowerShellModulePath)
                {
	                # Add the module base path to the machine environment variable
	                $machinePSModulePath += ";$($LocalPowerShellModulePath)"
	                # Add the module base path to the process environment variable
	                $env:PSModulePath += ";$($LocalPowerShellModulePath)"
	                # Update the machine environment variable value on the local computer
	                [Environment]::SetEnvironmentVariable('PSModulePath', $machinePSModulePath, 'Machine')
                }

                # If an old version of the module exists move it to the cleanup folder
                if(Test-Path -Path $DestinationLocalPath)
                {
                    # Move the old folder to the cleanup directory
                    # it will be cleaned up on the next deploy
                    Move-Item -Path $DestinationLocalPath `
                                -Destination $CleanupFolder `
                                -Confirm:$false `
                                -Force
                }
                Copy-Item -Path $ModuleNetworkPath `
                            -Destination $DestinationLocalPath `
                            -Recurse `
                            -Force `
                            -Confirm:$false

                Write-Verbose -Message "Finished Local Deployment"
            )
        }
    } -PSComputerName $WorkerList -PSCredential $Cred -PSAuthentication CredSSP
    
	New-VariableRunbookTrackingInstance -VariablePrefix 'TFSContinuousIntegration-LocalPSModuleDeploy' -WebServiceEndpoint $WebServiceEndpoint

    Write-Debug -Message "Finished Deploy-LocalPowerShellModule for [$ModuleName]"
}