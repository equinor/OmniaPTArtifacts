<#
.SYNOPSIS
 Script to stop the Azure ARM VM via AutoStop based scenario on CPU % utilization
.DESCRIPTION
 Script to stop the Azure ARM VM via AutoStop based scenario on CPU % utilization
.EXAMPLE
.\AutoStop_VM_Child_ARM.ps1
Version History
v1.0 - Initial Release
#>

param
(
    [Parameter (Mandatory = $false)]
    [object] $WebHookData
)

# If runbook was called from Webhook, WebhookData will not be null.
if ($WebHookData) {

    if (-Not $WebHookData.RequestBody ) {
        Write-Output 'No request body from test pane'

        $WebhookData = (ConvertFrom-Json -InputObject $WebhookData)

        $rbody = (ConvertFrom-Json -InputObject $WebhookData.RequestBody)

        $context = [object]$rbody.data.context
        Write-Output "Alert Name = $($context.name)"
        Write-Output "RG Name = $($context.resourceGroupName)"
        Write-Output "VM Name = $($context.resourceName)"

        exit
    }

    # Retrieve VMs from Webhook request body
    #$WebhookData = (ConvertFrom-JSON -InputObject $WebhookData -ErrorAction SilentlyContinue)

    $rbody = (ConvertFrom-Json -InputObject $WebhookData.RequestBody)

    $context = [object]$rbody.data.context

    Write-Output "`nALERT CONTEXT DATA"
    Write-Output '==================='
    Write-Output "Subscription Id : $($context.subscriptionId)"
    Write-Output "VM alert name : $($context.name)"
    Write-Output "VM ResourceGroup Name : $($context.resourceGroupName)"
    Write-Output "VM name : $($context.resourceName)"
    Write-Output "VM type : $($context.resourceType)"
    Write-Output "Resource Id : $($context.resourceId)"
    Write-Output "Timestamp : $($context.timestamp)"

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
            # Get the connection "AzureRunAsConnection "
            #$servicePrincipalConnection=Get-AutomationConnection -Name $connectionName

            #Add-AzAccount `
            #    -ServicePrincipal `
            #    -TenantId $servicePrincipalConnection.TenantId `
            #    -ApplicationId $servicePrincipalConnection.ApplicationId `
            #    -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint

            Connect-AzAccount -Identity

            $Context = Get-AzContext
            $Context

            Write-Output 'Successfully logged into Azure subscription using Az cmdlets...'

            if ($context.resourceType -eq 'Microsoft.Compute/virtualMachines') {
                Write-Output "~$($context.resourceName)"

                Write-Output "Stopping Virtual Machine : $($context.resourceName)"

                $Status = Stop-AzVM -Name $context.resourceName -ResourceGroupName $context.resourceGroupName -Force

                if ($Status -eq $null) {
                    Write-Output "Error occurred while stopping the Virtual Machine $($context.resourceName) hence retrying..."

                    if ($Attempt -gt $RetryCount) {
                        Write-Output "Reached the max $RetryCount retry attempts so please resubmit the job later..."

                        $RetryFlag = $false
                    } else {
                        Write-Output "[$Attempt/$RetryCount] Retrying in $TimeoutInSecs seconds..."

                        Start-Sleep -Seconds $TimeoutInSecs

                        $Attempt = $Attempt + 1

                        $RetryFlag = $true
                    }
                } else {
                    Write-Output "Successfully stopped the Virtual Machine : $($context.resourceName)"

                    Write-Output "$context.resourceName"

                    $RetryFlag = $false
                }
            }

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
    # Error
    Write-Error 'This runbook is meant to be started from an Azure alert webhook only.'
}
