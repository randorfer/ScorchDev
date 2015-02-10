<#
    .Synopsis
        Takes a json file and publishes all schedules and variables from it into SMA
    .Parameter
#>
Workflow Publish-SMASettingsFileChange
{
    Param( [Parameter(Mandatory=$True)][String] $FilePath )
    
    Write-Verbose -Message "Starting [$WorkflowCommandName]"
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

    $CIVariables = Get-BatchAutomationVariable -Name @('SMACredName',
                                                       'WebserviceEndpoint'
                                                       'WebservicePort') `
                                               -Prefix 'SMAContinuousIntegration'
    $SMACred = Get-AutomationPSCredential -Name $CIVariables.SMACredName

    Try
    {
        $Variables = Get-SmaVariablesFromFile -FilePath $FilePath
        foreach($VariableJSON in $Variables)
        {
            Write-Verbose -Message "[$VariableJSON] Updating"
            $Variable = ConvertFrom-Json $VariableJSON

            if(ConvertTo-Boolean $Variable.isEncrypted)
            {
                $CreateEncryptedVariable = Set-SmaVariable -Name $Variable.Name `
													       -Value $Variable.Value `
														   -Description $Variable.Description `
                                                           -Encrypted `
														   -WebServiceEndpoint $CIVariables.WebserviceEndpoint `
                                                           -Port $CIVariables.WebservicePort `
                                                           -Credential $SMACred `
                                                           -Force
            }
            else
            {
                $CreateNonEncryptedVariable = Set-SmaVariable -Name $Variable.Name `
													          -Value $Variable.Value `
														      -Description $Variable.Description `
														      -WebServiceEndpoint $CIVariables.WebserviceEndpoint `
                                                              -Port $CIVariables.WebservicePort `
                                                              -Credential $SMACred
            }
            Write-Verbose -Message "[$($Variable.Name)] Finished Updating"
        }
    }
    Catch
    {
        Write-Exception -Stream Warning -Exception $_
    }
    Write-Verbose -Message "Finished [$WorkflowCommandName]"
}