#requires -Version 2
<# 
    .Synopsis
        Uses ADO .NET to query SQL

    .Description
        Queries a SQL Database and returns a datatable of results

    .Parameter query
        The SQL Query to run
 
    .Parameter parameters
        A list of SQLParameters to pass to the query

    .Parameter connectionString
        Sql Connection string for the DB to connect to

    .Parameter timeout
        timeout property for SQL query. Default is 60 seconds

    .Parameter Credential
        if specified the credential will be used to connect to an SMA box and launch
        the SQL query as the target user.

        If specified the computer parameter becomes optional. This is the computer to connect
        to with this credential (using CredSSP authentication)

    .Parameter Computer
         This is the computer to connect to if Credntial is specified (using CredSSP authentication)
         Defaults to localhost

    .Example
        # run a simple query

        $connectionString = ""
        $parameters = @{}
        Invoke-SqlQuery -query "SELECT GroupID, GroupName From [dbo].[Group] WHERE GroupName=@GroupName" -parameters @{"@GroupName"="genmills\groupName"} -connectionString $connectionString;
        Invoke-SqlQuery -query "SELECT GroupID, GroupName From [dbo].[Group]" -parameters @{} -connectionString $connectionString;
#>
function Invoke-SqlQuery
{
    Param(
        [Parameter(
                Mandatory = $True
        )]
        [string]
        $Query, 
        
        [Parameter(
                Mandatory = $False
        )]
        [System.Collections.Hashtable]
        $Parameters, 

        [Parameter(
                Mandatory = $True
        )]
        [string]
        $ConnectionString, 

        [Parameter(
                Mandatory = $False
        )]
        [int]
        $Timeout = 60,

        [Parameter(
                Mandatory = $False,
                ParameterSetName = 'Credential'
        )]
        [pscredential]
        $Credential = $Null,

        [Parameter(
                Mandatory = $False,
                ParameterSetName = 'Credential'
        )]
        [string]
        $Computer = 'localhost'
    )
    
    Write-Debug -Message "`$query [$query]"
    Write-Debug -Message "`$connectionString [$connectionString]"
    Write-Debug -Message "`$timeout [$timeout]"
    $ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
    if($Credential)
    {
        $Result = Invoke-Command -ComputerName $Computer -Credential $Credential -Authentication Credssp -ScriptBlock {
            $parameters = $Using:Parameters
            $connectionString = $Using:connectionString
            $query = $Using:query
            $timeout = $Using:timeout
            try
            {
                foreach($paramKey in $parameters.Keys)
                {
                    Write-Debug -Message "`$paramKey   [$paramKey]"
                    Write-Debug -Message "`$ParamValue [$($parameters[$paramKey])]"
                }
                $sqlConnection = New-Object -TypeName System.Data.SqlClient.SqlConnection `
                                            -ArgumentList $connectionString
                $sqlConnection.Open()

                #Create a command object
                $sqlCommand = $sqlConnection.CreateCommand()
                $sqlCommand.CommandText = $query
                if($parameters)
                {
                    foreach($key in $parameters.Keys)
                    {
                        $null = $sqlCommand.Parameters.AddWithValue($key, $parameters[$key])
                    }
                }
                $sqlCommand.CommandTimeout = $timeout

                #Execute the Command
                $sqlReader = $sqlCommand.ExecuteReader()

                $Datatable = New-Object -TypeName System.Data.DataTable
                $Datatable.Load($sqlReader)
            }
            Finally
            {
                if($sqlConnection -and $sqlConnection.State -ne [System.Data.ConnectionState]::Closed)
                {
                    $sqlConnection.Close()
                }
            }
            return $Datatable -as [System.Data.DataTable]
        }
        $Result
    }
    else
    {
        try
        {
            foreach($paramKey in $parameters.Keys)
            {
                Write-Debug -Message "`$paramKey   [$paramKey]"
                Write-Debug -Message "`$ParamValue [$($parameters[$paramKey])]"
            }
            $sqlConnection = New-Object -TypeName System.Data.SqlClient.SqlConnection `
                                        -ArgumentList $connectionString
            $sqlConnection.Open()

            #Create a command object
            $sqlCommand = $sqlConnection.CreateCommand()
            $sqlCommand.CommandText = $query
            if($parameters)
            {
                foreach($key in $parameters.Keys)
                {
                    $null = $sqlCommand.Parameters.AddWithValue($key, $parameters[$key])
                }
            }

            $sqlCommand.CommandTimeout = $timeout

            #Execute the Command
            $sqlReader = $sqlCommand.ExecuteReader()

            $Datatable = New-Object -TypeName System.Data.DataTable
            $Datatable.Load($sqlReader)
        }
        Finally
        {
            if($sqlConnection -and $sqlConnection.State -ne [System.Data.ConnectionState]::Closed)
            {
                $sqlConnection.Close()
            }
        }
        return $Datatable
    }
}
Export-ModuleMember -Function * -Verbose:$False