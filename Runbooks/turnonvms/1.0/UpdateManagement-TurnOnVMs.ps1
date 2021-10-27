#requires -Modules ThreadJob
#requires -Modules Az.Compute
#requires -Modules Az.Automation
#requires -Modules Az.Resources

<#
.SYNOPSIS
    Start VMs as part of an Update Management deployment

.DESCRIPTION
    This script is intended to be run as a part of Update Management Pre/Post scripts.
    It requires a RunAsAccount.
    This script will ensure all tagged Azure VMs in the Update Deployment are running so they recieve updates.
    This script will store the names of machines that were started in an Automation variable so only those machines
    are turned back off when the deployment is finished (UpdateManagement-TurnOffVMs.ps1)

    Note that the VMs must have a tag named "UpdateStartStop" with value "Enabled" for this script to process it.
    If the tag does not exist, or if the tag has a wrong value, the VM will not be processed.

.PARAMETER SoftwareUpdateConfigurationRunContext
    This is a system variable which is automatically passed in by Update Management during a deployment.
.PARAMETER TagName
    This is the parameter that determines name of tag which decides eligibility.
.PARAMETER TagValue
    This is the parameter that determines value of tag which decides eligibility.
.PARAMETER ExecutionMode
    This parameter enables you to do a "dry run" of script functionality. When set to "DryRun", VMs are not started, only listed.
#>

param(
    [string]$SoftwareUpdateConfigurationRunContext,
    [string]$TagName = "OmniaPT_UpdateStartStop",
    [string]$TagValue = "Enabled",
    [string]$ExecutionMode = ""
)

if ($ExecutionMode -eq "DryRun") {
    $DryRun = $true
}
else {
    $DryRun = $false
}

#region BoilerplateAuthentication
try {
    $ServicePrincipalConnection = Connect-AzAccount -Identity
}
catch {
    Write-Output "Managed Identity Authentication not enabled. Fallback to AzureRunAsConnection"
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
    }
    catch {
        throw "Could not authenticate with AzureRunAsAccount"
    }
}

#$AzureContext = Set-AzContext -SubscriptionId $ServicePrincipalConnection.SubscriptionID -Tenant $ServicePrincipalConnection.TenantId
#endregion BoilerplateAuthentication

#To use the run context, it must be converted from JSON
$context = ConvertFrom-Json  $SoftwareUpdateConfigurationRunContext

if ($DryRun) {
    Write-Output "Execution mode: Dry run. No changes to VM statuses, only reporting."
}
else {
    Write-Output "Execution mode: Regular run. Eligible VMs processed by script."
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

$vmIds = $context.SoftwareUpdateConfigurationSettings.AzureVirtualMachines
$runId = "PrescriptContext" + $context.SoftwareUpdateConfigurationRunId

if (!$vmIds) {
    #Workaround: Had to change JSON formatting
    $Settings = ConvertFrom-Json $context.SoftwareUpdateConfigurationSettings
    #Write-Output "List of settings: $Settings"
    $VmIds = $Settings.AzureVirtualMachines
    #Write-Output "Azure VMs: $VmIds"
    if (!$vmIds) {
        Write-Output "No Azure VMs found"
        return
    }
}

#This is used to store the state of VMs
New-AzAutomationVariable -ResourceGroupName $ResourceGroup -AutomationAccountName $AutomationAccount -Name $runId -Value "" -Encrypted $false

$updatedMachines = @()
$startableStates = "stopped" , "stopping", "deallocated", "deallocating"
$jobIDs = New-Object System.Collections.Generic.List[System.Object]

#Parse the list of VMs and start those which are stopped
#Azure VMs are expressed by:
#subscription/$subscriptionID/resourcegroups/$resourceGroup/providers/microsoft.compute/virtualmachines/$name
$vmIds | ForEach-Object {
    $vmId = $_

    $split = $vmId -split "/";
    $subscriptionId = $split[2];
    $rg = $split[4];
    $name = $split[8];
    Write-Output ("Subscription Id: " + $subscriptionId)
    $mute = Select-AzSubscription -Subscription $subscriptionId

    $vm = Get-AzVM -ResourceGroupName $rg -Name $name -Status -DefaultProfile $mute
    $vmTags = Get-AzVM -ResourceGroupName $rg -Name $name | Select-Object Tags
    $state = ($vm.Statuses[1].DisplayStatus -split " ")[1]

    $UpdateStartStopEnabled = $false
    if ($vmTags.Tags[$TagName] -eq $TagValue) {
        $UpdateStartStopEnabled = $true
    }

    #Query the state of the VM to see if it's already running or if it's already started
    if ($state -in $startableStates) {
        if ($UpdateStartStopEnabled) {
            if ($DryRun) {
                Write-Output "Dry run. Would have started $name in regular run."
            }
            else {
                Write-Output "Starting '$($name)' ..."
                #Store the VM we started so we remember to shut it down later
                $updatedMachines += $vmId
                $newJob = Start-ThreadJob -ScriptBlock { param($resource, $vmname, $sub) $context = Select-AzSubscription -Subscription $sub; Start-AzVM -ResourceGroupName $resource -Name $vmname -DefaultProfile $context } -ArgumentList $rg, $name, $subscriptionId
                $jobIDs.Add($newJob.Id)
            }
        }
        else {
            Write-Output "'$($name)' not enabled for automatic start. Add tag if this was not intentional."
        }
    }
    else {
        Write-Output ($name + ": no action taken. State: " + $state)
    }
}

$updatedMachinesCommaSeparated = $updatedMachines -join ","
#Wait until all machines have finished before proceeding to the Update Deployment
$jobsList = $jobIDs.ToArray()
if ($jobsList) {
    Write-Output "Waiting for machines to finish starting..."
    Wait-Job -Id $jobsList
}

foreach ($id in $jobsList) {
    $job = Get-Job -Id $id
    if ($job.Error) {
        Write-Output $job.Error
    }

}

Write-output $updatedMachinesCommaSeparated
#Store output in the automation variable
Set-AutomationVariable -Name $runId -Value $updatedMachinesCommaSeparated
