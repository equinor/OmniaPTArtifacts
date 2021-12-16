<#
.SYNOPSIS
    This runbook used to perform sequenced start or stop Azure RM.
.DESCRIPTION
    This runbook used to perform sequenced start or stop Azure RM.
    Create a tag called “sequencestart” on each VM that you want to sequence start activity for.Create a tag called “sequencestop” on each VM that you want to sequence stop activity for. The value of the tag should be an integer (1,2,3) that corresponds to the order you want to start\stop. For both action, the order goes ascending (1,2,3) . WhatIf behaves the same as in other runbooks.
    Upon completion of the runbook, an option to email results of the started VM can be sent via Action Groups and alerts.

    This runbook requires the Azure Automation Run-As (Service Principle) account, which must be added when creating the Azure Automation account.
 .PARAMETER
    Parameters are read in from Azure Automation variables.
    Variables (editable):
    -  External_Start_ResourceGroupNames    :  ResourceGroup that contains VMs to be started. Must be in the same subscription that the Azure Automation Run-As account has permission to manage.
    -  External_Stop_ResourceGroupNames     :  ResourceGroup that contains VMs to be stopped. Must be in the same subscription that the Azure Automation Run-As account has permission to manage.
    -  External_ExcludeVMNames              :  VM names to be excluded from being started.
.EXAMPLE
	.\SequencedStartStop_Parent.ps1 -Action "Value1"

#>

Param(
    [Parameter(Mandatory = $true, HelpMessage = 'Enter the value for Action. Values can be either stop or start')][String]$Action,
    [Parameter(Mandatory = $false, HelpMessage = 'Enter the value for WhatIf. Values can be either true or false')][bool]$WhatIf = $false,
    [Parameter(Mandatory = $false, HelpMessage = 'Enter the value for ContinueOnError. Values can be either true or false')][bool]$ContinueOnError = $false,
    [Parameter(Mandatory = $false, HelpMessage = 'Enter the VMs separated by comma(,)')][string]$VMList
)

function PerformActionOnSequencedTaggedVMAll($Sequences, [string]$Action, $TagName, $ExcludeList) {
    $AllVMs = Get-AzVM

    $ResourceGroups = Get-AzResourceGroup

    foreach ($seq in $Sequences) {
        Write-Output "Getting all the VM's from the subscription..."

        $AzureVMList = @()

        $AzureVMListTemp = @()

        if ($WhatIf -eq $false) {
            Write-Output "Performing the $($Action) action against VM's where the tag $($TagName) is $($seq)."

            $AllVMResources = Get-AzResource -TagValue $seq | Where-Object { ($_.ResourceType -eq 'Microsoft.Compute/virtualMachines') }

            foreach ($rg in $ResourceGroups) {
                $AzureVMList += $AllVMResources | Where-Object ResourceGroupName -EQ $rg.ResourceGroupName | Select-Object Name, ResourceGroupName
            }

            foreach ($VM in $AzureVMList) {
                $FilterTagVMs = $AllVMs | Where-Object ResourceGroupName -EQ $VM.ResourceGroupName | Where-Object Name -EQ $VM.Name

                $CaseSensitiveTagName = $FilterTagVMs.Tags.Keys | Where-Object -FilterScript { $_ -eq $TagName }

                if ($null -ne $CaseSensitiveTagName) {
                    if ($FilterTagVMs.Tags[$CaseSensitiveTagName] -eq $seq) {
                        $AzureVMListTemp += $FilterTagVMs | Select-Object Name, ResourceGroupName
                    }
                }
            }
            $AzureVMList = $AzureVMListTemp

            ##Remove Excluded VMs
            $ActualAzureVMList = @()
            $ExAzureVMList = @()
            if (($null -ne $ExcludeList) -and ($ExcludeList -ne 'none')) {
                foreach ($filtervm in $ExcludeList) {
                    $currentVM = $AllVMs | Where-Object Name -Like $filtervm.Trim() -ErrorAction SilentlyContinue

                    if ($currentVM.Count -ge 1) {
                        $ExAzureVMList += $currentVM.Name
                    }
                }
            }

            if (($null -ne $ExcludeList) -and ($ExcludeList -ne 'none')) {
                foreach ($VM in $AzureVMList) {
                    ##Checking Vm in excluded list
                    if ($ExAzureVMList -notcontains ($($VM.Name))) {
                        $ActualAzureVMList += $VM
                    }
                }
            } else {
                $ActualAzureVMList = $AzureVMList
            }

            $ActualVMListOutput = @()

            foreach ($vmObj in $ActualAzureVMList) {
                $ActualVMListOutput = $ActualVMListOutput + $vmObj.Name + ' '

                Write-Output "Executing runbook ScheduledStartStop_Child to perform the $($Action) action on VM: $($vmobj.Name)"

                $params = @{'VMName' = "$($vmObj.Name)"; 'Action' = $Action; 'ResourceGroupName' = "$($vmObj.ResourceGroupName)" }

                #Retry logic for Start-AzAutomationRunbook cmdlet

                [string] $FailureMessage = 'Failed to execute the Start-AzAutomationRunbook command'
                [int] $RetryCount = 3
                [int] $TimeoutInSecs = 20
                $RetryFlag = $true
                $Attempt = 1

                do {
                    try {
                        $runbook = Start-AzAutomationRunbook -AutomationAccountName $automationAccountName -Name 'ScheduledStartStop_Child' -ResourceGroupName $aroResourceGroupName –Parameters $params

                        Write-Output "Triggered the child runbook for ARM VM : $($vmObj.Name)"

                        $RetryFlag = $false
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

            if ($null -ne $ActualVMListOutput) {
                Write-Output "~Attempted the $($Action) action on the following VMs in sequence $($seq): $($ActualVMListOutput)"
            }

            Write-Output "Completed the sequenced $($Action) against VM's where the tag $($TagName) is $($seq)."

            if (($Action -eq 'stop' -and $seq -ne $Sequences.Count) -or ($Action -eq 'start' -and $seq -ne [int]$Sequences.Count - ([int]$Sequences.Count - 1))) {
                Write-Output 'Validating the status before processing the next sequence...'
            }

            foreach ($vmObjStatus in $ActualAzureVMList) {
                [int]$SleepCount = 0
                $CheckVMStatus = CheckVMState -VMObject $vmObjStatus -Action $Action
                While ($CheckVMStatus -eq $false) {
                    Write-Output 'Checking the VM Status in 15 seconds...'

                    Start-Sleep -Seconds 15

                    $SleepCount += 15

                    if ($SleepCount -gt $maxWaitTimeForVMRetryInSeconds -and $ContinueOnError -eq $false) {
                        Write-Output "Unable to $($Action) the VM $($vmObjStatus.Name). ContinueOnError is set to False, hence terminating the sequenced $($Action)..."
                        Write-Output "Completed the sequenced $($Action)..."
                        exit
                    } elseif ($SleepCount -gt $maxWaitTimeForVMRetryInSeconds -and $ContinueOnError -eq $true) {
                        Write-Output "Unable to $($Action) the VM $($vmObjStatus.Name). ContinueOnError is set to True, hence moving to the next resource..."
                        break
                    }
                    $CheckVMStatus = CheckVMState -VMObject $vmObjStatus -Action $Action
                }
            }
        } elseif ($WhatIf -eq $true) {
            Write-Output 'WhatIf parameter is set to True...'

            Write-Output "When 'WhatIf' is set to TRUE, runbook provides a list of Azure Resources (e.g. VMs), that will be impacted if you choose to deploy this runbook."

            Write-Output "No action will be taken at this time. These are the resources where the tag $($TagName) is $($seq)..."

            $AllVMResources = Get-AzResource -TagValue $seq | Where-Object { ($_.ResourceType -eq 'Microsoft.Compute/virtualMachines') }

            foreach ($rg in $ResourceGroups) {
                $AzureVMList += $AllVMResources | Where-Object ResourceGroupName -EQ $rg.ResourceGroupName | Select-Object Name, ResourceGroupName
            }

            foreach ($VM in $AzureVMList) {
                $FilterTagVMs = $AllVMs | Where-Object ResourceGroupName -EQ $VM.ResourceGroupName | Where-Object Name -EQ $VM.Name

                $CaseSensitiveTagName = $FilterTagVMs.Tags.Keys | Where-Object -FilterScript { $_ -eq $TagName }

                if ($null -ne $CaseSensitiveTagName) {
                    if ($FilterTagVMs.Tags[$CaseSensitiveTagName] -eq $seq) {
                        $AzureVMListTemp += $FilterTagVMs | Select-Object Name, ResourceGroupName
                    }
                }
            }
            $AzureVMList = $AzureVMListTemp

            ##Remove Excluded VMs
            $ActualAzureVMList = @()
            $ExAzureVMList = @()
            if (($null -ne $ExcludeList) -and ($ExcludeList -ne 'none')) {
                foreach ($filtervm in $ExcludeList) {
                    $currentVM = $AllVMs | Where-Object Name -Like $filtervm.Trim() -ErrorAction SilentlyContinue

                    if ($currentVM.Count -ge 1) {
                        $ExAzureVMList += $currentVM.Name
                    }
                }
            }

            if (($null -ne $ExcludeList) -and ($ExcludeList -ne 'none')) {
                foreach ($VM in $AzureVMList) {
                    ##Checking Vm in excluded list
                    if ($ExAzureVMList -notcontains ($($VM.Name))) {
                        $ActualAzureVMList += $VM
                    }
                }
            } else {
                $ActualAzureVMList = $AzureVMList
            }

            Write-Output $($ActualAzureVMList)
            Write-Output "End of resources where tag $($TagName) is $($seq)..."
        }
    }
}

function PerformActionOnSequencedTaggedVMRGs($Sequences, [string]$Action, $TagName, [string[]]$VMRGList, $ExcludeList) {
    $AllVMs = Get-AzVM

    foreach ($seq in $Sequences) {
        $AzureVMList = @()
        $AzureVMListTemp = @()

        if ($WhatIf -eq $false) {
            Write-Output "Performing the $($Action) action against VM's where the tag $($TagName) is $($seq)."

            $AllVMResources = Get-AzResource -TagValue $seq | Where-Object { ($_.ResourceType -eq 'Microsoft.Compute/virtualMachines') }

            foreach ($rg in $VMRGList) {
                $AzureVMList += $AllVMResources | Where-Object ResourceGroupName -EQ $rg.Trim() | Select-Object Name, ResourceGroupName
            }

            foreach ($VM in $AzureVMList) {
                $FilterTagVMs = $AllVMs | Where-Object ResourceGroupName -EQ $VM.ResourceGroupName | Where-Object Name -EQ $VM.Name

                $CaseSensitiveTagName = $FilterTagVMs.Tags.Keys | Where-Object -FilterScript { $_ -eq $TagName }

                if ($null -ne $CaseSensitiveTagName) {
                    if ($FilterTagVMs.Tags[$CaseSensitiveTagName] -eq $seq) {
                        $AzureVMListTemp += $FilterTagVMs | Select-Object Name, ResourceGroupName
                    }
                }
            }
            $AzureVMList = $AzureVMListTemp

            ##Remove Excluded VMs
            $ActualAzureVMList = @()
            $ExAzureVMList = @()

            if (($null -ne $ExcludeList) -and ($ExcludeList -ne 'none')) {
                foreach ($filtervm in $ExcludeList) {
                    $currentVM = $AllVMs | Where-Object Name -Like $filtervm.Trim() -ErrorAction SilentlyContinue

                    if ($currentVM.Count -ge 1) {
                        $ExAzureVMList += $currentVM.Name
                    }
                }
            }

            if (($null -ne $ExcludeList) -and ($ExcludeList -ne 'none')) {
                foreach ($VM in $AzureVMList) {
                    ##Checking Vm in excluded list
                    if ($ExAzureVMList -notcontains ($($VM.Name))) {
                        $ActualAzureVMList += $VM
                    }
                }
            } else {
                $ActualAzureVMList = $AzureVMList
            }

            $ActualVMListOutput = @()

            foreach ($vmObj in $ActualAzureVMList) {
                $ActualVMListOutput = $ActualVMListOutput + $vmObj.Name + ' '
                Write-Output "Executing runbook ScheduledStartStop_Child to perform the $($Action) action on VM: $($vmobj.Name)"
                $params = @{'VMName' = "$($vmObj.Name)"; 'Action' = $Action; 'ResourceGroupName' = "$($vmObj.ResourceGroupName)" }

                #Retry logic for Start-AzAutomationRunbook cmdlet

                [string] $FailureMessage = 'Failed to execute the Start-AzAutomationRunbook command'
                [int] $RetryCount = 3
                [int] $TimeoutInSecs = 20
                $RetryFlag = $true
                $Attempt = 1

                do {
                    try {
                        $runbook = Start-AzAutomationRunbook -AutomationAccountName $automationAccountName -Name 'ScheduledStartStop_Child' -ResourceGroupName $aroResourceGroupName –Parameters $params

                        Write-Output "Triggered the child runbook for ARM VM : $($vmObj.Name)"

                        $RetryFlag = $false
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

            if ($null -ne $ActualVMListOutput) {
                Write-Output "~Attempted the $($Action) action on the following VMs in sequence $($seq): $($ActualVMListOutput)"
            }

            Write-Output "Completed the sequenced $($Action) against VM's where the tag $($TagName) is $($seq)."

            if (($Action -eq 'stop' -and $seq -ne $Sequences.Count) -or ($Action -eq 'start' -and $seq -ne [int]$Sequences.Count - ([int]$Sequences.Count - 1))) {
                Write-Output 'Validating the status before processing the next sequence...'
            }

            foreach ($vmObjStatus in $ActualAzureVMList) {
                [int]$SleepCount = 0

                $CheckVMStatus = CheckVMState -VMObject $vmObjStatus -Action $Action

                While ($CheckVMStatus -eq $false) {
                    Write-Output 'Checking the VM Status in 15 seconds...'

                    Start-Sleep -Seconds 15

                    $SleepCount += 15

                    if ($SleepCount -gt $maxWaitTimeForVMRetryInSeconds -and $ContinueOnError -eq $false) {
                        Write-Output "Unable to $($Action) the VM $($vmObjStatus.Name). ContinueOnError is set to False, hence terminating the sequenced $($Action)..."
                        Write-Output "Completed the sequenced $($Action)..."
                        exit
                    } elseif ($SleepCount -gt $maxWaitTimeForVMRetryInSeconds -and $ContinueOnError -eq $true) {
                        Write-Output "Unable to $($Action) the VM $($vmObjStatus.Name). ContinueOnError is set to True, hence moving to the next resource..."
                        break
                    }
                    $CheckVMStatus = CheckVMState -VMObject $vmObjStatus -Action $Action
                }
            }
        } elseif ($WhatIf -eq $true) {
            Write-Output 'WhatIf parameter is set to True...'

            Write-Output "When 'WhatIf' is set to TRUE, runbook provides a list of Azure Resources (e.g. VMs), that will be impacted if you choose to deploy this runbook."

            Write-Output "No action will be taken at this time. These are the resources where the tag $($TagName) is $($seq)..."

            $AllVMResources = Get-AzResource -TagValue $seq | Where-Object { ($_.ResourceType -eq 'Microsoft.Compute/virtualMachines') }

            foreach ($rg in $VMRGList) {
                $AzureVMList += $AllVMResources | Where-Object ResourceGroupName -EQ $rg.Trim() | Select-Object Name, ResourceGroupName
            }

            foreach ($VM in $AzureVMList) {
                $FilterTagVMs = $AllVMs | Where-Object ResourceGroupName -EQ $VM.ResourceGroupName | Where-Object Name -EQ $VM.Name

                $CaseSensitiveTagName = $FilterTagVMs.Tags.Keys | Where-Object -FilterScript { $_ -eq $TagName }

                if ($null -ne $CaseSensitiveTagName) {
                    if ($FilterTagVMs.Tags[$CaseSensitiveTagName] -eq $seq) {
                        $AzureVMListTemp += $FilterTagVMs | Select-Object Name, ResourceGroupName
                    }
                }
            }
            $AzureVMList = $AzureVMListTemp

            ##Remove Excluded VMs
            $ActualAzureVMList = @()
            $ExAzureVMList = @()
            if (($null -ne $ExcludeList) -and ($ExcludeList -ne 'none')) {
                foreach ($filtervm in $ExcludeList) {
                    $currentVM = $AllVMs | Where-Object Name -Like $filtervm.Trim() -ErrorAction SilentlyContinue

                    if ($currentVM.Count -ge 1) {
                        $ExAzureVMList += $currentVM.Name
                    }
                }
            }

            if (($null -ne $ExcludeList) -and ($ExcludeList -ne 'none')) {
                foreach ($VM in $AzureVMList) {
                    ##Checking Vm in excluded list
                    if ($ExAzureVMList -notcontains ($($VM.Name))) {
                        $ActualAzureVMList += $VM
                    }
                }
            } else {
                $ActualAzureVMList = $AzureVMList
            }

            Write-Output $($ActualAzureVMList)

            Write-Output "End of resources where tag $($TagName) is $($seq)..."
        }
    }
}

function PerformActionOnSequencedTaggedVMList($Sequences, [string]$Action, $TagName, [string[]]$AzVMList) {
    $AllVMs = Get-AzVM

    foreach ($seq in $Sequences) {
        $AzureVMList = @()
        $AzureVMListTemp = @()

        if ($WhatIf -eq $false) {
            Write-Output "Performing the $($Action) action against VM's where the tag $($TagName) is $($seq)."

            $AllVMResources = Get-AzResource -TagValue $seq | Where-Object { ($_.ResourceType -eq 'Microsoft.Compute/virtualMachines') }

            foreach ($vm in $AzVMList) {
                $AzureVMList += $AllVMResources | Where-Object Name -EQ $vm.Trim() | Select-Object Name, ResourceGroupName
            }

            foreach ($VM in $AzureVMList) {
                $FilterTagVMs = $AllVMs | Where-Object ResourceGroupName -EQ $VM.ResourceGroupName | Where-Object Name -EQ $VM.Name

                $CaseSensitiveTagName = $FilterTagVMs.Tags.Keys | Where-Object -FilterScript { $_ -eq $TagName }

                if ($null -ne $CaseSensitiveTagName) {
                    if ($FilterTagVMs.Tags[$CaseSensitiveTagName] -eq $seq) {
                        $AzureVMListTemp += $FilterTagVMs | Select-Object Name, ResourceGroupName
                    }
                }
            }
            $AzureVMList = $AzureVMListTemp

            $ActualVMListOutput = @()

            foreach ($vmObj in $AzureVMList) {
                $ActualVMListOutput = $ActualVMListOutput + $vmObj.Name + ' '
                Write-Output "Executing runbook ScheduledStartStop_Child to perform the $($Action) action on VM: $($vmobj.Name)"
                $params = @{'VMName' = "$($vmObj.Name)"; 'Action' = $Action; 'ResourceGroupName' = "$($vmObj.ResourceGroupName)" }

                #Retry logic for Start-AzAutomationRunbook cmdlet

                [string] $FailureMessage = 'Failed to execute the Start-AzAutomationRunbook command'
                [int] $RetryCount = 3
                [int] $TimeoutInSecs = 20
                $RetryFlag = $true
                $Attempt = 1

                do {
                    try {
                        $runbook = Start-AzAutomationRunbook -AutomationAccountName $automationAccountName -Name 'ScheduledStartStop_Child' -ResourceGroupName $aroResourceGroupName –Parameters $params

                        Write-Output "Triggered the child runbook for ARM VM : $($vmObj.Name)"

                        $RetryFlag = $false
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

            if ($null -ne $ActualVMListOutput) {
                Write-Output "~Attempted the $($Action) action on the following VMs in sequence $($seq): $($ActualVMListOutput)"
            }

            Write-Output "Completed the sequenced $($Action) against VM's where the tag $($TagName) is $($seq)."

            if (($Action -eq 'stop' -and $seq -ne $Sequences.Count) -or ($Action -eq 'start' -and $seq -ne [int]$Sequences.Count - ([int]$Sequences.Count - 1))) {
                Write-Output 'Validating the status before processing the next sequence...'
            }

            foreach ($vmObjStatus in $AzureVMList) {
                [int]$SleepCount = 0

                $CheckVMStatus = CheckVMState -VMObject $vmObjStatus -Action $Action

                While ($CheckVMStatus -eq $false) {
                    Write-Output 'Checking the VM Status in 15 seconds...'

                    Start-Sleep -Seconds 15

                    $SleepCount += 15

                    if ($SleepCount -gt $maxWaitTimeForVMRetryInSeconds -and $ContinueOnError -eq $false) {
                        Write-Output "Unable to $($Action) the VM $($vmObjStatus.Name). ContinueOnError is set to False, hence terminating the sequenced $($Action)..."

                        Write-Output "Completed the sequenced $($Action)..."

                        exit
                    } elseif ($SleepCount -gt $maxWaitTimeForVMRetryInSeconds -and $ContinueOnError -eq $true) {
                        Write-Output "Unable to $($Action) the VM $($vmObjStatus.Name). ContinueOnError is set to True, hence moving to the next resource..."

                        break
                    }
                    $CheckVMStatus = CheckVMState -VMObject $vmObjStatus -Action $Action
                }
            }
        } elseif ($WhatIf -eq $true) {
            Write-Output 'WhatIf parameter is set to True...'

            Write-Output "When 'WhatIf' is set to TRUE, runbook provides a list of Azure Resources (e.g. VMs), that will be impacted if you choose to deploy this runbook."

            Write-Output "No action will be taken at this time. These are the resources where the tag $($TagName) is $($seq)..."

            $AllVMResources = Get-AzResource -TagValue $seq | Where-Object { ($_.ResourceType -eq 'Microsoft.Compute/virtualMachines') }

            foreach ($vm in $AzVMList) {
                $AzureVMList += $AllVMResources | Where-Object Name -EQ $vm.Trim() | Select-Object Name, ResourceGroupName
            }

            foreach ($VM in $AzureVMList) {
                $FilterTagVMs = $AllVMs | Where-Object ResourceGroupName -EQ $VM.ResourceGroupName | Where-Object Name -EQ $VM.Name

                $CaseSensitiveTagName = $FilterTagVMs.Tags.Keys | Where-Object -FilterScript { $_ -eq $TagName }

                if ($null -ne $CaseSensitiveTagName) {
                    if ($FilterTagVMs.Tags[$CaseSensitiveTagName] -eq $seq) {
                        $AzureVMListTemp += $FilterTagVMs | Select-Object Name, ResourceGroupName
                    }
                }
            }

            $ActualAzureVMList = $AzureVMListTemp

            Write-Output $($ActualAzureVMList)

            Write-Output "End of resources where tag $($TagName) is $($seq)..."
        }
    }
}
function CheckVMState ($VMObject, [string]$Action) {
    [bool]$IsValid = $false

    $CheckVMState = (Get-AzVM -ResourceGroupName $VMObject.ResourceGroupName -Name $VMObject.Name -Status -ErrorAction SilentlyContinue).Statuses.Code[1]
    if ($Action.ToLower() -eq 'start' -and $CheckVMState -eq 'PowerState/running') {
        $IsValid = $true
    } elseif ($Action.ToLower() -eq 'stop' -and $CheckVMState -eq 'PowerState/deallocated') {
        $IsValid = $true
    }
    return $IsValid
}


function CheckValidAzureVM ($FilterVMList) {
    [string[]] $invalidvm = @()
    $VMListARM = @()

    $VMListARM = Get-AzResource -ResourceType Microsoft.Compute/virtualMachines

    foreach ($filtervm in $FilterVMList) {
        $VMARMTemp = $VMListARM | Where-Object name -Like $filtervm.Trim()

        if ($null -eq $VMARMTemp) {
            $invalidvm = $invalidvm + $filtervm
        }
    }

    if ($null -ne $invalidvm) {
        Write-Output "Runbook Execution Stopped! Invalid VM Name(s) in the list: $($invalidvm) "
        Write-Warning "Runbook Execution Stopped! Invalid VM Name(s) in the list: $($invalidvm) "
        exit
    } else {
        $ExAzureVMList = @()

        foreach ($vm in $FilterVMList) {
            $NewVM = $VMListARM | Where-Object name -Like $vm

            if ($null -ne $NewVM) {
                foreach ($nvm in $NewVM) {
                    $ExAzureVMList += @{Name = $nvm.Name; ResourceGroupName = $nvm.ResourceGroupName; Type = 'ResourceManager' }
                }
            }
        }

        return $ExAzureVMList
    }
}

# ------------------Execution Entry point ---------------------

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
$automationAccountName = Get-AutomationVariable -Name 'Internal_AutomationAccountName'
$aroResourceGroupName = Get-AutomationVariable -Name 'Internal_ResourceGroupName'
$maxWaitTimeForVMRetryInSeconds = Get-AutomationVariable -Name 'External_WaitTimeForVMRetryInSeconds'
$StartResourceGroupNames = Get-AutomationVariable -Name 'External_Start_ResourceGroupNames'
$StopResourceGroupNames = Get-AutomationVariable -Name 'External_Stop_ResourceGroupNames'
$ExcludeVMNames = Get-AutomationVariable -Name 'External_ExcludeVMNames'

try {
    $Action = $Action.Trim().ToLower()

    if (!($Action -eq 'start' -or $Action -eq 'stop')) {
        Write-Output "`$Action parameter value is : $($Action). Value should be either start or stop."
        Write-Output 'Completed the runbook execution...'
        exit
    }

    #If user gives the VM list with comma seperated....
    [string[]] $AzVMList = $VMList -split ','

    #Validate the Exclude List VM's and stop the execution if the list contains any invalid VM
    if (([string]::IsNullOrEmpty($ExcludeVMNames) -ne $true) -and ($ExcludeVMNames -ne 'none')) {
        Write-Output "Values exist on the VM's Exclude list. Checking resources against this list..."
        [string[]] $VMfilterList = $ExcludeVMNames -split ','
        $ExAzureVMList = CheckValidAzureVM -FilterVMList $VMfilterList
    }

    if ($Action -eq 'stop') {
        [string[]] $VMRGList = $StopResourceGroupNames -split ','
    }
    if ($Action -eq 'start') {
        [string[]] $VMRGList = $StartResourceGroupNames -split ','
    }

    Write-Output "Executing the Sequenced $($Action)..."
    Write-Output 'Input parameter values...'
    Write-Output "`$Action : $($Action)"
    Write-Output "`$WhatIf : $($WhatIf)"
    Write-Output "`$ContinueOnError : $($ContinueOnError)"
    Write-Output "Filtering the tags across all the VM's..."

    $startTagValue = 'sequencestart'
    $stopTagValue = 'sequencestop'
    $startTagKeys = Get-AzVM | Where-Object { $_.Tags.Keys -eq $startTagValue.ToLower() } | Select-Object Tags
    $stopTagKeys = Get-AzVM | Where-Object { $_.Tags.Keys -eq $stopTagValue.ToLower() } | Select-Object Tags
    $startSequences = [System.Collections.ArrayList]@()
    $stopSequences = [System.Collections.ArrayList]@()

    foreach ($tag in $startTagKeys.Tags) {
        foreach ($key in $($tag.keys)) {
            if ($key.ToLower() -eq $startTagValue.ToLower()) {
                [void]$startSequences.add([int]$tag[$key])
            }
        }
    }

    foreach ($tag in $stopTagKeys.Tags) {
        foreach ($key in $($tag.keys)) {
            if ($key.ToLower() -eq $stopTagValue.ToLower()) {
                [void]$stopSequences.add([int]$tag[$key])
            }
        }
    }

    $startSequences = $startSequences | Sort-Object -Unique
    $stopSequences = $stopSequences | Sort-Object -Unique

    if ($Action -eq 'start') {
        if ($null -ne $AzVMList) {
            $AzureVMList = CheckValidAzureVM -FilterVMList $AzVMList

            PerformActionOnSequencedTaggedVMList -Sequences $startSequences -Action $Action -TagName $startTagValue -AzVMList $AzVMList
        } else {
            if (($null -ne $VMRGList) -and ($VMRGList -ne '*')) {
                PerformActionOnSequencedTaggedVMRGs -Sequences $startSequences -Action $Action -TagName $startTagValue -VMRGList $VMRGList -ExcludeList $VMfilterList
            } else {
                PerformActionOnSequencedTaggedVMAll -Sequences $startSequences -Action $Action -TagName $startTagValue -ExcludeList $VMfilterList
            }
        }
    }

    if ($Action -eq 'stop') {
        if ($null -ne $AzVMList) {
            $AzureVMList = CheckValidAzureVM -FilterVMList $AzVMList

            PerformActionOnSequencedTaggedVMList -Sequences $stopSequences -Action $Action -TagName $stopTagValue -AzVMList $AzVMList
        } else {
            if (($null -ne $VMRGList) -and ($VMRGList -ne '*')) {
                PerformActionOnSequencedTaggedVMRGs -Sequences $stopSequences -Action $Action -TagName $stopTagValue -VMRGList $VMRGList -ExcludeList $VMfilterList
            } else {
                PerformActionOnSequencedTaggedVMAll -Sequences $stopSequences -Action $Action -TagName $stopTagValue -ExcludeList $VMfilterList
            }
        }
    }


    Write-Output "Completed the sequenced $($Action)..."
} catch {
    Write-Output "Error Occurred in the sequence $($Action) runbook..."
    Write-Output $_.Exception
}
