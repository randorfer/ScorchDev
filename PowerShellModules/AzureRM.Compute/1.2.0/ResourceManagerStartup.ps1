# ----------------------------------------------------------------------------------
#
# Copyright Microsoft Corporation
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# http://www.apache.org/licenses/LICENSE-2.0
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# ----------------------------------------------------------------------------------

# Authorization script commandlet that builds on top of existing Insights comandlets. 
# This commandlet gets all events for the "Microsoft.Authorization" resource provider by calling the "Get-AzureRmResourceProviderLog" commandlet

function Get-AzureRmAuthorizationChangeLog { 
<#

.SYNOPSIS

Gets access change history for the selected subscription for the specified time range i.e. role assignments that were added or removed, including classic administrators (co-administrators and service administrators).
Maximum duration that can be queried is 15 days (going back up to past 90 days).


.DESCRIPTION

The Get-AzureRmAuthorizationChangeLog produces a report of who granted (or revoked) what role to whom at what scope within the subscription for the specified time range. 

The command queries all role assignment events from the Insights resource provider of Azure Resource Manager. Specifying the time range is optional. If both StartTime and EndTime parameters are not specified, the default query interval is the past 1 hour. Maximum duration that can be queried is 15 days (going back up to past 90 days).


.PARAMETER StartTime 

Start time of the query. Optional.


.PARAMETER EndTime 

End time of the query. Optional


.EXAMPLE 

Get-AzureRmAuthorizationChangeLog

Gets the access change logs for the past hour.


.EXAMPLE   

Get-AzureRmAuthorizationChangeLog -StartTime "09/20/2015 15:00" -EndTime "09/24/2015 15:00"

Gets all access change logs between the specified dates

Timestamp        : 2015-09-23 21:52:41Z
Caller           : admin@rbacCliTest.onmicrosoft.com
Action           : Revoked
PrincipalId      : 54401967-8c4e-474a-9fbb-a42073f1783c
PrincipalName    : testUser
PrincipalType    : User
Scope            : /subscriptions/9004a9fd-d58e-48dc-aeb2-4a4aec58606f/resourceGroups/TestRG/providers/Microsoft.Network/virtualNetworks/testresource
ScopeName        : testresource
ScopeType        : Resource
RoleDefinitionId : /subscriptions/9004a9fd-d58e-48dc-aeb2-4a4aec58606f/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c
RoleName         : Contributor


.EXAMPLE 

Get-AzureRmAuthorizationChangeLog  -StartTime ([DateTime]::Now - [TimeSpan]::FromDays(5)) -EndTime ([DateTime]::Now) | FT Caller, Action, RoleName, PrincipalName, ScopeType

Gets access change logs for the past 5 days and format the output

Caller                  Action                  RoleName                PrincipalName           ScopeType
------                  ------                  --------                -------------           ---------
admin@contoso.com       Revoked                 Contributor             User1                   Subscription
admin@contoso.com       Granted                 Reader                  User1                   Resource Group
admin@contoso.com       Revoked                 Contributor             Group1                  Resource

.LINK

New-AzureRmRoleAssignment

.LINK

Get-AzureRmRoleAssignment

.LINK

Remove-AzureRmRoleAssignment

#>

    [CmdletBinding()] 
    param(  
        [parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$true, HelpMessage = "The start time. Optional
             If both StartTime and EndTime are not provided, defaults to querying for the past 1 hour. Maximum allowed difference in StartTime and EndTime is 15 days")] 
        [DateTime] $StartTime,

        [parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$true, HelpMessage = "The end time. Optional. 
            If both StartTime and EndTime are not provided, defaults to querying for the past 1 hour. Maximum allowed difference in StartTime and EndTime is 15 days")] 
        [DateTime] $EndTime
    ) 
    PROCESS { 
         # Get all events for the "Microsoft.Authorization" provider by calling the Insights commandlet
         $events = Get-AzureRmLog -ResourceProvider "Microsoft.Authorization" -DetailedOutput -StartTime $StartTime -EndTime $EndTime
             
         $startEvents = @{}
         $endEvents = @{}
         $offlineEvents = @()

         # StartEvents and EndEvents will contain matching pairs of logs for when role assignments (and definitions) were created or deleted. 
         # i.e. A PUT on roleassignments will have a Start-End event combination and a DELETE on roleassignments will have another Start-End event combination
         $startEvents = $events | ? { $_.httpRequest -and $_.Status -ieq "Started" }
         $events | ? { $_.httpRequest -and $_.Status -ne "Started" } | % { $endEvents[$_.OperationId] = $_ }
         # This filters non-RBAC events like classic administrator write or delete
         $events | ? { $_.httpRequest -eq $null } | % { $offlineEvents += $_ } 

         $output = @()

         # Get all role definitions once from the service and cache to use for all 'startevents'
         $azureRoleDefinitionCache = @{}
         Get-AzureRmRoleDefinition | % { $azureRoleDefinitionCache[$_.Id] = $_ }

         $principalDetailsCache = @{}

         # Process StartEvents
         # Find matching EndEvents that succeeded and relating to role assignments only
         $startEvents | ? { $endEvents.ContainsKey($_.OperationId) `
             -and $endEvents[$_.OperationId] -ne $null `
             -and $endevents[$_.OperationId].OperationName.StartsWith("Microsoft.Authorization/roleAssignments", [System.StringComparison]::OrdinalIgnoreCase)  `
             -and $endEvents[$_.OperationId].Status -ieq "Succeeded"} |  % {
       
         $endEvent = $endEvents[$_.OperationId];
        
         # Create the output structure
         $out = "" | select Timestamp, Caller, Action, PrincipalId, PrincipalName, PrincipalType, Scope, ScopeName, ScopeType, RoleDefinitionId, RoleName
				 
         $out.Timestamp = Get-Date -Date $endEvent.EventTimestamp -Format u
         $out.Caller = $_.Caller
         if ($_.HttpRequest.Method -ieq "PUT") {
            $out.Action = "Granted"
            if ($_.Properties.Content.ContainsKey("requestbody")) {
                $messageBody = ConvertFrom-Json $_.Properties.Content["requestbody"]
            }
             
          $out.Scope =  $_.Authorization.Scope
        } 
        elseif ($_.HttpRequest.Method -ieq "DELETE") {
            $out.Action = "Revoked"
            if ($endEvent.Properties.Content.ContainsKey("responseBody")) {
                $messageBody = ConvertFrom-Json $endEvent.Properties.Content["responseBody"]
            }
        }

        if ($messageBody) {
            # Process principal details
            $out.PrincipalId = $messageBody.properties.principalId
            if ($out.PrincipalId -ne $null) { 
				# Get principal details by querying Graph. Cache principal details and read from cache if present
				$principalId = $out.PrincipalId 
                
				if($principalDetailsCache.ContainsKey($principalId)) {
					# Found in cache
                    $principalDetails = $principalDetailsCache[$principalId]
                } else { # not in cache
		            $principalDetails = "" | select Name, Type
                    $user = Get-AzureRmADUser -ObjectId $principalId
                    if ($user) {
                        $principalDetails.Name = $user.DisplayName
                        $principalDetails.Type = "User"    
                    } else {
                        $group = Get-AzureRmADGroup -ObjectId $principalId
                        if ($group) {
                            $principalDetails.Name = $group.DisplayName
                            $principalDetails.Type = "Group"        
                        } else {
                            $servicePrincipal = Get-AzureRmADServicePrincipal -objectId $principalId
                            if ($servicePrincipal) {
                                $principalDetails.Name = $servicePrincipal.DisplayName
                                $principalDetails.Type = "Service Principal"                        
                            }
                        }
                    }              
					# add principal details to cache
                    $principalDetailsCache.Add($principalId, $principalDetails);
	            }

                $out.PrincipalName = $principalDetails.Name
                $out.PrincipalType = $principalDetails.Type
            }

			# Process scope details
            if ([string]::IsNullOrEmpty($out.Scope)) { $out.Scope = $messageBody.properties.Scope }
            if ($out.Scope -ne $null) {
				# Remove the authorization provider details from the scope, if present
			    if ($out.Scope.ToLower().Contains("/providers/microsoft.authorization")) {
					$index = $out.Scope.ToLower().IndexOf("/providers/microsoft.authorization") 
					$out.Scope = $out.Scope.Substring(0, $index) 
				}

              	$scope = $out.Scope 
				$resourceDetails = "" | select Name, Type
                $scopeParts = $scope.Split('/', [System.StringSplitOptions]::RemoveEmptyEntries)
                $len = $scopeParts.Length

                if ($len -gt 0 -and $len -le 2 -and $scope.ToLower().Contains("subscriptions"))	{
                    $resourceDetails.Type = "Subscription"
                    $resourceDetails.Name  = $scopeParts[1]
                } elseif ($len -gt 0 -and $len -le 4 -and $scope.ToLower().Contains("resourcegroups")) {
                    $resourceDetails.Type = "Resource Group"
                    $resourceDetails.Name  = $scopeParts[3]
                    } elseif ($len -ge 6 -and $scope.ToLower().Contains("providers")) {
                        $resourceDetails.Type = "Resource"
                        $resourceDetails.Name  = $scopeParts[$len -1]
                        }
                
				$out.ScopeName = $resourceDetails.Name
                $out.ScopeType = $resourceDetails.Type
            }

			# Process Role definition details
            $out.RoleDefinitionId = $messageBody.properties.roleDefinitionId
            if ($out.RoleDefinitionId -ne $null) {
                if ($azureRoleDefinitionCache[$out.RoleDefinitionId]) {
                    $out.RoleName = $azureRoleDefinitionCache[$out.RoleDefinitionId].Name
                } else {
                    $out.RoleName = ""
                }
            }
        }
        $output += $out
    } # start event processing complete

    # Filter classic admins events
    $offlineEvents | % {
        if($_.Status -ne $null -and $_.Status -ieq "Succeeded" -and $_.OperationName -ne $null -and $_.operationName.StartsWith("Microsoft.Authorization/ClassicAdministrators", [System.StringComparison]::OrdinalIgnoreCase)) {
            
            $out = "" | select Timestamp, Caller, Action, PrincipalId, PrincipalName, PrincipalType, Scope, ScopeName, ScopeType, RoleDefinitionId, RoleName
            $out.Timestamp = Get-Date -Date $_.EventTimestamp -Format u
            $out.Caller = "Subscription Admin"

            if($_.operationName -ieq "Microsoft.Authorization/ClassicAdministrators/write"){
                $out.Action = "Granted"
            } 
            elseif($_.operationName -ieq "Microsoft.Authorization/ClassicAdministrators/delete"){
                $out.Action = "Revoked"
            }

            $out.RoleDefinitionId = $null
            $out.PrincipalId = $null
            $out.PrincipalType = "User"
            $out.Scope = "/subscriptions/" + $_.SubscriptionId
            $out.ScopeType = "Subscription"
            $out.ScopeName = $_.SubscriptionId
                                
            if($_.Properties -ne $null){
                $out.PrincipalName = $_.Properties.Content["adminEmail"]
                $out.RoleName = "Classic " + $_.Properties.Content["adminType"]
            }
                     
            $output += $out
        }
    } # end offline events

    $output | Sort Timestamp
} 
} # End commandlet
 

# SIG # Begin signature block
# MIIavwYJKoZIhvcNAQcCoIIasDCCGqwCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUhDrBInF+1t1vfhRo4+YNh7CT
# PwKgghWCMIIEwzCCA6ugAwIBAgITMwAAAI/XdhW5zUWKdAAAAAAAjzANBgkqhkiG
# 9w0BAQUFADB3MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4G
# A1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSEw
# HwYDVQQDExhNaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EwHhcNMTUxMDA3MTgxNDA1
# WhcNMTcwMTA3MTgxNDA1WjCBszELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hp
# bmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jw
# b3JhdGlvbjENMAsGA1UECxMETU9QUjEnMCUGA1UECxMebkNpcGhlciBEU0UgRVNO
# OkY1MjgtMzc3Ny04QTc2MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBT
# ZXJ2aWNlMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEApJcIvUZWGHH+
# aele5pKSdqAcDMEf+MDK6zGAo/MUX8dt5ALRy9KFMU4NHAGS8/l8obqAdrI09ogi
# +b45cokPhf4FSjH9FxnI4fKA5D1zvzqSSZv2Do/DPwTABn0gJDIEg98eWrfTfSiS
# BeIitCII4xYrcQzmLNdOhK7c9s4a297v2YoSsr6ywwsi2GCTR7lf639DQpvUewUe
# AgjS5difTzJOY6P1zaZhaLe3JBfQaD/XNwKRUHZ1gKpZHR6BKfSA1Qr2y8SIH6Sn
# joNP5g/i1SJLe8BFuwRukdEkASkPMlizTVWk0iKDCrq2K4Jqb4TIdC6ftxnlLLTQ
# 6o10Ggos3wIDAQABo4IBCTCCAQUwHQYDVR0OBBYEFECCgGhicp5gIAaY3xx6dqTg
# wjuHMB8GA1UdIwQYMBaAFCM0+NlSRnAK7UD7dvuzK7DDNbMPMFQGA1UdHwRNMEsw
# SaBHoEWGQ2h0dHA6Ly9jcmwubWljcm9zb2Z0LmNvbS9wa2kvY3JsL3Byb2R1Y3Rz
# L01pY3Jvc29mdFRpbWVTdGFtcFBDQS5jcmwwWAYIKwYBBQUHAQEETDBKMEgGCCsG
# AQUFBzAChjxodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpL2NlcnRzL01pY3Jv
# c29mdFRpbWVTdGFtcFBDQS5jcnQwEwYDVR0lBAwwCgYIKwYBBQUHAwgwDQYJKoZI
# hvcNAQEFBQADggEBAEsssyc5D24SUTSeGpvT+p4fpocAu/lqzyqP8UGZQRGOfj0E
# qbqVQ3lJFN6GJMJCw+eqHhOPo0GFEyIcaH9UQYiY25UVyiWgZo/2Pr/vFAV07uXh
# 3kXwLev3puvEHa+J2wKvuq/gxGiYcHV2/kL0ELdLf7neNhFiZGCoHuE0mf5lUSGA
# lhP5Ahd+nO9YVYaF7HwZbjxiMbGgsRVSMmxiErv6Q+yJmP1Wc41FQ7CWSzFtXa+G
# tYmWNLTVVcV1P17uOb7htXNacqn39uE1+ssJa9mlwT3SfHYSO5UNe4MwF9bdycSI
# Vc8pxNHdPbnKw3HKI/hWrjpyaa6pX/9CbGmdlNswggTsMIID1KADAgECAhMzAAAB
# Cix5rtd5e6asAAEAAAEKMA0GCSqGSIb3DQEBBQUAMHkxCzAJBgNVBAYTAlVTMRMw
# EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
# aWNyb3NvZnQgQ29ycG9yYXRpb24xIzAhBgNVBAMTGk1pY3Jvc29mdCBDb2RlIFNp
# Z25pbmcgUENBMB4XDTE1MDYwNDE3NDI0NVoXDTE2MDkwNDE3NDI0NVowgYMxCzAJ
# BgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25k
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xDTALBgNVBAsTBE1PUFIx
# HjAcBgNVBAMTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjCCASIwDQYJKoZIhvcNAQEB
# BQADggEPADCCAQoCggEBAJL8bza74QO5KNZG0aJhuqVG+2MWPi75R9LH7O3HmbEm
# UXW92swPBhQRpGwZnsBfTVSJ5E1Q2I3NoWGldxOaHKftDXT3p1Z56Cj3U9KxemPg
# 9ZSXt+zZR/hsPfMliLO8CsUEp458hUh2HGFGqhnEemKLwcI1qvtYb8VjC5NJMIEb
# e99/fE+0R21feByvtveWE1LvudFNOeVz3khOPBSqlw05zItR4VzRO/COZ+owYKlN
# Wp1DvdsjusAP10sQnZxN8FGihKrknKc91qPvChhIqPqxTqWYDku/8BTzAMiwSNZb
# /jjXiREtBbpDAk8iAJYlrX01boRoqyAYOCj+HKIQsaUCAwEAAaOCAWAwggFcMBMG
# A1UdJQQMMAoGCCsGAQUFBwMDMB0GA1UdDgQWBBSJ/gox6ibN5m3HkZG5lIyiGGE3
# NDBRBgNVHREESjBIpEYwRDENMAsGA1UECxMETU9QUjEzMDEGA1UEBRMqMzE1OTUr
# MDQwNzkzNTAtMTZmYS00YzYwLWI2YmYtOWQyYjFjZDA1OTg0MB8GA1UdIwQYMBaA
# FMsR6MrStBZYAck3LjMWFrlMmgofMFYGA1UdHwRPME0wS6BJoEeGRWh0dHA6Ly9j
# cmwubWljcm9zb2Z0LmNvbS9wa2kvY3JsL3Byb2R1Y3RzL01pY0NvZFNpZ1BDQV8w
# OC0zMS0yMDEwLmNybDBaBggrBgEFBQcBAQROMEwwSgYIKwYBBQUHMAKGPmh0dHA6
# Ly93d3cubWljcm9zb2Z0LmNvbS9wa2kvY2VydHMvTWljQ29kU2lnUENBXzA4LTMx
# LTIwMTAuY3J0MA0GCSqGSIb3DQEBBQUAA4IBAQCmqFOR3zsB/mFdBlrrZvAM2PfZ
# hNMAUQ4Q0aTRFyjnjDM4K9hDxgOLdeszkvSp4mf9AtulHU5DRV0bSePgTxbwfo/w
# iBHKgq2k+6apX/WXYMh7xL98m2ntH4LB8c2OeEti9dcNHNdTEtaWUu81vRmOoECT
# oQqlLRacwkZ0COvb9NilSTZUEhFVA7N7FvtH/vto/MBFXOI/Enkzou+Cxd5AGQfu
# FcUKm1kFQanQl56BngNb/ErjGi4FrFBHL4z6edgeIPgF+ylrGBT6cgS3C6eaZOwR
# XU9FSY0pGi370LYJU180lOAWxLnqczXoV+/h6xbDGMcGszvPYYTitkSJlKOGMIIF
# vDCCA6SgAwIBAgIKYTMmGgAAAAAAMTANBgkqhkiG9w0BAQUFADBfMRMwEQYKCZIm
# iZPyLGQBGRYDY29tMRkwFwYKCZImiZPyLGQBGRYJbWljcm9zb2Z0MS0wKwYDVQQD
# EyRNaWNyb3NvZnQgUm9vdCBDZXJ0aWZpY2F0ZSBBdXRob3JpdHkwHhcNMTAwODMx
# MjIxOTMyWhcNMjAwODMxMjIyOTMyWjB5MQswCQYDVQQGEwJVUzETMBEGA1UECBMK
# V2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0
# IENvcnBvcmF0aW9uMSMwIQYDVQQDExpNaWNyb3NvZnQgQ29kZSBTaWduaW5nIFBD
# QTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBALJyWVwZMGS/HZpgICBC
# mXZTbD4b1m/My/Hqa/6XFhDg3zp0gxq3L6Ay7P/ewkJOI9VyANs1VwqJyq4gSfTw
# aKxNS42lvXlLcZtHB9r9Jd+ddYjPqnNEf9eB2/O98jakyVxF3K+tPeAoaJcap6Vy
# c1bxF5Tk/TWUcqDWdl8ed0WDhTgW0HNbBbpnUo2lsmkv2hkL/pJ0KeJ2L1TdFDBZ
# +NKNYv3LyV9GMVC5JxPkQDDPcikQKCLHN049oDI9kM2hOAaFXE5WgigqBTK3S9dP
# Y+fSLWLxRT3nrAgA9kahntFbjCZT6HqqSvJGzzc8OJ60d1ylF56NyxGPVjzBrAlf
# A9MCAwEAAaOCAV4wggFaMA8GA1UdEwEB/wQFMAMBAf8wHQYDVR0OBBYEFMsR6MrS
# tBZYAck3LjMWFrlMmgofMAsGA1UdDwQEAwIBhjASBgkrBgEEAYI3FQEEBQIDAQAB
# MCMGCSsGAQQBgjcVAgQWBBT90TFO0yaKleGYYDuoMW+mPLzYLTAZBgkrBgEEAYI3
# FAIEDB4KAFMAdQBiAEMAQTAfBgNVHSMEGDAWgBQOrIJgQFYnl+UlE/wq4QpTlVnk
# pDBQBgNVHR8ESTBHMEWgQ6BBhj9odHRwOi8vY3JsLm1pY3Jvc29mdC5jb20vcGtp
# L2NybC9wcm9kdWN0cy9taWNyb3NvZnRyb290Y2VydC5jcmwwVAYIKwYBBQUHAQEE
# SDBGMEQGCCsGAQUFBzAChjhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpL2Nl
# cnRzL01pY3Jvc29mdFJvb3RDZXJ0LmNydDANBgkqhkiG9w0BAQUFAAOCAgEAWTk+
# fyZGr+tvQLEytWrrDi9uqEn361917Uw7LddDrQv+y+ktMaMjzHxQmIAhXaw9L0y6
# oqhWnONwu7i0+Hm1SXL3PupBf8rhDBdpy6WcIC36C1DEVs0t40rSvHDnqA2iA6VW
# 4LiKS1fylUKc8fPv7uOGHzQ8uFaa8FMjhSqkghyT4pQHHfLiTviMocroE6WRTsgb
# 0o9ylSpxbZsa+BzwU9ZnzCL/XB3Nooy9J7J5Y1ZEolHN+emjWFbdmwJFRC9f9Nqu
# 1IIybvyklRPk62nnqaIsvsgrEA5ljpnb9aL6EiYJZTiU8XofSrvR4Vbo0HiWGFzJ
# NRZf3ZMdSY4tvq00RBzuEBUaAF3dNVshzpjHCe6FDoxPbQ4TTj18KUicctHzbMrB
# 7HCjV5JXfZSNoBtIA1r3z6NnCnSlNu0tLxfI5nI3EvRvsTxngvlSso0zFmUeDord
# EN5k9G/ORtTTF+l5xAS00/ss3x+KnqwK+xMnQK3k+eGpf0a7B2BHZWBATrBC7E7t
# s3Z52Ao0CW0cgDEf4g5U3eWh++VHEK1kmP9QFi58vwUheuKVQSdpw5OPlcmN2Jsh
# rg1cnPCiroZogwxqLbt2awAdlq3yFnv2FoMkuYjPaqhHMS+a3ONxPdcAfmJH0c6I
# ybgY+g5yjcGjPa8CQGr/aZuW4hCoELQ3UAjWwz0wggYHMIID76ADAgECAgphFmg0
# AAAAAAAcMA0GCSqGSIb3DQEBBQUAMF8xEzARBgoJkiaJk/IsZAEZFgNjb20xGTAX
# BgoJkiaJk/IsZAEZFgltaWNyb3NvZnQxLTArBgNVBAMTJE1pY3Jvc29mdCBSb290
# IENlcnRpZmljYXRlIEF1dGhvcml0eTAeFw0wNzA0MDMxMjUzMDlaFw0yMTA0MDMx
# MzAzMDlaMHcxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYD
# VQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xITAf
# BgNVBAMTGE1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQTCCASIwDQYJKoZIhvcNAQEB
# BQADggEPADCCAQoCggEBAJ+hbLHf20iSKnxrLhnhveLjxZlRI1Ctzt0YTiQP7tGn
# 0UytdDAgEesH1VSVFUmUG0KSrphcMCbaAGvoe73siQcP9w4EmPCJzB/LMySHnfL0
# Zxws/HvniB3q506jocEjU8qN+kXPCdBer9CwQgSi+aZsk2fXKNxGU7CG0OUoRi4n
# rIZPVVIM5AMs+2qQkDBuh/NZMJ36ftaXs+ghl3740hPzCLdTbVK0RZCfSABKR2YR
# JylmqJfk0waBSqL5hKcRRxQJgp+E7VV4/gGaHVAIhQAQMEbtt94jRrvELVSfrx54
# QTF3zJvfO4OToWECtR0Nsfz3m7IBziJLVP/5BcPCIAsCAwEAAaOCAaswggGnMA8G
# A1UdEwEB/wQFMAMBAf8wHQYDVR0OBBYEFCM0+NlSRnAK7UD7dvuzK7DDNbMPMAsG
# A1UdDwQEAwIBhjAQBgkrBgEEAYI3FQEEAwIBADCBmAYDVR0jBIGQMIGNgBQOrIJg
# QFYnl+UlE/wq4QpTlVnkpKFjpGEwXzETMBEGCgmSJomT8ixkARkWA2NvbTEZMBcG
# CgmSJomT8ixkARkWCW1pY3Jvc29mdDEtMCsGA1UEAxMkTWljcm9zb2Z0IFJvb3Qg
# Q2VydGlmaWNhdGUgQXV0aG9yaXR5ghB5rRahSqClrUxzWPQHEy5lMFAGA1UdHwRJ
# MEcwRaBDoEGGP2h0dHA6Ly9jcmwubWljcm9zb2Z0LmNvbS9wa2kvY3JsL3Byb2R1
# Y3RzL21pY3Jvc29mdHJvb3RjZXJ0LmNybDBUBggrBgEFBQcBAQRIMEYwRAYIKwYB
# BQUHMAKGOGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2kvY2VydHMvTWljcm9z
# b2Z0Um9vdENlcnQuY3J0MBMGA1UdJQQMMAoGCCsGAQUFBwMIMA0GCSqGSIb3DQEB
# BQUAA4ICAQAQl4rDXANENt3ptK132855UU0BsS50cVttDBOrzr57j7gu1BKijG1i
# uFcCy04gE1CZ3XpA4le7r1iaHOEdAYasu3jyi9DsOwHu4r6PCgXIjUji8FMV3U+r
# kuTnjWrVgMHmlPIGL4UD6ZEqJCJw+/b85HiZLg33B+JwvBhOnY5rCnKVuKE5nGct
# xVEO6mJcPxaYiyA/4gcaMvnMMUp2MT0rcgvI6nA9/4UKE9/CCmGO8Ne4F+tOi3/F
# NSteo7/rvH0LQnvUU3Ih7jDKu3hlXFsBFwoUDtLaFJj1PLlmWLMtL+f5hYbMUVbo
# nXCUbKw5TNT2eb+qGHpiKe+imyk0BncaYsk9Hm0fgvALxyy7z0Oz5fnsfbXjpKh0
# NbhOxXEjEiZ2CzxSjHFaRkMUvLOzsE1nyJ9C/4B5IYCeFTBm6EISXhrIniIh0EPp
# K+m79EjMLNTYMoBMJipIJF9a6lbvpt6Znco6b72BJ3QGEe52Ib+bgsEnVLaxaj2J
# oXZhtG6hE6a/qkfwEm/9ijJssv7fUciMI8lmvZ0dhxJkAj0tr1mPuOQh5bWwymO0
# eFQF1EEuUKyUsKV4q7OglnUa2ZKHE3UiLzKoCG6gW4wlv6DvhMoh1useT8ma7kng
# 9wFlb4kLfchpyOZu6qeXzjEp/w7FW1zYTRuh2Povnj8uVRZryROj/TGCBKcwggSj
# AgEBMIGQMHkxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYD
# VQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xIzAh
# BgNVBAMTGk1pY3Jvc29mdCBDb2RlIFNpZ25pbmcgUENBAhMzAAABCix5rtd5e6as
# AAEAAAEKMAkGBSsOAwIaBQCggcAwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQw
# HAYKKwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFFM7
# /qA3lQCT8md14Jn9py1l7VUuMGAGCisGAQQBgjcCAQwxUjBQoDaANABNAGkAYwBy
# AG8AcwBvAGYAdAAgAEEAegB1AHIAZQAgAFAAbwB3AGUAcgBTAGgAZQBsAGyhFoAU
# aHR0cDovL0NvZGVTaWduSW5mbyAwDQYJKoZIhvcNAQEBBQAEggEADWwrvEq0kusQ
# byAKsdhMVPHqVjNC2UNR/iar5/M0vsjE8L89tKgpeaTVeXXq/31D5WNsgjVcabKt
# wVEJAQ2THpncc5QFXTJ2WZo7bBci1zzLL22fQt6yXohLniSY1pAK82csDDQ28uTD
# DqZclIPYaQ0zgrXNptgKpNEqxwkVEQGWOJr9MVIBiPPRo/Smvy5SoohzTY8EeTEk
# cRurE4J5jJbG2ZO1JWseOLgwOSRMXGHPriVNtZ1Ins2FXiKEIt/ChhHakqFjqTR6
# 8sPxdGcoe90njh5xlFysQjzBoBHJuGJ4tRoyTRmSmYhyEd39y+BR0YDMIDnUjvF4
# MbNfbKXBOaGCAigwggIkBgkqhkiG9w0BCQYxggIVMIICEQIBATCBjjB3MQswCQYD
# VQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEe
# MBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSEwHwYDVQQDExhNaWNyb3Nv
# ZnQgVGltZS1TdGFtcCBQQ0ECEzMAAACP13YVuc1FinQAAAAAAI8wCQYFKw4DAhoF
# AKBdMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTE1
# MTIxNjA4MTIzOVowIwYJKoZIhvcNAQkEMRYEFOBPcwrx8GbhPFc3pAeawVY0s7CB
# MA0GCSqGSIb3DQEBBQUABIIBAAkIA7IeCpeoisr0WuFCDSpbYi+O3S516DDEmYMN
# FAbmiqOad15HExFYDR+YP7ATBac1rRAop30H/RFOF1euMdJCg19BpOdpjZ6UTNnQ
# 2UROeYD8e1ceY4Swc7QSlK+rCG4mpuaQf24aHmfJ0bj2JtuW5tzR9+bUC8fQO9Yz
# 5CAw+N8I67MZp9Q4Kmw6I9ltsS+OFdHc3Loahn0cCvzA+8e0BpGZQJ3ycR7L3jQc
# sMR1MND+AQ7NibxD1aUX38avTKwtg+abJ+OMdfs0iEUnOOIGaHeT9rj1o2EX9FHC
# nQfEAiU2M9zaSFzyL5b+gKrhzt4DGrJXdCbiK8skkqouN78=
# SIG # End signature block
