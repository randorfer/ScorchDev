<#
    .Synopsis
        Takes a ps1 file and publishes it to the current SMA environment.
        Creates a new source controlled .json settings file if one does not already exist
    .Parameter
#>
Workflow Publish-SMARunbookChange
{
    Param( [Parameter(Mandatory=$True)][String] $FilePath,
           [Parameter(Mandatory=$True)][String] $CurrentCommit )
    
    Write-Verbose -Message "Starting [$WorkflowCommandName]"
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

    $CIVariables = Get-BatchAutomationVariable -Name @('SMACredName',
                                                       'WebserviceEndpoint'
                                                       'WebservicePort') `
                                               -Prefix 'SMAContinuousIntegration'
    $SMACred = Get-AutomationPSCredential -Name $CIVariables.SMACredName

    Try
    {
        $WorkflowName = Get-SmaWorkflowNameFromFile -FilePath $FilePath
        $CommitTag = "CurrentCommit:$CurrentCommit;"
        
        $ErrorActionPreference = [System.Management.Automation.ActionPreference]::SilentlyContinue
        $Runbook = Get-SmaRunbook -Name $WorkflowName `
                                    -WebServiceEndpoint $CIVariables.WebserviceEndpoint `
                                    -Port $CIVariables.WebservicePort `
                                    -Credential $SMACred
        $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

        if(Test-IsNullOrEmpty $Runbook.RunbookID.Guid)
        {
           Write-Verbose -Message "[$WorkflowName] Initial Import"
            
            $ImportedRunbook = Import-SmaRunbook -Path $FilePath `
                                                 -WebServiceEndpoint $CIVariables.WebserviceEndpoint `
                                                 -Port $CIVariables.WebservicePort `
                                                 -Credential $SMACred
            
            $Runbook = Get-SmaRunbook -Name $WorkflowName `
                                      -WebServiceEndpoint $CIVariables.WebserviceEndpoint `
                                      -Port $CIVariables.WebservicePort `
                                      -Credential $SMACred
            $TagLine = $CommitTag
            $NewVersion = $True
        }
        else
        {
            Write-Verbose -Message "[$WorkflowName] Update"
            $TagUpdateJSON = New-SmaChangesetTagLine -TagLine $Runbook.Tags `
                                                     -CurrentCommit $CurrentCommit
            $TagUpdate = ConvertFrom-Json $TagUpdateJSON
            $TagLine = $TagUpdate.TagLine
            $NewVersion = $TagUpdate.NewVersion
            if($NewVersion)
            {
                $EditStatus = Edit-SmaRunbook -Overwrite `
                                          -Path $FilePath `
                                          -Name $WorkflowName `
                                          -WebServiceEndpoint $CIVariables.WebserviceEndpoint `
                                          -Port $CIVariables.WebservicePort `
                                          -Credential $SMACred                
            }
            else
            {
                Write-Verbose -Message "[$WorkflowName] Already is at commit [$CurrentCommit]"
            }
        }
        if($NewVersion)
        {
            $PublishHolder = Publish-SmaRunbook -Name $WorkflowName `
                                                -WebServiceEndpoint $CIVariables.WebserviceEndpoint `
                                                -Port $CIVariables.WebservicePort `
                                                -Credential $SMACred

            Set-SmaRunbookTags -RunbookID $Runbook.RunbookID.Guid `
                               -Tags $TagLine `
                               -WebserviceEndpoint $CIVariables.WebserviceEndpoint `
                               -Port $CIVariables.WebservicePort `
                               -Credential $SMACred
        }
    }
    Catch
    {
        Write-Exception -Stream Warning -Exception $_
    }
    Write-Verbose -Message "Finished [$WorkflowCommandName]"
}