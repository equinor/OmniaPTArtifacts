<#
.SYNOPSIS
    This runbook used to perform action start or stop in classic VM group by Cloud Services
.DESCRIPTION
    This runbook used to perform action start or stop in classic VM group by Cloud Services
    This runbook requires the Azure Automation Run-As (Service Principle) account, which must be added when creating the Azure Automation account.
 .EXAMPLE
    .\ScheduledStartStop_Base_Classic.ps1 -CloudServiceName "Value1" -Action "Value2" -VMList "VM1,VM2,VM3"

#>

Param(
    [Parameter(Mandatory = $true, HelpMessage = 'Enter the value for CloudService.')][String]$CloudServiceName,
    [Parameter(Mandatory = $true, HelpMessage = 'Enter the value for Action. Values can be either start or stop')][String]$Action,
    [Parameter(Mandatory = $false, HelpMessage = 'Enter the VMs separated by comma(,)')][string]$VMList
)

function ScheduleSnoozeClassicAction ([string]$CloudServiceName, [string]$VMName, [string]$Action) {

    if ($Action.ToLower() -eq 'start') {
        $params = @{'VMName' = "$($VMName)"; 'Action' = 'start'; 'ResourceGroupName' = "$($CloudServiceName)" }
    } elseif ($Action.ToLower() -eq 'stop') {
        $params = @{'VMName' = "$($VMName)"; 'Action' = 'stop'; 'ResourceGroupName' = "$($CloudServiceName)" }
    }

   	Write-Output "Performing the schedule $($Action) for the VM : $($VMName) using Classic"

    $runbookName = 'ScheduledStartStop_Child_Classic'

    #Retry logic for Start-AzAutomationRunbook cmdlet

    [string] $FailureMessage = 'Failed to execute the Start-AzAutomationRunbook command'
    [int] $RetryCount = 3
    [int] $TimeoutInSecs = 20
    $RetryFlag = $true
    $Attempt = 1

    do {
        try {
            $job = Start-AzAutomationRunbook -AutomationAccountName $automationAccountName -Name $runbookName -ResourceGroupName $aroResourceGroupName -Parameters $params

            Write-Output "Triggered the child runbook for ARM VM : $($VMName)"

            $RetryFlag = $false

            return $job
        } catch {
            Write-Output $ErrorMessage

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
}

[string] $FailureMessage = 'Failed to execute the command'
[int] $RetryCount = 3
[int] $TimeoutInSecs = 20
$RetryFlag = $true
$Attempt = 1
do {
    #----------------------------------------------------------------------------------
    #---------------------LOGIN TO AZURE AND SELECT THE SUBSCRIPTION-------------------
    #----------------------------------------------------------------------------------

    try {
        $connectionName = 'AzureRunAsConnection'

        Write-Output 'Logging into Azure subscription using Az cmdlets...'

        Import-Module Az.Resources
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

try {
    Write-Output 'Runbook (ScheduledStartStop_Base_Classic) Execution Started...'

    $automationAccountName = Get-AutomationVariable -Name 'Internal_AutomationAccountName'
    $aroResourceGroupName = Get-AutomationVariable -Name 'Internal_ResourceGroupName'

    [string[]] $AzVMList = $VMList -split ','

    Write-Output "Performing the action $($Action) against the classic VM list $($VMList) in the cloud service $($CloudServiceName)..."

    foreach ($VM in $AzVMList) {
        Write-Output "Processing the classic VM $($VM)"

        $job = ScheduleSnoozeClassicAction -CloudServiceName $CloudServiceName -VMName $VM -Action $Action

        Write-Output 'Checking the job status...'

        $jobInfo = Get-AzAutomationJob -Id $job.JobId -ResourceGroupName $aroResourceGroupName -AutomationAccountName $automationAccountName

        $isJobCompleted = $false

        While ($isJobCompleted -ne $true) {
            $isJobCompleted = $true
            if ($jobInfo.Status.ToLower() -ne 'completed') {
                $isJobCompleted = $false

                $jobInfo = Get-AzAutomationJob -Id $job.JobId -ResourceGroupName $aroResourceGroupName -AutomationAccountName $automationAccountName

                Write-Output 'Job is currently in progress...'

                Start-Sleep -Seconds 10
            } else {
                Write-Output "Job is completed for the VM $($VM)..."
                break
            }
        }
    }

    Write-Output 'Runbook (ScheduledStartStop_Base_Classic) Execution Completed...'
} catch {
    $ex = $_.Exception
    Write-Output $_.Exception
}
