<#
.SYNOPSIS
 Bootstrap master script for pre-configuring Automation Account
.DESCRIPTION
 Bootstrap master script for pre-configuring Automation Account
.EXAMPLE
.\Bootstrap_Main.ps1
Version History
v1.0 - Initial Release
v2.0 - Refactored Az modules
v2.1 - Added possibility for disabling schedules after deploy
#>


# ------------------Execution Entry point ---------------------

Write-Output 'Bootstrap main script execution started...'

#---------Inputs variables for NewRunAsAccountCertKeyVault.ps1 child bootstrap script--------------
$automationAccountName = Get-AutomationVariable -Name 'Internal_AutomationAccountName'
$aroResourceGroupName = Get-AutomationVariable -Name 'Internal_ResourceGroupName'

$startScheduleDisabled = Get-AutomationVariable -Name 'Internal_StartScheduleDisabled'
$stopScheduleDisabled = Get-AutomationVariable -Name 'Internal_StopScheduleDisabled'

[string] $FailureMessage = 'Failed to execute the command'
[int] $RetryCount = 3
[int] $TimeoutInSecs = 20
$RetryFlag = $true
$Attempt = 1

do {
    #-----L O G I N - A U T H E N T I C A T I O N-----
    $connectionName = 'AzureRunAsConnection'
    try {
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

            Write-Error -Message $_.Exception

            throw $_.Exception

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

    #=======================STEP 1 execution starts===========================

    #In Step 1 we are creating webhooks for AutoStop runbooks...
    try {
        #---------Inputs variables for Webhook creation--------------
        $runbookNameforAutoStopVM = 'AutoStop_VM_Child'
        $webhookNameforAutoStopVM = 'AutoStop_VM_ChildWebhook'

        $runbookNameforAutoStopVMARM = 'AutoStop_VM_Child_ARM'
        $webhookNameforAutoStopVMARM = 'AutoStop_VM_ChildWebhook_ARM'

        [String] $WebhookUriVariableName = 'Internal_AutoSnooze_WebhookUri'
        [String] $WebhookUriVariableNameARM = 'Internal_AutoSnooze_ARM_WebhookUri'

        #Webhook creation for variable Internal_AutoSnooze_WebhookUri
        $checkWebhook = Get-AzAutomationWebhook -Name $webhookNameforAutoStopVM -AutomationAccountName $AutomationAccountName -ResourceGroupName $aroResourceGroupName -ErrorAction SilentlyContinue

        if ($null -eq $checkWebhook) {
            Write-Output "Executing Step-1 : Create the webhook for $($runbookNameforAutoStopVM)..."

            $ExpiryTime = (Get-Date).AddDays(730)

            Write-Output "Creating the Webhook ($($webhookNameforAutoStopVM)) for the Runbook ($($runbookNameforAutoStopVM))..."

            $Webhookdata = New-AzAutomationWebhook -Name $webhookNameforAutoStopVM -AutomationAccountName $automationAccountName -ResourceGroupName $aroResourceGroupName -RunbookName $runbookNameforAutoStopVM -IsEnabled $true -ExpiryTime $ExpiryTime -Force

            Write-Output "Successfully created the Webhook ($($webhookNameforAutoStopVM)) for the Runbook ($($runbookNameforAutoStopVM))..."

            $ServiceUri = $Webhookdata.WebhookURI

            Write-Output "Webhook Uri [$($ServiceUri)]"

            Write-Output "Creating the Assest Variable ($($WebhookUriVariableName)) in the Automation Account ($($automationAccountName)) to store the Webhook URI..."

            New-AzAutomationVariable -AutomationAccountName $automationAccountName -Name $WebhookUriVariableName -Encrypted $False -Value $ServiceUri -ResourceGroupName $aroResourceGroupName

            Write-Output "Successfully created the Assest Variable ($($WebhookUriVariableName)) in the Automation Account ($($automationAccountName)) and Webhook URI value updated..."

            Write-Output 'Webhook creation for variable Internal_AutoSnooze_WebhookUri completed...'

            Write-Output 'Completed Step-1...'
        } else {
            Write-Output 'Webhook for variable Internal_AutoSnooze_WebhookUri already available. Ignoring Step-1...'
        }


        #Webhook creation for variable Internal_AutoSnooze_ARM_WebhookUri
        $checkWebhook = Get-AzAutomationWebhook -Name $webhookNameforAutoStopVMARM -AutomationAccountName $AutomationAccountName -ResourceGroupName $aroResourceGroupName -ErrorAction SilentlyContinue

        if ($null -eq $checkWebhook) {
            Write-Output "Executing Step-1 : Create the webhook for $($runbookNameforAutoStopVMARM)..."

            $ExpiryTime = (Get-Date).AddDays(730)

            Write-Output "Creating the Webhook ($($webhookNameforAutoStopVMARM)) for the Runbook ($($runbookNameforAutoStopVMARM))..."

            $Webhookdata = New-AzAutomationWebhook -Name $webhookNameforAutoStopVMARM -AutomationAccountName $automationAccountName -ResourceGroupName $aroResourceGroupName -RunbookName $runbookNameforAutoStopVMARM -IsEnabled $true -ExpiryTime $ExpiryTime -Force

            Write-Output "Successfully created the Webhook ($($webhookNameforAutoStopVMARM)) for the Runbook ($($runbookNameforAutoStopVMARM))..."

            $ServiceUri = $Webhookdata.WebhookURI

            Write-Output "Webhook Uri [$($ServiceUri)]"

            Write-Output "Creating the Assest Variable ($($WebhookUriVariableNameARM)) in the Automation Account ($($automationAccountName)) to store the Webhook URI..."

            New-AzAutomationVariable -AutomationAccountName $automationAccountName -Name $WebhookUriVariableNameARM -Encrypted $False -Value $ServiceUri -ResourceGroupName $aroResourceGroupName

            Write-Output "Successfully created the Assest Variable ($($WebhookUriVariableNameARM)) in the Automation Account ($($automationAccountName)) and Webhook URI value updated..."

            Write-Output 'Webhook creation for variable Internal_AutoSnooze_ARM_WebhookUri completed...'

            Write-Output 'Completed Step-1...'
        } else {
            Write-Output 'Webhook for variable Internal_AutoSnooze_ARM_WebhookUri already available. Ignoring Step-1...'
        }

    } catch {
        Write-Output 'Error Occurred in Step-1...'
        Write-Output $_.Exception
        Write-Error $_.Exception
        exit
    }

    #=======================STEP 1 execution ends=============================

    #***********************STEP 2 execution starts**********************************

    #In Step 2 we are creating schedules for AutoSnooze and disable it...
    try {
        #---------Inputs variables for CreateScheduleforAlert.ps1 child bootstrap script--------------
        $runbookNameforCreateAlert = 'AutoStop_CreateAlert_Parent'
        $scheduleNameforCreateAlert = 'Schedule_AutoStop_CreateAlert_Parent'

        $checkMegaSchedule = Get-AzAutomationSchedule -Name $scheduleNameforCreateAlert -AutomationAccountName $automationAccountName -ResourceGroupName $aroResourceGroupName -ErrorAction SilentlyContinue

        if ($null -eq $checkMegaSchedule) {
            Write-Output 'Executing Step-2 : Create schedule for AutoStop_CreateAlert_Parent runbook ...'

            #-----Configure the Start & End Time----
            $StartTime = (Get-Date).AddMinutes(10)
            $EndTime = $StartTime.AddYears(3)

            #----Set the schedule to run every 8 hours---
            $Hours = 8

            #---Create the schedule at the Automation Account level---
            Write-Output "Creating the Schedule ($($scheduleNameforCreateAlert)) in Automation Account ($($automationAccountName))..."

            New-AzAutomationSchedule -AutomationAccountName $automationAccountName -Name $scheduleNameforCreateAlert -ResourceGroupName $aroResourceGroupName -StartTime $StartTime -ExpiryTime $EndTime -HourInterval $Hours

            #Disable the schedule
            Set-AzAutomationSchedule -AutomationAccountName $automationAccountName -Name $scheduleNameforCreateAlert -ResourceGroupName $aroResourceGroupName -IsEnabled $false

            Write-Output "Successfully created the Schedule ($($scheduleNameforCreateAlert)) in Automation Account ($($automationAccountName))..."

            $paramsAutoSnooze = @{'WhatIf' = $false }

            #---Link the schedule to the runbook---
            Write-Output "Registering the Schedule ($($scheduleNameforCreateAlert)) in the Runbook ($($runbookNameforCreateAlert))..."

            Register-AzAutomationScheduledRunbook -AutomationAccountName $automationAccountName -RunbookName $runbookNameforCreateAlert -ScheduleName $scheduleNameforCreateAlert -ResourceGroupName $aroResourceGroupName -Parameters $paramsAutoSnooze

            Write-Output "Successfully Registered the Schedule ($($scheduleNameforCreateAlert)) in the Runbook ($($runbookNameforCreateAlert))..."

            Write-Output 'Completed Step-2 ...'
        } else {
            Write-Output "Schedule $($scheduleNameforCreateAlert) already available. Ignoring Step-2..."
        }
    } catch {
        Write-Output 'Error Occurred in Step-2...'
        Write-Output $_.Exception
        Write-Error $_.Exception
        exit
    }

    #***********************STEP 2 execution ends**********************************


    #~~~~~~~~~~~~~~~~~~~~STEP 3 execution starts~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    #In Step 3 we are creating schedules for SequencedSnooze and disable it...

    try {

        $runbookNameforARMVMOptimization = 'SequencedStartStop_Parent'
        $sequenceStart = 'Sequenced-StartVM'
        $sequenceStop = 'Sequenced-StopVM'

        $checkSeqSnoozeStart = Get-AzAutomationSchedule -AutomationAccountName $automationAccountName -Name $sequenceStart -ResourceGroupName $aroResourceGroupName -ErrorAction SilentlyContinue
        $checkSeqSnoozeStop = Get-AzAutomationSchedule -AutomationAccountName $automationAccountName -Name $sequenceStop -ResourceGroupName $aroResourceGroupName -ErrorAction SilentlyContinue

        #Starts every monday 6AM
        $StartVmUTCTime = (Get-Date '13:00:00').AddDays(1).ToUniversalTime()
        #Stops every friday 6PM
        $StopVmUTCTime = (Get-Date '01:00:00').AddDays(1).ToUniversalTime()

        if ($null -eq $checkSeqSnoozeStart) {
            Write-Output 'Executing Step-3 : Create start schedule for SequencedStartStop_Parent runbook ...'

            #---Create the schedule at the Automation Account level---
            Write-Output "Creating the Schedule in Automation Account ($($automationAccountName))..."

            New-AzAutomationSchedule -AutomationAccountName $automationAccountName -Name $sequenceStart -ResourceGroupName $aroResourceGroupName -StartTime $StartVmUTCTime -DaysOfWeek Monday -WeekInterval 1

            Write-Output "Successfully created the Schedule in Automation Account ($($automationAccountName))..."

            Set-AzAutomationSchedule -AutomationAccountName $automationAccountName -Name $sequenceStart -ResourceGroupName $aroResourceGroupName -IsEnabled $false

            $paramsStartVM = @{'Action' = 'start'; 'WhatIf' = $false; 'ContinueOnError' = $false }

            Register-AzAutomationScheduledRunbook -AutomationAccountName $automationAccountName -RunbookName $runbookNameforARMVMOptimization -ScheduleName $sequenceStart -ResourceGroupName $aroResourceGroupName -Parameters $paramsStartVM

            Write-Output "Successfully Registered the Schedule in the Runbook ($($runbookNameforARMVMOptimization))..."
        }

        if ($null -eq $checkSeqSnoozeStop) {
            Write-Output 'Executing Step-3 : Create stop schedule for SequencedStartStop_Parent runbook ...'

            #---Create the schedule at the Automation Account level---
            Write-Output "Creating the Schedule in Automation Account ($($automationAccountName))..."

            New-AzAutomationSchedule -AutomationAccountName $automationAccountName -Name $sequenceStop -ResourceGroupName $aroResourceGroupName -StartTime $StopVmUTCTime -DaysOfWeek Friday -WeekInterval 1

            Write-Output "Successfully created the Schedule in Automation Account ($($automationAccountName))..."

            Set-AzAutomationSchedule -AutomationAccountName $automationAccountName -Name $sequenceStop -ResourceGroupName $aroResourceGroupName -IsEnabled $false

            $paramsStartVM = @{'Action' = 'stop'; 'WhatIf' = $false; 'ContinueOnError' = $false }

            Register-AzAutomationScheduledRunbook -AutomationAccountName $automationAccountName -RunbookName $runbookNameforARMVMOptimization -ScheduleName $sequenceStop -ResourceGroupName $aroResourceGroupName -Parameters $paramsStartVM

            Write-Output "Successfully Registered the Schedule in the Runbook ($($runbookNameforARMVMOptimization))..."
        }

        if ($null -ne $checkSeqSnoozeStart -and $null -ne $checkSeqSnoozeStop) {
            Write-Output 'Schedule already available. Ignoring Step-3...'
        }
        Write-Output 'Completed Step-3 ...'

    } catch {
        Write-Output 'Error Occurred in Step-3...'
        Write-Output $_.Exception
        Write-Error $_.Exception
        exit
    }


    #~~~~~~~~~~~~~~~~~~~~STEP 3 execution ends~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    #~~~~~~~~~~~~~~~~~~~~STEP 4 execution starts~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    try {
        if ($startScheduleDisabled -eq 'true') {
            Write-Output 'Disabling start schedule according to Automation Variable "Internal_StartScheduleDisabled"...'
            $startSchedule = Get-AzAutomationSchedule -AutomationAccountName $automationAccountName -Name 'Scheduled-StartVM' -ResourceGroupName $aroResourceGroupName -ErrorAction SilentlyContinue

            if ($null -ne $startSchedule) {
                Set-AzAutomationSchedule -AutomationAccountName $automationAccountName -Name $startSchedule.Name -ResourceGroupName $aroResourceGroupName -IsEnabled $false
            }
        }

        if ($stopScheduleDisabled -eq 'true') {
            Write-Output 'Disabling stop schedule according to Automation Variable "Internal_StopScheduleDisabled"...'
            $stopSchedule = Get-AzAutomationSchedule -AutomationAccountName $automationAccountName -Name 'Scheduled-StopVM' -ResourceGroupName $aroResourceGroupName -ErrorAction SilentlyContinue

            if ($null -ne $stopSchedule) {
                Set-AzAutomationSchedule -AutomationAccountName $automationAccountName -Name $stopSchedule.Name -ResourceGroupName $aroResourceGroupName -IsEnabled $false
            }
        }

        Write-Output 'Completed Step-4...'
    } catch {
        Write-Output 'Error Occurred in Step-4...'
        Write-Output $_.Exception
        Write-Error $_.Exception
        exit
    }


    #*******************STEP 5 execution starts********************************************

    try {

        $checkScheduleBootstrap = Get-AzAutomationSchedule -AutomationAccountName $automationAccountName -Name 'startBootstrap' -ResourceGroupName $aroResourceGroupName -ErrorAction SilentlyContinue

        if ($null -ne $checkScheduleBootstrap) {

            Write-Output 'Removing Bootstrap Schedule...'

            Remove-AzAutomationSchedule -Name 'startBootstrap' -AutomationAccountName $automationAccountName -ResourceGroupName $aroResourceGroupName -Force
        }

        Write-Output 'Removing Bootstrap Runbook...'

        Remove-AzAutomationRunbook -Name 'Bootstrap_Main' -ResourceGroupName $aroResourceGroupName -AutomationAccountName $automationAccountName -Force

        Write-Output 'Completed Step-5...'
    } catch {
        Write-Output 'Error Occurred in Step-5...'
        Write-Output $_.Exception
    }

    #*******************STEP 5 execution ends********************************************

    Write-Output 'Bootstrap wrapper script execution completed...'

} catch {
    Write-Output 'Error Occurred in Bootstrap Wrapper...'
    Write-Output $_.Exception
    Write-Error $_.Exception
}
