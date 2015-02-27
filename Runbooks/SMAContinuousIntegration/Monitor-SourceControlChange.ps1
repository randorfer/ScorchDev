<#
    .Synopsis
        Monitors a local git repository for new commits from a centralized repository.
        When a new commit is found a list of modified files is passed to Sync-CommitChanges
        to update the SMA environment with those changes
#>
workflow Monitor-SourceControlChange
{
    Param()
    
    Write-Verbose -Message "Starting [$WorkflowCommandName]"
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

    $CIVariables = Get-BatchAutomationVariable -Name @('MonitorLifeSpan',
                                                       'MonitorDelayCycle',
                                                       'MonitorCheckpoint',
                                                       'RepositoryInformation') `
                                               -Prefix 'SMAContinuousIntegration'

    $MonitorRefreshTime = ( Get-Date ).AddMinutes( $CIVariables.MonitorLifeSpan )
    $MonitorActive      = ( Get-Date ) -lt $MonitorRefreshTime
    $LastCommit         = $CIVariables.GitCurrentCommit
    while($MonitorActive)
    {
		try
		{
            $RepositoryInformation = ConvertFrom-JSON $CIVariables.RepositoryInformation
            foreach($RepositoryName in (ConvertFrom-PSCustomObject -InputObject $RepositoryInformation `
                                                                   -KeyFilterScript {
                                                                        Param($KeyName)
                                                                        if($KeyName -notin ('PSComputerName',
                                                                                            'PSShowComputerName',
                                                                                            'PSSourceJobInstanceId'))
                                                                        {
                                                                            $KeyName
                                                                        }}).Keys )
            {
                Write-Verbose -Message "[$RepositoryName] Starting Processing"
                Invoke-GitRepositorySync -RepositoryName $RepositoryName
                Write-Verbose -Message "[$RepositoryName] Finished Processing"
            }
        }
        catch
        {
            switch -CaseSensitive ((Get-ExceptionInfo -Exception $_).Type)
            {
                'GitTargetBranchNotFound'
                {
                    Throw $_
                }
                default
                {
                    Throw $_
                }
            }
        }
        finally
		{
			#region Sleep for Delay Cycle
			[int]$RemainingDelay = $CIVariables.MonitorDelayCycle - (Get-Date).TimeOfDay.TotalSeconds % $CIVariables.MonitorDelayCycle 
			If ( $RemainingDelay -eq 0 ) { $RemainingDelay = $CIVariables.MonitorDelayCycle  }
			Write-Verbose -Message "Sleeping for $RemainingDelay seconds."
			Checkpoint-Workflow

			While ( $RemainingDelay -gt 0 )
			{    
				Start-Sleep -Seconds ( [math]::Min( $RemainingDelay, $CIVariables.MonitorCheckpoint ) )
				Checkpoint-Workflow
				$RemainingDelay -= $CIVariables.MonitorCheckpoint
			}
			#endregion
			$MonitorActive = ( Get-Date ) -lt $MonitorRefreshTime
		}
    }
	#  Relaunch this monitor
	Write-Verbose -Message "Reached end of monitor lifespan. Relaunching this monitor [$WorkflowCommandName]."
	$Launch = Start-SmaRunbook -Name $WorkflowCommandName `
     						   -WebServiceEndpoint $WebServiceEndpoint
}