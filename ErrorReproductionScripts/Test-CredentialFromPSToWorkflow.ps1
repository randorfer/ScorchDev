<#
    Serialization / Deserialization is very slow for complex objects
#>

workflow Test-CredentialFromPSToWorkflow
{
    Write-Verbose -Message 'Before InlineScript'
    $Cred = InlineScript
    {
        $SecurePassword = ConvertTo-SecureString -String 'MyTestPassword' -AsPlainText -Force
        $Cred = New-Object -TypeName 'System.Management.Automation.PSCredential' -ArgumentList 'TestUser', $SecurePassword
        Write-Verbose -Message 'Got the credential in the InlineScript'
        # The InlineScript will never return
        return $Cred
    }
    Write-Verbose -Message 'After InlineScript'
}