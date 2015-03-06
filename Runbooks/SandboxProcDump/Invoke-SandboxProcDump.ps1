<#
    .Synopsis
        Starts a proc dump on all runbook workers in an environment. 
    
    .Description
        Uses PSAuthentication CredSSP to be able to write the dumps out to a network share.
        You must download procdump from sysinternals onto all runbook workers or a network share
        and update ProcDumpExePath to reflect the location of the executable
#>
Workflow Invoke-SandboxProcDump
{
    Param()
    Write-Verbose -Message "Starting [$WorkflowCommandName]"
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
    
    $ProcDumpVars = Get-BatchAutomationVariable -Name @('DumpPath',
                                                        'WebServiceEndpoint',
                                                        'WebServicePort',
                                                        'ProcDumpExePath',
                                                        'AccessCredName') `
                                                -Prefix 'SandboxProcDump'
    $AccessCred = Get-AutomationPSCredential -Name $ProcDumpVars.AccessCredName
    $Workers = Get-SmaRunbookWorkerDeployment -WebServiceEndpoint $ProcDumpVars.WebServiceEndpoint `
                                              -Port $ProcDumpVars.WebServicePort
    
    foreach -Parallel ($Worker in $Workers)
    {
        inlinescript
        {
            $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Continue
		    & {
			    $null = $(
				    $DebugPreference       = [System.Management.Automation.ActionPreference]$Using:DebugPreference
				    $VerbosePreference     = [System.Management.Automation.ActionPreference]$Using:VerbosePreference
				    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

                    $ProcDumpVars = $Using:ProcDumpVars

                    if(-not (Test-Path $ProcDumpVars.ProcDumpExePath))
                    {
                        Throw-Exception -Type 'ProcDumpExeNotFound' `
                                        -Message 'Could not find the procdump.exe executable' `
                                        -Property @{ 'ProcDumpExePath' = $ProcDumpVars.ProcDumpExePath ;
                                                     'ComputerName' = $Env:ComputerName } 
                    }
                    
                    $DumpPath = "$($ProcDumpVars.DumpPath)\$($(Get-Date).ToShortDateString() -replace '/','-')\$($env:computername)"
                    if(-not (Test-Path -Path $DumpPath))
                    {
                        Write-Verbose -Message "Dump path did not exist for this server - creating [$DumpPath]"
                        New-Item -ItemType Directory -Path $DumpPath
                    }
                    $ProcIDS = (Get-Process -Name Orchestrator.Sandbox).Id
                    foreach($procID in $ProcIDS)
                    {
                        $ProcDumpCommand = "$($ProcDumpVars.ProcDumpExePath) -ma $procID $($DumpPath) -accepteula"
                        Write-Verbose -Message "Starting Procdump [$ProcDumpCommand]"
                        Invoke-Expression -Command $ProcDumpCommand
                    }
                )
            }
        } -PSComputerName $Worker.ComputerName -PSCredential $AccessCred -PSAuthentication CredSSP
    }

    Write-Verbose -Message "Finished [$WorkflowCommandName]"
}