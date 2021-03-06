[CmdletBinding()]
Param (
    [Parameter(Mandatory = $true)]
    [String] $azureSubscriptionId,
    [Parameter(Mandatory = $true)]
    [String] $azureTenantId,
    [Parameter(Mandatory = $true)]
    [String] $resourceGroupName,
    [Parameter(Mandatory = $true)]
    [String] $appServiceNameOrch,
    [Parameter(Mandatory = $true)]
    [String] $appServiceNameIdentity,
    [Parameter(Mandatory = $true)]
    [String] $appServiceNameWebhooks,
    [Parameter(Mandatory = $false)]
    [String] $action,
    [Parameter(Mandatory = $true)]
    [String] $hostAdminPassword,
    [Parameter(Mandatory = $false)]
    [String] $defaultTenantAdminPassword,
    [Parameter(Mandatory = $false)]
    [String] $storageLocation,
    [Parameter(Mandatory = $false)]
    [String] $redisConnectionString,
    [Parameter(Mandatory = $false)]
    [String] $azureSignalRConnectionString,
    [Parameter(Mandatory = $false)]
    [ValidateScript( { if (($_ -as [System.URI]).AbsoluteURI -eq $null) { throw "Invalid" } return $true })]
    [String] $identityServerUrl,
    [Parameter(Mandatory = $false)]
    [ValidateScript( { if (($_ -as [System.URI]).AbsoluteURI -eq $null) { throw "Invalid" } return $true })]
    [String] $orchestratorUrl,
    [Parameter(Mandatory = $false)]
    [String] $insightsKey,
    [Parameter(Mandatory = $false)]
    [ValidateScript( { if (-Not ($_ | Test-Path -PathType Leaf)) { throw "UiPath orchestrator web package is not valid." } return $true })]
    [String] $orchestratorPackage = "UiPath.Orchestrator.Web.zip",
    [Parameter(Mandatory = $false)]
    [ValidateScript( { if (-Not ($_ | Test-Path -PathType Leaf)) { throw "UiPath identity web package is not valid." } return $true })]
    [String] $identityPackage = "UiPath.IdentityServer.Web.zip",
    [Parameter(Mandatory = $false)]
    [ValidateScript( { if (-Not ($_ | Test-Path -PathType Leaf)) { throw "UiPath identity migrator package is not valid." } return $true })]
    [String] $identityCliPackage = "UiPath.IdentityServer.Migrator.Cli.zip",
    [Parameter(Mandatory = $false)]
    [ValidateScript( { if (-Not ($_ | Test-Path -PathType Leaf)) { throw "UiPath webhooks web package is not valid." } return $true })]
    [String] $webhookServicePackage = "UiPath.WebhookService.Web.zip",
    [Parameter(Mandatory = $false)]
    [ValidateScript( { if (-Not ($_ | Test-Path -PathType Leaf)) { throw "UiPath webhooks cli package is not valid." } return $true })]
    [String] $webhookMigrateCliPackage = "UiPath.WebhookService.Migrator.Cli.zip"
)
$global:stepCount = 1

Write-Output "$env:System.DefaultWorkingDirectory"

Write-Output "$(Get-Date) Unzipping ps_utils..."
Expand-Archive -LiteralPath "d:/a/1/s/Azure/Orchestrator/20.10.1/ps_utils.zip" -DestinationPath . -Force
Enable-AzureRmAlias

Write-Output "$(Get-Date) Importing custom modules..."
Import-Module ([System.IO.Path]::GetFullPath((Join-Path (Get-Location) "./ps_utils/CloudDeploymentUtils.ps1"))) -Global -Force
Write-Output "$(Get-Date) Done importing custom modules..."

function Main {
    $ErrorActionPreference = "Stop"
    
    $logFile = "Installation.log"
    Start-Transcript -Path $logFile -Append -IncludeInvocationHeader

    PublishOrchestrator
    PublishIdentityServer
    MigrateToIdentityServer
    PublishWebhooks
    MigrateToWebhooks
    Write-Output " ******* $(Get-Date) Orchestrator installation complete *******"
    Stop-Transcript
}

function InstallMSDeploy {
    Write-Output "$(Get-Date) Installing MSDeploy..."
    $msiExecArgs = "/i `"WebDeploy_amd64_en-US.msi`" /q /norestart LicenseAccepted=""0"" /l*vx `"webdeployInstallation.log`" "
    Start-Process "msiexec" -ArgumentList $msiExecArgs -Wait -PassThru
    $msdeployFile = "C:\Program Files (x86)\IIS\Microsoft Web Deploy V3\msdeploy.exe"

    if (Test-Path $msdeployFile) {
        Write-Output "$(Get-Date) MSDeploy path valid: $msdeployFile"
    }
    else {
        Write-Output "$(Get-Date) MSDeploy path invalid: $msdeployFile"
        Exit 1
    }
}

function LoginToAzure {
    Write-Output "$(Get-Date) Login with MSI..."
    Connect-AzureRmAccount -Identity -AccountId $azureMSIApplicationId -SubscriptionId $azureSubscriptionId -TenantId $azureTenantId -ErrorAction Stop
    Write-Output "$(Get-Date) Logged in with MSI."
}
function PublishOrchestrator {
    Write-Output "******* $(Get-Date) Step $global:stepCount: Publish orchestrator script: ******* "
    
    d:/a/1/s/Azure/Orchestrator/20.10.1/Publish-Orchestrator.ps1 -action $action -unattended -package 'D:\a\1\a\BlobFile\UiPath.Orchestrator.Web.zip' -stopApplicationBeforePublish -azureSubscriptionId $azureSubscriptionId -azureAccountTenantId $azureTenantId -resourceGroupName $resourceGroupName -appServiceName $appServiceNameOrch -hostAdminPassword $hostAdminPassword -defaultTenantAdminPassword $defaultTenantAdminPassword -storageType "Azure" -storageLocation $storageLocation -noAzureAuthentication -verbose
    
    IncrementStepCount
}

function PublishIdentityServer {
    Write-Output "******* $(Get-Date) Step $global:stepCount: publish identity script: *******"
    d:/a/1/s/Azure/Orchestrator/20.10.1/Publish-IdentityServer.ps1 -action $action -azureSubscriptionId $azureSubscriptionId -azureAccountTenantId $azureTenantId -package 'D:\a\1\a\BlobFile\UiPath.IdentityServer.Web.zip' -cliPackage 'D:\a\1\a\BlobFile\UiPath.IdentityServer.Migrator.Cli.zip' -stopApplicationBeforePublish -resourceGroupName $resourceGroupName -appServiceName $appServiceNameIdentity -orchestratorUrl $orchestratorUrl -noAzureAuthentication -unattended
    
    IncrementStepCount
}

function MigrateToIdentityServer {
    Write-Output "******* $(Get-Date) Step $global:stepCount: migrate to identity script: *******"
    d:/a/1/s/Azure/Orchestrator/20.10.1/MigrateTo-IdentityServer.ps1 -cliPackage 'D:\a\1\a\BlobFile\UiPath.IdentityServer.Migrator.Cli.zip' -orchDetails @{ resourceGroupName = $resourceGroupName; appServiceName = $appServiceNameOrch; targetSlot = "Production" } -identityServerDetails @{ resourceGroupName = $resourceGroupName; appServiceName = $appServiceNameIdentity; targetSlot = "Production" } -identityServerUrl $identityServerUrl -orchestratorUrl $orchestratorUrl -noAzureAuthentication
    
    IncrementStepCount
}

function PublishWebhooks {
    Write-Output "*******  $(Get-Date) Step $global:stepCount: publish web hooks script: ******* "
    d:/a/1/s/Azure/Orchestrator/20.10.1/Publish-Webhooks.ps1 -action $action -azureSubscriptionId $azureSubscriptionId -appServiceName $appServiceNameWebhooks -resourceGroupName $resourceGroupName -package 'D:\a\1\a\BlobFile\UiPath.WebhookService.Web.zip' -stopApplicationBeforePublish -noAzureAuthentication
    
    IncrementStepCount
}

function MigrateToWebhooks {
    Write-Output "*******  $(Get-Date) Step $global:stepCount: migrate to web hooks script: ******* "
    d:/a/1/s/Azure/Orchestrator/20.10.1/MigrateTo-Webhooks.ps1 -cliPackage 'D:\a\1\a\BlobFile\UiPath.WebhookService.Migrator.Cli.zip' -orchDetails @{ resourceGroupName = $resourceGroupName; appServiceName = $appServiceNameOrch; targetSlot = "Production" } -webhookDetails @{ resourceGroupName = $resourceGroupName; appServiceName = $appServiceNameWebhooks; targetSlot = "Production" } -noAzureAuthentication
    
    IncrementStepCount
}

function IncrementStepCount {
    $global:stepCount++
}

Main
