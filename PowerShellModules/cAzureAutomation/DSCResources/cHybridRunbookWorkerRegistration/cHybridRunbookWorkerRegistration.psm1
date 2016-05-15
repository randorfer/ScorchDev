
#######################################################################
# The Get-TargetResource cmdlet.
#######################################################################
function Get-TargetResource
{
	param
	(	
        [parameter(Mandatory)]
        [string] $RunbookWorkerGroup,
        
        [parameter(Mandatory)]
        [string] $AutomationAccountURL,

        [parameter(Mandatory)]
	    [string] $Key
  	)
    
    if(Test-Path -Path 'HKLM:\SOFTWARE\Microsoft\HybridRunbookWorker')
    {
        $LocalGroup = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\HybridRunbookWorker' -Name 'RunbookWorkerGroup').RunbookWorkerGroup
    }
    else
    {
        $LocalGroup ='Not Configured'
    }
    Return @{
        'RunbookWorkerGroup' = $LocalGroup
        'AutomationAccountURL' = $AutomationAccountURL
        'Key' = [string]::Empty
    }
}

######################################################################## 
# The Set-TargetResource cmdlet.
########################################################################
function Set-TargetResource
{
	param
	(	
        [parameter(Mandatory)]
        [string] $RunbookWorkerGroup,
        
        [parameter(Mandatory)]
        [string] $AutomationAccountURL,

        [parameter(Mandatory)]
	    [string] $Key
	)
    $StartingDir = (pwd).Path
    $AzureAutomationInitialPath = 'C:\Program Files\Microsoft Monitoring Agent\Agent\AzureAutomation'
    Try
    {
        # Wait for the completion of the install of OMS Agent.
        $TimeOut = (Get-Date).AddMinutes(1)
        While(((Get-Date) -lt ($TimeOut)) -and (-not (Test-Path -Path $AzureAutomationInitialPath)))
        {
            Start-Sleep -Seconds 10
        }
        
        cd $AzureAutomationInitialPath
        cd $((Get-ChildItem)[0].Name)
        cd HybridRegistration
        Import-Module .\HybridRegistration.psd1

        if(Test-Path -Path 'HKLM:\SOFTWARE\Microsoft\HybridRunbookWorker')
        {
            Try { Remove-HybridRunbookWorker -Url $AutomationAccountURL -Key $Key }
            Catch { Write-Exception -Exception $_ -Stream Verbose }
        }

        Add-HybridRunbookWorker -Url $AutomationAccountURL -Key $Key -GroupName $RunbookWorkerGroup
    }
    Catch { throw }
    Finally { Set-Location -Path $StartingDir }
}

#######################################################################
# The Test-TargetResource cmdlet.
#######################################################################
function Test-TargetResource
{
	[CmdletBinding()]
	param
	(
        [parameter(Mandatory)]
        [string] $RunbookWorkerGroup,
        
        [parameter(Mandatory)]
        [string] $AutomationAccountURL,

        [parameter(Mandatory)]
	    [string] $Key
	)
    
    if(Test-Path -Path 'HKLM:\SOFTWARE\Microsoft\HybridRunbookWorker')
    {
        $LocalGroup = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\HybridRunbookWorker' -Name 'RunbookWorkerGroup').RunbookWorkerGroup
    }
    else
    {
        $LocalGroup ='Not Configured'
    }

    return ($LocalGroup -eq $RunbookWorkerGroup) -as [bool]
}

Export-ModuleMember -Function *-TargetResource


