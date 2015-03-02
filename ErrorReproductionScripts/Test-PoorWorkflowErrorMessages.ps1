workflow Test-ReservedWordAssignment
{
    $To = 'somebody@somewhere.net'
}

<#
Produces this:

The workflow 'Test-ReservedWordAssignment' could not be started: The following errors were encountered while processing the workflow tree:
'DynamicActivity': The private implementation of activity '1: DynamicActivity' has the following validation error:   Compiler error(s) encountered processing expression "To".
Expression expected.
At line:383 char:21
+                     throw (New-Object System.Management.Automation.ErrorRecord $ ...
+ ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    + CategoryInfo          : InvalidArgument: (System.Manageme...etersDictionary:PSBoundParametersDictionary) [], RuntimeException
    + FullyQualifiedErrorId : StartWorkflow.InvalidArgument
#>