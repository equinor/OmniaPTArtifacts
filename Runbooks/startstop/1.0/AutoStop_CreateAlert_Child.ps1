<#
.SYNOPSIS
 Child runbook for AutoStop scenario to create alerts (both classic and V2 ARM alerts) for the given VMs
.DESCRIPTION
 Child runbook for AutoStop scenario to create alerts (both classic and V2 ARM alerts) for the given VMs
.EXAMPLE
.\AutoStop_CreateAlert_Child.ps1 -VMObject "VM" -AlertAction "Create" -WebhookUri "url"
Version History
v1.0   - Initial Release
v2.0   - Added classic support
#>
param(
    $VMObject,
    [string]$AlertAction,
    [string]$WebhookUri
)


#-----Function to generate unique alert name-----
function Generate-AlertName {
    param ([string] $OldAlertName ,
        [string] $VMName)

    [string[]] $AlertSplit = $OldAlertName -split '-'
    [int] $Number = $AlertSplit[$AlertSplit.Length - 1]
    $Number++
    $Newalertname = "Alert-$($VMName)-$Number"
    return $Newalertname
}

# ------------------Execution Entry point ---------------------

Import-Module Az.Monitor

[string] $FailureMessage = 'Failed to execute the command'
[int] $RetryCount = 3
[int] $TimeoutInSecs = 20
$RetryFlag = $true
$Attempt = 1
do {
    Write-Output 'Logging into Azure subscription using Az cmdlets...'
    #-----L O G I N - A U T H E N T I C A T I O N-----
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

#---------Read all the input variables---------------
$SubId = Get-AutomationVariable -Name 'Internal_AzureSubscriptionId'
$aroResourceGroupName = Get-AutomationVariable -Name 'Internal_ResourceGroupName'

#Flag for CSP subs
$enableClassicVMs = Get-AutomationVariable -Name 'External_EnableClassicVMs'

#-----Prepare the inputs for alert attributes-----
$threshold = Get-AutomationVariable -Name 'External_AutoStop_Threshold'
$metricName = Get-AutomationVariable -Name 'External_AutoStop_MetricName'
$timeWindow = Get-AutomationVariable -Name 'External_AutoStop_TimeWindow'
$condition = Get-AutomationVariable -Name 'External_AutoStop_Condition' # Other valid values are LessThanOrEqual, GreaterThan, GreaterThanOrEqual
$description = Get-AutomationVariable -Name 'External_AutoStop_Description'
$timeAggregationOperator = Get-AutomationVariable -Name 'External_AutoStop_TimeAggregationOperator'
$frequency = Get-AutomationVariable -Name 'External_AutoStop_Frequency'
$severity = Get-AutomationVariable -Name 'External_AutoStop_Severity'
$webhookUri = Get-AutomationVariable -Name 'Internal_AutoSnooze_WebhookUri'
$webhookARMUri = Get-AutomationVariable -Name 'Internal_AutoSnooze_ARM_WebhookUri'


try {
    Write-Output 'Runbook execution started...'
    $ResourceGroupName = $VMObject.ResourceGroupName
    $Location = $VMObject.Location

    Write-Output "Location...$($VMObject.Location)"

    Write-Output 'getting status...'

    $NewAlertName = "Alert-$($VMObject.Name)-1"

    if (($VMObject.Type -eq 'Classic') -and ($enableClassicVMs)) {
        #Processing the alerts for Classy vms
        #Get the classic VM asset using azure resource graph to get the cloudservice names
        $AllClassicVMs = Search-AzGraph -Query "Resources | where type =~ 'Microsoft.ClassicCompute/virtualMachines'"

        $currentVM = $AllClassicVMs | Where-Object Name -EQ $VMObject.Name -ErrorAction SilentlyContinue

        $VMState = $currentVM.properties.instanceView.powerState

        $resourceId = "/subscriptions/$($SubId)/resourceGroups/$ResourceGroupName/providers/Microsoft.ClassicCompute/virtualMachines/$($VMObject.Name.Trim())"

        Write-Output "Processing VM ($($VMObject.Name))"

        Write-Output "Current VM state is ($($VMState))"

        $actionWebhook = New-AzAlertRuleWebhook -ServiceUri $WebhookUri

        if ($AlertAction -eq 'Disable') {
            $ExVMAlerts = Get-AzAlertRule -ResourceGroup $VMObject.ResourceGroupName -DetailedOutput -ErrorAction SilentlyContinue

            if ($ExVMAlerts -ne $null) {
                Write-Output 'Checking for any previous alert(s)...'
                #Alerts exists so disable alert
                foreach ($Alert in $ExVMAlerts) {

                    if ($Alert.Name.ToLower().Contains($($VMObject.Name.ToLower().Trim()))) {
                        Write-Output "Previous alert ($($Alert.Name)) found and disabling now..."
                        Add-AzMetricAlertRule -Name $Alert.Name `
                            -Location $Alert.Location `
                            -ResourceGroupName $ResourceGroupName `
                            -TargetResourceId $resourceId `
                            -MetricName $metricName `
                            -Operator $condition `
                            -Threshold $threshold `
                            -WindowSize $timeWindow `
                            -TimeAggregationOperator $timeAggregationOperator `
                            -Action $actionWebhook `
                            -Description $description -DisableRule

                        Write-Output "Alert ($($Alert.Name)) Disabled for VM $($VMObject.Name)"

                    }
                }

            }
        } elseif ($AlertAction -eq 'Create') {
            #Getting ResourcegroupName and Location based on VM

            #if (($VMState -eq 'PowerState/running') -or ($VMState -eq 'ReadyRole'))
            #{
            Write-Output 'Creating alerts...'
            $VMAlerts = Get-AzAlertRule -ResourceGroupName $ResourceGroupName -DetailedOutput -ErrorAction SilentlyContinue

            #Check if alerts exists and take action
            if ($VMAlerts -ne $null) {
                Write-Output 'Checking for any previous alert(s)...'
                #Alerts exists so delete and re-create the new alert
                foreach ($Alert in $VMAlerts) {

                    if ($Alert.Name.ToLower().Contains($($VMObject.Name.ToLower().Trim()))) {
                        Write-Output "Previous alert ($($Alert.Name)) found and deleting now..."
                        #Remove the old alert
                        Remove-AzAlertRule -Name $Alert.Name -ResourceGroupName $ResourceGroupName

                        #Wait for few seconds to make sure it processed
                        Do {
                            #Start-Sleep 10
                            $GetAlert = Get-AzAlertRule -ResourceGroupName $ResourceGroupName -Name $Alert.Name -DetailedOutput -ErrorAction SilentlyContinue
                        }
                        while ($GetAlert -ne $null)

                        Write-Output 'Generating a new alert with unique name...'
                        #Now generate new unique alert name
                        $NewAlertName = Generate-AlertName -OldAlertName $Alert.Name -VMName $VMObject.Name
                    }
                }

            }
            #Alert does not exist, so create new alert
            Write-Output $NewAlertName

            Write-Output 'Adding a new alert to the VM...'

            Add-AzMetricAlertRule -Name $NewAlertName `
                -Location $location `
                -ResourceGroupName $ResourceGroupName `
                -TargetResourceId $resourceId `
                -MetricName $metricName `
                -Operator $condition `
                -Threshold $threshold `
                -WindowSize $timeWindow `
                -TimeAggregationOperator $timeAggregationOperator `
                -Action $actionWebhook `
                -Description $description


            Write-Output "Alert Created for VM $($VMObject.Name.Trim())"
        }
    } else {
        #Processing the alerts for ARM vms
        $VMState = (Get-AzVM -ResourceGroupName $VMObject.ResourceGroupName -Name $VMObject.Name -Status -ErrorAction SilentlyContinue).Statuses[1].Code

        $resourceId = "/subscriptions/$($SubId)/resourceGroups/$($ResourceGroupName)/providers/Microsoft.Compute/virtualMachines/$($VMObject.Name.Trim())"

        Write-Output "Processing VM ($($VMObject.Name))"

        Write-Output "Current VM state is ($($VMState))"


        $actionWebhookArm = New-AzAlertRuleWebhook -ServiceUri $webhookARMUri

        if ($AlertAction -eq 'Disable') {
            $ExVMAlerts = Get-AzMetricAlertRuleV2 -ResourceGroupName $VMObject.ResourceGroupName -ErrorAction SilentlyContinue

            if ($ExVMAlerts -ne $null) {
                Write-Output 'Checking for any previous alert(s)...'
                #Alerts exists so disable alert
                foreach ($Alert in $ExVMAlerts) {
                    if ($Alert.Name.ToLower().Contains($($VMObject.Name.ToLower().Trim()))) {
                        Write-Output "Previous alert ($($Alert.Name)) found and disabling now..."

                        Get-AzMetricAlertRuleV2 -ResourceGroupName $ResourceGroupName -Name $Alert.Name | Add-AzMetricAlertRuleV2 -DisableRule

                        Write-Output "Alert ($($Alert.Name)) Disabled for VM $($VMObject.Name)"
                    }
                }
            }
        } elseif ($AlertAction -eq 'Create') {
            Write-Output 'Creating alerts...'
            $VMAlerts = Get-AzMetricAlertRuleV2 -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue

            #Check if alerts exists and take action
            if ($VMAlerts -ne $null) {
                Write-Output 'Checking for any previous alert(s)...'
                #Alerts exists so delete and re-create the new alert
                foreach ($Alert in $VMAlerts) {

                    if ($Alert.Name.ToLower().Contains($($VMObject.Name.ToLower().Trim()))) {
                        Write-Output "Previous alert ($($Alert.Name)) found and deleting now..."
                        #Remove the old alert
                        Remove-AzMetricAlertRuleV2 -Name $Alert.Name -ResourceGroupName $ResourceGroupName

                        #Wait for few seconds to make sure it processed
                        Do {
                            #Start-Sleep 10
                            $GetAlert = Get-AzMetricAlertRuleV2 -ResourceGroupName $ResourceGroupName -Name $Alert.Name -ErrorAction SilentlyContinue
                        }
                        while ($GetAlert -ne $null)

                        Write-Output 'Generating a new alert with unique name...'
                        #Now generate new unique alert name
                        $NewAlertName = Generate-AlertName -OldAlertName $Alert.Name -VMName $VMObject.Name
                    }
                }

            }

            #Alert does not exist, so create new alert
            Write-Output $NewAlertName

            Write-Output 'Adding a new alert to the VM...'

            #Creating ARM alert is multi-step process.

            #1. Check for existing action group first and reuse if not else Create the Action group receiver and Action group.

            $actionGroup = New-Object Microsoft.Azure.Management.Monitor.Models.ActivityLogAlertActionGroup -ErrorAction SilentlyContinue

            $actionGroupName = 'StSt_AutoStop_AG_ARM-' + $aroResourceGroupName

            $actionGroupShortName = 'AutoStopAG'

            $actionGroup = Get-AzActionGroup -Name $actionGroupName -ResourceGroupName $aroResourceGroupName -ErrorAction SilentlyContinue

            if ($actionGroup -eq $null) {
                #1a Create the webhook receiver
                $webhookReceiverName = 'AutoStop_VM_WebhookReceiver_ARM'
                $webhookReceiver = New-AzActionGroupReceiver -Name $webhookReceiverName -WebhookReceiver -ServiceUri $webhookARMUri

                #1b Create the action group
                Set-AzActionGroup -Name $actionGroupName -ResourceGroupName $aroResourceGroupName -ShortName $actionGroupShortName -Receiver $webhookReceiver
                $actionGroup = Get-AzActionGroup -Name $actionGroupName -ResourceGroupName $aroResourceGroupName
            }

            #2 Create the action groupId
            $actionGroupId = New-AzActionGroup -ActionGroupId $actionGroup.Id

            #3 Create the condition/criteria
            $criteria = New-AzMetricAlertRuleV2Criteria -MetricName $metricName -MetricNamespace 'Microsoft.Compute/virtualMachines' -TimeAggregation $timeAggregationOperator -Operator $condition -Threshold $threshold

            #4 Now create the ARM metric alert

            Add-AzMetricAlertRuleV2 -Name $NewAlertName -ResourceGroupName $ResourceGroupName -WindowSize $timeWindow -Frequency $frequency `
                -TargetResourceId $resourceId -Condition $criteria -ActionGroup $actionGroupId -Severity $severity -Description $description


            Write-Output "Alert Created for VM $($VMObject.Name.Trim())"
        }
    }
} catch {
    Write-Output 'Error Occurred'
    Write-Output $_.Exception
}
