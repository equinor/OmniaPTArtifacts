[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [String]$ConfigurationName = 'MyConfig',
    [Parameter(Mandatory = $false)]
    [ValidateSet('Audit', 'AuditAndSet')]
    [String]$ConfigurationType = 'Audit',
    [Parameter(Mandatory = $true)]
    [String]$ConfigurationFilePath,
    [Parameter(Mandatory = $true)]
    [String]$Version,
    [Parameter(Mandatory = $false)]
    [bool]$PublishPackage = $false,
    [Parameter(Mandatory = $false)]
    [String]$StorageAccountName,
    [Parameter(Mandatory = $false)]
    [String]$StorageContainerName = 'guestconfiguration',
    [Parameter(Mandatory = $false)]
    [String]$ResourceGroupName,
    [Parameter(Mandatory = $false)]
    [hashtable]$PolicyParameters = @{},
    [Parameter(Mandatory = $false)]
    [bool]$PublishPolicy = $false
)

if (!(Test-Path -Path $ConfigurationFilePath)) {
    throw "Configuration file $ConfigurationFilePath cound not be found. Please provide a valid mof file with full path."
}


$package = New-GuestConfigurationPackage `
    -Name 'MyConfig' `
    -Configuration $ConfigurationFilePath `
    -Type $ConfigurationType `
    -Force

if ($PublishPackage) {
    Publish-GuestConfigurationPackage -Path $package.Path -ResourceGroupName $ResourceGroupName -StorageAccountName $StorageAccountName -StorageContainerName $StorageContainerName -Force | ForEach-Object ContentUri
}

if ($PolicyParameters.Count -gt 0) {
    New-GuestConfigurationPolicy `
        -PolicyId $PolicyParameters['PolicyId'] `
        -ContentUri $PolicyParameters['ContentUri'] `
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
