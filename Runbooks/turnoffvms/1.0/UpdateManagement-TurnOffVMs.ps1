#requires -Modules ThreadJob
#requires -Modules Az.Compute
#requires -Modules Az.Automation
#requires -Modules Az.Resources

<#
.SYNOPSIS
    Stop VMs that were started as part of an Update Management deployment

.DESCRIPTION
    This script is intended to be run as a part of Update Management Pre/Post scripts.
    It requires a RunAsAccount.
    This script will turn off all Azure VMs that were started as part of TurnOnVMs.ps1.
    It retrieves the list of VMs that were started from an Automation Account variable.

    Note that the VMs must have a tag named "UpdateStartStop" with value "Enabled" for this script to process it.
    If the tag does not exist, or if the tag has a wrong value, the VM will not be processed.

.PARAMETER SoftwareUpdateConfigurationRunContext
    This is a system variable which is automatically passed in by Update Management during a deployment.
.PARAMETER TagName
    This is the parameter that determines name of tag which decides eligibility.
.PARAMETER TagValue
    This is the parameter that determines value of tag which decides eligibility.
.PARAMETER ExecutionMode
    This parameter enables you to do a "dry run" of script functionality. When set to "DryRun", VMs are not stopped, only listed.
#>

param(
    [string]$SoftwareUpdateConfigurationRunContext,
    [string]$TagName = 'OmniaPT_UpdateStartStop',
    [string]$TagValue = 'Enabled',
    [string]$ExecutionMode = ''
)

if ($ExecutionMode -eq 'DryRun') {
    $DryRun = $true
} else {
    $DryRun = $false
}

#region BoilerplateAuthentication
try {
    $ServicePrincipalConnection = Connect-AzAccount -Identity
} catch {
    Write-Output 'Managed Identity Authentication not enabled. Fallback to AzureRunAsConnection'
    $ServicePrincipalConnection = $false
}

if (!$ServicePrincipalConnection) {
    try {
        #This requires a RunAs account
        $ServicePrincipalConnection = Get-AutomationConnection -Name 'AzureRunAsConnection'
        Connect-AzAccount `
            -ServicePrincipal `
            -TenantId $ServicePrincipalConnection.TenantId `
            -ApplicationId $ServicePrincipalConnection.ApplicationId `
            -CertificateThumbprint $ServicePrincipalConnection.CertificateThumbprint
    } catch {
        throw 'Could not authenticate with AzureRunAsAccount'
    }
}

#$AzureContext = Set-AzContext -SubscriptionId $ServicePrincipalConnection.SubscriptionID -Tenant $ServicePrincipalConnection.TenantId
#endregion BoilerplateAuthentication

#If you wish to use the run context, it must be converted from JSON
$context = ConvertFrom-Json $SoftwareUpdateConfigurationRunContext
$runId = 'PrescriptContext' + $context.SoftwareUpdateConfigurationRunId

if ($DryRun) {
    Write-Output 'Execution mode: Dry run. No changes to VM statuses, only reporting.'
} else {
    Write-Output 'Execution mode: Regular run. Eligible VMs processed by script.'
}


#Retrieve the automation variable, which we named using the runID from our run context.
#See: https://docs.microsoft.com/en-us/azure/automation/automation-variables#activities
$variable = Get-AutomationVariable -Name $runId
if (!$variable) {
    Write-Output 'No machines to turn off'
    return
}

#Find the Automation Account and Resource Group name by filtering on all automation accounts and jobs
$AutomationResource = Get-AzResource -ResourceType Microsoft.Automation/AutomationAccounts

foreach ($Automation in $AutomationResource) {
    $Job = Get-AzAutomationJob -ResourceGroupName $Automation.ResourceGroupName -AutomationAccountName $Automation.Name -Id $PSPrivateMetadata.JobId.Guid -ErrorAction SilentlyContinue
    if (!([string]::IsNullOrEmpty($Job))) {
        $ResourceGroup = $Job.ResourceGroupName
        $AutomationAccount = $Job.AutomationAccountName
        break;
    }
}

$vmIds = $variable -split ','
$stoppableStates = 'starting', 'running'
$jobIDs = New-Object System.Collections.Generic.List[System.Object]

#This script can run across subscriptions, so we need unique identifiers for each VMs
#Azure VMs are expressed by:
#subscription/$subscriptionID/resourcegroups/$resourceGroup/providers/microsoft.compute/virtualmachines/$name
$vmIds | ForEach-Object {
    $vmId = $_

    $split = $vmId -split '/';
    $subscriptionId = $split[2];
    $rg = $split[4];
    $name = $split[8];
    Write-Output ('Subscription Id: ' + $subscriptionId)
    $mute = Select-AzSubscription -Subscription $subscriptionId

    $vm = Get-AzVM -ResourceGroupName $rg -Name $name -Status -DefaultProfile $mute

    $vmTags = Get-AzVM -ResourceGroupName $rg -Name $name | Select-Object Tags
    $state = ($vm.Statuses[1].DisplayStatus -split ' ')[1]

    $UpdateStartStopEnabled = $false
    if ($vmTags.Tags[$TagName] -eq $TagValue) {
        $UpdateStartStopEnabled = $true
    }

    if ($state -in $stoppableStates) {
        if ($UpdateStartStopEnabled) {
            if ($DryRun) {
                Write-Output "Dry run. Would have stopped $name in regular run."
            } else {
                Write-Output "Stopping '$($name)' ..."
                $newJob = Start-ThreadJob -ScriptBlock { param($resource, $vmname, $sub) $context = Select-AzSubscription -Subscription $sub; Stop-AzVM -ResourceGroupName $resource -Name $vmname -Force -DefaultProfile $context } -ArgumentList $rg, $name, $subscriptionId
                $jobIDs.Add($newJob.Id)
            }
        } else {
            Write-Output "'$($name)' not enabled for automatic stop. Add tag if this was not intentional."
        }
    } else {
        Write-Output ($name + ': already stopped. State: ' + $state)
    }
}

#Wait for all machines to finish stopping so we can include the results as part of the Update Deployment
$jobsList = $jobIDs.ToArray()
if ($jobsList) {
    Write-Output 'Waiting for machines to finish stopping...'
    Wait-Job -Id $jobsList
}

foreach ($id in $jobsList) {
    $job = Get-Job -Id $id
    if ($job.Error) {
        Write-Output $job.Error
    }
}
#Clean up our variables:
Remove-AzAutomationVariable -AutomationAccountName $AutomationAccount -ResourceGroupName $ResourceGroup -Name $runID
