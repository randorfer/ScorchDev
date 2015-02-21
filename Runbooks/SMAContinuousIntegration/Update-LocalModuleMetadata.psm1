<#
    .Synopsis
        Runs in an SMA environment and imports all metadata about a PowerShell module
        into the environment
#>
Workflow Update-LocalModuleMetadata
{       
    Param([Parameter(Mandatory=$True)] $ModuleName)

    Write-Verbose -Message "[$ModuleName] Started [$WorkflowCommandName]"

    try 
    {
		Set-AutomationActivityMetadata -ModuleName $ModuleName -ModuleVersion 1 -ListOfCommands (Get-Command -Module $ModuleName).Name
	} 
	catch 
    {
		Throw-Exception -Type 'ModuleActivityFailure' `
                        -Message 'Failed to set the module activity metadata' `
                        -Property @{ 'Error' = $_ }
	}
       
    Write-Verbose -Message "[$ModuleName] Finished [$WorkflowCommandName]"                            
}