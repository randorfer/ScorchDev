# SCOrchDev-Exception
PowerShell module for wrapping and handling custom exceptions!

The way that powershell handles exceptions is a bit akward if you come from another language and is inconsistant between powershell and powershell workflow, which makes good error handling routines hard to write and support for enterprise automation like what is written for SMA. Using this library you can make routines (like below) that behave the same way in PowerShell and PowerShell worfklow

Example:
<pre><code>
Function Test-Throw-Function
{
    try
    {
        Throw-Exception -Type 'CustomTypeA' `
                        -Message 'MessageA' `
                        -Property @{
                            'a' = 'b'
                        }
    }
    catch
    {
        $Exception = $_
        $ExceptionInfo = Get-ExceptionInfo -Exception $Exception
        Switch -CaseSensitive ($ExceptionInfo.Type)
        {
            'CustomTypeA'
            {
                Write-Exception -Exception $Exception -Stream Verbose
                $a = $_
            }
            Default
            {
                Write-Warning -Message 'unhandled' -WarningAction Continue
            }
        }
    }
}
</pre></code>
<pre><code>
Workflow Test-Throw-Workflow
{
    try
    {
        Throw-Exception -Type 'CustomTypeA' `
                        -Message 'MessageA' `
                        -Property @{
                            'a' = 'b'
                        }
    }
    catch
    {
        $Exception = $_
        $ExceptionInfo = Get-ExceptionInfo -Exception $Exception
        Switch -CaseSensitive ($ExceptionInfo.Type)
        {
            'CustomTypeA'
            {
                Write-Exception -Exception $Exception -Stream Verbose
                $a = $_
            }
            Default
            {
                Write-Warning -Message 'unhandled' -WarningAction Continue
            }
        }
    }
}
</pre></code>
Both will output the same thing
<pre>
C:\Windows\System32\WindowsPowerShell\v1.0> Test-Throw-Workflow
VERBOSE: [localhost]:Exception information
------
a = b
Message = MessageA
Type = CustomTypeA
__CUSTOM_EXCEPTION__ = True

C:\Windows\System32\WindowsPowerShell\v1.0> Test-Throw-Function
VERBOSE: Exception information
------
a = b
Message = MessageA
Type = CustomTypeA
__CUSTOM_EXCEPTION__ = True
</pre>
