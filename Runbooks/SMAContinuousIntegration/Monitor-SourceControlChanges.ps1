<#
    #TODO Put header information here
#>
workflow Monitor-SourceControlChanges
{
    Param()
    
    Write-Verbose -Message "Starting [$WorkflowCommandName]"
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

    $CIVariables = Get-BatchAutomationVariable -Name @('MonitorLifeSpan',
                                                       'MonitorDelayCycle',
                                                       'MonitorCheckpoint',
                                                       'GitLocalRepo',
                                                       'GitBranch',
                                                       'GitCurrentCommit') `
                                               -Prefix 'SMAContinuousIntegration'

    $MonitorRefreshTime = ( Get-Date ).AddMinutes( $CIVariables.MonitorLifeSpan )
    $MonitorActive      = ( Get-Date ) -lt $MonitorRefreshTime
    
    while($MonitorActive)
    {
		try
		{
			$RepoChange = ConvertFrom-JSON( Find-GitRepoChange -Path $CIVariables.GitLocalRepo `
                                                               -Branch $CIVariables.GitBranch `
                                                               -LastCommit $CIVariables.GitCurrentCommit)

            if($RepoChange.Status -eq 'Updates')
            {
                Write-Warning -Message "Updates Found" -WarningAction Continue
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
			[int]$RemainingDelay = $DelayCycle - (Get-Date).TimeOfDay.TotalSeconds % $DelayCycle
			If ( $RemainingDelay -eq 0 ) { $RemainingDelay = $DelayCycle }
			Write-Verbose -Message "Sleeping for $RemainingDelay seconds."
			Checkpoint-Workflow

			While ( $RemainingDelay -gt 0 )
			{    
				Start-Sleep -Seconds ( [math]::Min( $RemainingDelay, $DelayCheckpoint ) )
				Checkpoint-Workflow
				$RemainingDelay -= $DelayCheckpoint
			}
			#endregion
			$MonitorActive = ( Get-Date ) -lt $MonitorRefreshTime
		}
    }
	#  Relaunch this monitor
	Write-Verbose -Message "Reached end of monitor lifespan. Relaunching this monitor [$WorkflowCommandName]."
	#$Launch = Start-SmaRunbook -Name $WorkflowCommandName `
#							   -WebServiceEndpoint $WebServiceEndpoint
}