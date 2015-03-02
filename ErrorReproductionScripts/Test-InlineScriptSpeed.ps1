workflow Test-VerboseWorkflow
{
    $VerbosePreference = 'SilentlyContinue'
    foreach($i in 0..200)
    {
        Write-Verbose -Message 'Test String'
    }
}

workflow Test-InlineScriptInnerWorkflow
{
    $VerbosePreference = 'SilentlyContinue'
    foreach($i in 0..200)
    {
        InlineScript
        {
            Write-Verbose -Message 'Test String'
        }
    }
}

workflow Test-InlineScriptOuterWorkflow
{
    $VerbosePreference = 'SilentlyContinue'
    InlineScript
    {
        foreach($i in 0..200)
        {
            Write-Verbose -Message 'Test String'
        }
    }
}

Measure-Command -Expression { Test-VerboseWorkflow }
Measure-Command -Expression { Test-InlineScriptInnerWorkflow }
Measure-Command -Expression { Test-InlineScriptOuterWorkflow }