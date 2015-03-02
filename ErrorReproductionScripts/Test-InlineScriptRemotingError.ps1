<#
    Here’s an example of a simpler workflow that demonstrates the bug:
    It generates an error after the third iteration. But because of the ErrorActionPreference, the $i variable isn’t updated appropriately and you get 10 iterations.

    Fixed in PSv5
#>

workflow Test-InlineScriptRemotingError
{
    foreach ($i in 1..10)
    {
        inlinescript
        {
            $errorActionPreference = "Stop"
 
            "Before: " + $using:i
            if($using:i -gt 3)
            {
                Write-Error -Message Error
            }
            "After."
        } -PSComputerName localhost
    }
}

workflow Test-InlineScriptRemotingErrorWorkaround
{
    foreach ($i in 1..10)
    {
        inlinescript
        {
            & {
                $errorActionPreference = "Stop"
 
                "Before: " + $using:i
                if($using:i -gt 3)
                {
                    Write-Error -Message Error
                }
                "After."
            }
        } -PSComputerName localhost
    }
}