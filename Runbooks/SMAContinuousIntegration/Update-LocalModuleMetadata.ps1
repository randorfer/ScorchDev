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
        $commandNames = InlineScript
        {                
            Import-Module -Name $using:ModuleName -WarningAction SilentlyContinue
            $commands = Get-Command -Module $using:ModuleName

            $commands.Name
        }
        $hashtable = @{}
        $commandNames | ForEach-Object -Process { $hashtable.Add($_, "") }

		Set-AutomationActivityMetadata -ModuleName $module.Name -ModuleVersion 1 -ListOfCommands $hashtable.Keys
	} 
	catch 
    {
		Throw-Exception -Type 'ModuleActivityFailure' `
                        -Message 'Failed to set the module activity metadata' `
                        -Property @{ 'Error' = $_ }
	}
       
    Write-Verbose -Message "[$ModuleName] Finished [$WorkflowCommandName]"                            
}