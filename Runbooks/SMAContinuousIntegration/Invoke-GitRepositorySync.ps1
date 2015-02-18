<#
    .Synopsis
        Check GIT repository for new commits. If found sync the changes into
        the current SMA environment

    .Parameter RepositoryName
#>
Workflow Invoke-GitRepositorySync
{
    Param([Parameter(Mandatory=$true)][String] $RepositoryName)
    
    Write-Verbose -Message "Starting [$WorkflowCommandName]"
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

    $CIVariables = Get-BatchAutomationVariable -Name @('RepositoryInformation',
                                                       'SMACredName',
                                                       'WebserviceEndpoint'
                                                       'WebservicePort') `
                                               -Prefix 'SMAContinuousIntegration'
    $SMACred = Get-AutomationPSCredential -Name $CIVariables.SMACredName
    Try
    {
        $RepositoryInformation = (ConvertFrom-Json $CIVariables.RepositoryInformation)."$RepositoryName"
        Write-Verbose -Message "`$RepositoryInformation [$(ConvertTo-JSON $RepositoryInformation)]"

        $RunbookWorker = Get-SmaRunbookWorkerDeployment -WebServiceEndpoint $CIVariables.WebserviceEndpoint `
                                                        -Port $CIVariables.WebservicePort `
                                                        -Credential $SMACred
        
        # Update the repository on all SMA Workers
        InlineScript
        {
            $RepositoryInformation = $Using:RepositoryInformation
            Update-GitRepository -RepositoryInformation $RepositoryInformation
        } -PSComputerName $RunbookWorker -PSCredential $SMACred

        $RepositoryChangeJSON = Find-GitRepositoryChange -RepositoryInformation $RepositoryInformation
        $RepositoryChange = ConvertFrom-JSON -InputObject $RepositoryChangeJSON

        if($RepositoryChange.CurrentCommit -ne $RepositoryInformation.CurrentCommit)
        {
            Write-Verbose -Message "Processing [$($RepositoryInformation.CurrentCommit)..$($RepositoryInformation.CurrentCommit)]"
            
            $ReturnInformation = ConvertFrom-JSON (Group-RepositoryFile -Files $RepositoryChange.Files)
            Foreach($RunbookFilePath in $ReturnInformation.ScriptFiles)
            {
                Write-Verbose -Message "[$($RunbookFilePath)] Starting Processing"
                Publish-SMARunbookChange -FilePath $RunbookFilePath `
                                         -CurrentCommit $RepositoryChange.CurrentCommit `
                                         -RepositoryName $RepositoryName
                Write-Verbose -Message "[$($RunbookFilePath)] Finished Processing"
            }
            Foreach($SettingsFilePath in $ReturnInformation.SettingsFiles)
            {
                Write-Verbose -Message "[$($SettingsFilePath)] Starting Processing"
                Publish-SMASettingsFileChange -FilePath $SettingsFilePath `
                                              -CurrentCommit $RepositoryChange.CurrentCommit `
                                              -RepositoryName $RepositoryName
                Write-Verbose -Message "[$($SettingsFilePath)] Finished Processing"
            }
            Checkpoint-Workflow

            if($ReturnInformation.CleanRunbooks)
            {
                Remove-SmaOrphanRunbook -RepositoryName $RepositoryName
            }
            if($ReturnInformation.CleanAssets)
            {
                Remove-SmaOrphanAsset -RepositoryName $RepositoryName
            }
            
            $UpdatedRepositoryInformation = Set-SmaRepositoryInformationCommitVersion -RepositoryInformation $CIVariables.RepositoryInformation `
                                                                                      -Path $Path `
                                                                                      -Commit $RepoChange.CurrentCommit
            Set-SmaVariable -Name 'SMAContinuousIntegration-RepositoryInformation' `
                            -Value $UpdatedRepositoryInformation `
                            -WebServiceEndpoint $CIVariables.WebserviceEndpoint `
                            -Port $CIVariables.WebservicePort `
                            -Credential $SMACred

            Write-Verbose -Message "Finished Processing [$($RepositoryInformation.CurrentCommit)..$($RepoChange.CurrentCommit)]"
        }
    }
    Catch
    {
        Write-Exception -Stream Warning -Exception $_
    }
    Write-Verbose -Message "Finished [$WorkflowCommandName]"
}