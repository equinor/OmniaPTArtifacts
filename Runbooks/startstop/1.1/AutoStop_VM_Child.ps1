﻿<#
.SYNOPSIS
 Script to stop the Azure Classic VM via AutoStop based scenario on CPU % utilization
.DESCRIPTION
 Script to stop the Azure Classic VM via AutoStop based scenario on CPU % utilization
.EXAMPLE
.\AutoStop_VM_Child.ps1
Version History
v1.0 - Initial Release
#>

param (
    [object]$WebhookData
)

if ($null -ne $WebhookData) {
    # Collect properties of WebhookData.
    $WebhookName = $WebhookData.WebhookName
    $WebhookBody = $WebhookData.RequestBody
    $WebhookHeaders = $WebhookData.RequestHeader

    # Information on the webhook name that called This
    Write-Output "This runbook was started from webhook $WebhookName."

    # Obtain the WebhookBody containing the AlertContext
    $WebhookBody = (ConvertFrom-Json -InputObject $WebhookBody)
    Write-Output "`nWEBHOOK BODY"
    Write-Output '============='
    Write-Output $WebhookBody

    # Obtain the AlertContext
    $AlertContext = [object]$WebhookBody.context

    # Some selected AlertContext information
    Write-Output "`nALERT CONTEXT DATA"
    Write-Output '==================='
    Write-Output "Subscription Id : $($AlertContext.subscriptionId)"
    Write-Output "VM alert name : $($AlertContext.name)"
    Write-Output "VM ResourceGroup Name : $($AlertContext.resourceGroupName)"
    Write-Output "VM name : $($AlertContext.resourceName)"
    Write-Output "VM type : $($AlertContext.resourceType)"
    Write-Output "Resource Id : $($AlertContext.resourceId)"
    Write-Output "Timestamp : $($AlertContext.timestamp)"

    [string] $FailureMessage = 'Failed to execute the command'
    [int] $RetryCount = 3
    [int] $TimeoutInSecs = 20
    $RetryFlag = $true
    $Attempt = 1
    do {
        #----------------------------------------------------------------------------------
        #---------------------LOGIN TO AZURE AND SELECT THE SUBSCRIPTION-------------------
        #----------------------------------------------------------------------------------

        Write-Output 'Logging into Azure subscription using Az cmdlets...'
        $connectionName = 'AzureRunAsConnection'
        try {
            Connect-AzAccount -Identity

            $Context = Get-AzContext
            $Context

            Write-Output 'Successfully logged into Azure subscription using Az cmdlets...'

            #Flag for CSP subs
            $enableClassicVMs = Get-AutomationVariable -Name 'External_EnableClassicVMs'

            #Generate the access token

            Write-Output 'Generating the access token...'

            $context = Get-AzContext

            $SubscriptionId = $context.Subscription

            $cache = $context.TokenCache

            $cacheItem = $cache.ReadItems()

            $AccessToken = $cacheItem[$cacheItem.Count - 1].AccessToken

            $headerParams = @{'Authorization' = "Bearer $AccessToken" }

            $uriclassicDeallocate = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$($AlertContext.resourceGroupName)/providers/Microsoft.ClassicCompute/virtualMachines/$($AlertContext.resourceName)/shutdown?api-version=2015-10-01"

            Write-Output "API url : $($uriclassicDeallocate)"

            Write-Output "~Attempted the stop action on the following VM(s): $($AlertContext.resourceName)"

            if (($AlertContext.resourceType -eq 'microsoft.classiccompute/virtualmachines') -and ($enableClassicVMs)) {
                Write-Output 'Taking action stop on VM using API...'

                $results = Invoke-RestMethod -Uri $uriclassicDeallocate -Headers $headerParams -Method POST

                Write-Output "Successfully stopped the VM $($AlertContext.resourceName)"
            } else {
                Write-Output 'Please check whether classic VM asset variable (External_EnableClassicVMs) is set to True...'
            }

            $RetryFlag = $false
        } catch {
            if (!$Context) {
                $ErrorMessage = "Connection $connectionName not found."

                $RetryFlag = $false

                throw $ErrorMessage
            }

            if ($Attempt -gt $RetryCount) {
                Write-Output "$FailureMessage! Total retry attempts: $RetryCount"

                Write-Output "[Error Message] $($_.exception.message) `n"

                $RetryFlag = $false
            } else {
                Write-Output "[$Attempt/$RetryCount] $FailureMessage. Retrying in $TimeoutInSecs seconds..."

                Start-Sleep -Seconds $TimeoutInSecs

                $Attempt = $Attempt + 1
            }
        }

    }
    while ($RetryFlag)
} else {
    Write-Error 'This runbook is meant to only be started from a webhook.'
}
