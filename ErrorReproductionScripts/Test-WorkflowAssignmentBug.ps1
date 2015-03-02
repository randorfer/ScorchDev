workflow Test-ArgumentAssignmentBug
{
    param([string] $MyArg)

    $MyArg = Helper
}

workflow Test-ArgumentAssignmentBugWorkaround
{
    param([string] $MyArg)

    $t = Helper
    $MyArg = $t
}

workflow Helper
{
    return 'Test String'
}