<#
    .Synopsis
        Monitors Sma Runbook workers. When they are found to be unhealthy
        invokes a process dump for the top processes running
#>

Workflow Monitor-SmaRunbookWorker
{
    Write-Verbose -Message "Starting [$WorkflowCommandName]"
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop

    $SmaRunbookWorkerVars = Get-BatchAutomationVariable -Name @('WebServiceEndpoint',
                                                                'WebServicePort',
                                                                'AccessCredName',
                                                                'MinimumPercentFreeMemory',
                                                                'MinimumProcDumpPerDay',
                                                                'DaysToKeepProcDump',
                                                                'ProcDumpPath',
                                                                'ProcessesToDumpJSON') `
                                                        -Prefix 'SmaRunbookWorker'
    $AccessCred = Get-AutomationPSCredential -Name $SmaRunbookWorkerVars.AccessCredName
    $Worker = Get-SMARunbookWorker

    Do
    {
        Foreach -Parallel ($Worker in (Get-SmaRunbookWorker))
        {
            $DumpPath = "$($SmaRunbookWorkerVars.ProcDumpPath)\$(Get-Date -Format MM-d-yyyy)\$($env:COMPUTERNAME)"
            $WorkerStatus = Test-SmaRunbookWorker -RunbookWorker $Worker `
                                                  -MinimumPercentFreeMemory $SmaRunbookWorkerVars.MinimumPercentFreeMemory `
                                                  -AccessCred $AccessCred
        
            if($WorkerStatus -eq 'Healthy')
            {
                # Check if there has been a process dump in the last 24 hours. If not create process dump
            }
            else
            {
                Invoke-RemoteProcDump -ComputerName $Worker `
                                      -DumpPath $DumpPath `
                                      -ProcessList $SmaRunbookWorkerVars.ProcessesToDumpJSON `
                                      -AccessCredName $SmaRunbookWorkerVars.AccessCredName
            }

            # Cleanup old process dumps
            # Implement Delay Cycle
        }
    }
    While($MonitorActive)

    Start-SmaRunbook -Name $WorkflowCommandName
    Write-Verbose -Message "Finished [$WorkflowCommandName]"
}