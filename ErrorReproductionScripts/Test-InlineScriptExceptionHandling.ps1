<#
    In theory both of these should behave the exact same. They don't.
#>

workflow Test-InlinescriptExceptionHandling
{
    $ErrorActionPreference = 'continue'
    InlineScript
    {
        & 'C:\does\not\exist'
    }
    Write-Verbose -Message 'Above terminates'
}

workflow Test-InlinescriptExceptionHandling1
{
    $ErrorActionPreference = 'continue'
    InlineScript
    {
        Write-Verbose "$ErrorActionPreference"
        & 'C:\does\not\exist'
    }
    Write-Verbose -Message 'The above does not terminate'
}