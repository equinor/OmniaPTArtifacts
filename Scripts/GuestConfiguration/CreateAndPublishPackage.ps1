<#
.SYNOPSIS
 Script for creating and publishing a Guest Configuration Package
.DESCRIPTION
 This script will create a Guest Configuration package based on an existing MOF DSC definition.
 If the relevant booleans and information is provided, it will also attempt to publish a config package,
 and create a Guest Configuration Policy.
.EXAMPLE
Will create a package and publish it to a specified storage account
.\CreateAndPubilshPackage.ps1 -ConfigurationName 'GuestConfig_Baseline' `
    -ConfigurationType 'AuditAndSet' `
    -ConfigurationFilePath '.\configurations\configurationfile.mof' `
    -PublishPackage $true `
    -StorageAccountName 'mystorageaccountname' `
    -ResourceGroupName 'MyResourceGroupName'

Will create a package, publish it, and create an Azure Policy for assigning it
$PolicyParameters = @{
    "PolicyId" = "1111-22222-3333-44444-55555"
    "DisplayName" = "MyDisplayName"
    "Description" = "MyDescription"
    "Path" = ".\myPolicyFiles"
    "Platform" = "Windows" # Can be either Windows or Linux
    "Version" = "1.0.0.0"
    "Mode" = "ApplyAndAutoCorrect" # Can be one of ApplyAndMonitor/ApplyAndAutoCorrect/Audit
    "Tag" = @{"Tag1Name"="Tag1Value";"Tag2Name"="Tag2Value"}
}
.\CreateAndPubilshPackage.ps1 -ConfigurationName 'GuestConfig_Baseline' `
    -ConfigurationType 'AuditAndSet' `
    -ConfigurationFilePath '.\configurations\configurationfile.mof' `
    -PublishPackage $true `
    -StorageAccountName 'mystorageaccountname' `
    -ResourceGroupName 'MyResourceGroupName' `
    -PolicyParameters $PolicyParameters
.NOTES
Version History
v0.1   - Initial Draft

#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [String]$ConfigurationName = 'MyConfig',
    [Parameter(Mandatory = $false)]
    [ValidateSet('Audit', 'AuditAndSet')]
    [String]$ConfigurationType = 'Audit',
    [Parameter(Mandatory = $true)]
    [String]$ConfigurationFilePath,
    [Parameter(Mandatory = $false)]
    [bool]$PublishPackage = $false,
    [Parameter(Mandatory = $false)]
    [String]$StorageAccountName,
    [Parameter(Mandatory = $false)]
    [String]$StorageContainerName = 'guestconfiguration',
    [Parameter(Mandatory = $false)]
    [String]$ResourceGroupName,
    [Parameter(Mandatory = $false)]
    [hashtable]$PolicyParameters = @{}
)

if (!(Test-Path -Path $ConfigurationFilePath)) {
    throw "Configuration file $ConfigurationFilePath cound not be found. Please provide a valid mof file with full path."
}


$package = New-GuestConfigurationPackage `
    -Name 'MyConfig' `
    -Configuration $ConfigurationFilePath `
    -Type $ConfigurationType `
    -Force

try {
    $storageAccount = Get-AzStorageAccount -Name $StorageAccountName -ResourceGroupName $ResourceGroupName -ErrorAction Stop
} catch {
    if (!$storageAccount) {
        Write-Output 'Could not find storage account. Will create one.'
        $storageAccount = New-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -SkuName 'Standard_LRS' -Kind StorageV2
    }
}

if ($storageAccount) {
    if ($PublishPackage) {
        Write-Output "Publishing Guest Configuration Package $($package.Path) to storage account $($storageAccount.StorageAccountName) in resource group $($storageAccount.ResourceGroupName)"
        $ContentUri = Publish-GuestConfigurationPackage -Path $package.Path -ResourceGroupName $storageAccount.ResourceGroupName -StorageAccountName $storageAccount.StorageAccountName -StorageContainerName $StorageContainerName -Force | ForEach-Object ContentUri
    }

    if ($PolicyParameters.Count -gt 0 -and $contentUri) {
        Write-Output 'Creating new Guest Configuration Policy with the following parameters'
        $PolicyParameters

        New-GuestConfigurationPolicy `
            -PolicyId $PolicyParameters['PolicyId'] `
            -ContentUri $ContentUri `
            -DisplayName $PolicyParameters['DisplayName'] `
            -Description $PolicyParameters['Description'] `
            -Path $PolicyParameters['Path'] `
            -Platform $PolicyParameters['Platform'] `
            -Version $PolicyParameters['Version'] `
            -Mode $PolicyParameters['Mode'] `
            -Tag $PolicyParameters['Tag'] `
            -Verbose

        if ($?) {
            Write-Output "Publishing Guest Configuration Policy from path $($PolicyParameters['Path'])"
            Publish-GuestConfigurationPolicy -Path $PolicyParameters['Path']
        }
    }
}
