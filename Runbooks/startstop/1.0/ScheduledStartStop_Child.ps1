<#
.SYNOPSIS
 Wrapper script for start & stop AzureRM VM's
.DESCRIPTION
 Wrapper script for start & stop AzureRM VM's
.EXAMPLE
.\ScheduledStartStop_Child.ps1 -VMName "Value1" -Action "Value2" -ResourceGroupName "Value3"
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

        Write-Output "VM action is : $($Action)"

        if ($Action.Trim().ToLower() -eq 'stop') {
            Write-Output "Stopping the Virtual Machine : $($VMName)"

            $Status = Stop-AzVM -Name $VMName -ResourceGroupName $ResourceGroupName -Force

            if ($Status -eq $null) {
                Write-Output "Error occurred while stopping the Virtual Machine $($VMName) hence retrying..."

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
                Write-Output "Successfully stopped the Virtual Machine : $($VMName)"

                $RetryFlag = $false
            }
        } elseif ($Action.Trim().ToLower() -eq 'start') {
            Write-Output "Starting the Virtual Machine : $($VMName)"

            $Status = Start-AzVM -Name $VMName -ResourceGroupName $ResourceGroupName

            if ($Status -eq $null) {
                Write-Output "Error occurred while starting the Virtual Machine $($VMName) hence retrying..."

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
                Write-Output "Successfully started the Virtual Machine : $($VMName)"

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
