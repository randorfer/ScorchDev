$here = Split-Path -Parent $MyInvocation.MyCommand.Path

Select-LocalDevWorkspace SCOrchDev

Describe "Invoke-GitRepositorySync" {
    Mock Get-AutomationPSCredential {
        return new-object -TypeName System.Management.Automation.PSCredential -ArgumentList 'user\a', ('asdf'|ConvertTo-SecureString -AsPlainText -Force)
    }
    Mock Connect-AzureRmAccount { 
    }
    
    Mock Set-AutomationVariable {
        Return $Value
    }
    Mock Sync-GitRepositoryToAzureAutomation {
        '123'
    }

    $Output = & "$Here\../Runbooks/GitRepositorySync/Invoke-GitRepositorySync.ps1"
    It 'Should establish a connection to azure' {
        Assert-MockCalled -CommandName Connect-AzureRmAccount -Times 1
    }

    It 'Should call Sync Git Repository' {
        Assert-MockCalled -CommandName Sync-GitRepositoryToAzureAutomation -Times 1
    }
}
