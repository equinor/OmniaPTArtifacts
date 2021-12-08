<#
.SYNOPSIS
 Wrapper script for start & stop Classic VM's
.DESCRIPTION
 Wrapper script for start & stop Classic VM's
.EXAMPLE
.\ScheduledStartStop_Child_Classic.ps1 -VMName "Value1" -Action "Value2" -ResourceGroupName "Value3"
Version History
v1.0   - Initial Release
#>
param(
    [string]$VMName = $(throw 'Value for VMName is missing'),
    [String]$Action = $(throw 'Value for Action is missing'),
    [String]$ResourceGroupName = $(throw 'Value for ResourceGroupName is missing')
)

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

        #Generate the access token

        Write-Output 'Generating access token...'

        #$context = Get-AzContext

        $SubscriptionId = $context.Subscription

        $cache = $context.TokenCache

        $cacheItem = $cache.ReadItems()

        $AccessToken = $cacheItem[$cacheItem.Count - 1].AccessToken

        $headerParams = @{'Authorization' = "Bearer $AccessToken" }

        Write-Output "VM action is : $($Action)"

        $ClassicVM = Search-AzGraph -Query "Resources | where type =~ 'Microsoft.ClassicCompute/virtualMachines' | where name == '$($VMName)'"

        $ResourceGroupName = $ClassicVM.resourceGroup

        if ($Action.Trim().ToLower() -eq 'stop') {
            $uriclassicDeallocate = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.ClassicCompute/virtualMachines/$VMName/shutdown?api-version=2015-10-01"

            Write-Output "API url : $($uriclassicDeallocate)"

            Write-Output "Stopping the VM : $($VMName) using API..."

            $results = Invoke-RestMethod -Uri $uriclassicDeallocate -Headers $headerParams -Method POST

            Write-Output "Successfully stopped the VM $($VMName)"

        } elseif ($Action.Trim().ToLower() -eq 'start') {

            $uriclassicStart = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.ClassicCompute/virtualMachines/$VMName/start?api-version=2017-04-01"

            Write-Output "API url : $($uriclassicStart)"

            Write-Output "Starting the VM : $($VMName) using API..."

            $results = Invoke-RestMethod -Uri $uriclassicStart -Headers $headerParams -Method POST

            Write-Output "Successfully started the VM $($VMName)"
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
