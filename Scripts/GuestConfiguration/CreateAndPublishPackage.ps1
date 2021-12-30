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
        "Platform" = "Windows/Linux"
        "Version" = "1.0.0.0"
        "Mode" = "ApplyAndMonitor/ApplyAndAutoCorrect/Audit"
        "Tag" = @{"TagName"="TagValue"}
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

if ($PublishPackage -and $StorageAccountName -and $ResourceGroupName) {
    $ContentUri = Publish-GuestConfigurationPackage -Path $package.Path -ResourceGroupName $ResourceGroupName -StorageAccountName $StorageAccountName -StorageContainerName $StorageContainerName -Force | ForEach-Object ContentUri
}

if ($PolicyParameters.Count -gt 0 -and $contentUri) {
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

    if ($PublishPolicy) {
        Publish-GuestConfigurationPolicy -Path $PolicyParameters['Path']
    }
}
