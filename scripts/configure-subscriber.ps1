param([string]$TargetOrg='goldvuee-dev')
$ErrorActionPreference='Stop'
# Only an existing administrator with encrypted-data access and the assigned operations role is eligible.
# The username is an environment reference; it is never printed or used as an authentication credential.
$query="SELECT Assignee.Username,Assignee.Profile.PermissionsViewEncryptedData,Assignee.Profile.PermissionsModifyAllData FROM PermissionSetAssignment WHERE PermissionSet.Name='GoldVuee_Operations' AND Assignee.IsActive=true"
$response=& sf data query --target-org $TargetOrg --query $query --json | ConvertFrom-Json
if($response.status -ne 0){throw 'Subscriber user lookup failed.'}
$eligible=@($response.result.records | Where-Object {$_.Assignee.Profile.PermissionsModifyAllData})
if($eligible.Count -ne 1){throw 'Expected one existing operations administrator; configure a dedicated subscriber user.'}
$subscriberUser=[Security.SecurityElement]::Escape($eligible[0].Assignee.Username)
$directory=Join-Path $PSScriptRoot '../deployment-config/subscriber/platformEventSubscriberConfigs'
$null=New-Item -Path $directory -ItemType Directory -Force
$xml='<?xml version="1.0" encoding="UTF-8"?><PlatformEventSubscriberConfig xmlns="http://soap.sforce.com/2006/04/metadata"><batchSize>20</batchSize><masterLabel>GoldVuee Payment Verification</masterLabel><platformEventConsumer>GVPaymentVerificationProbe</platformEventConsumer><user>'+$subscriberUser+'</user></PlatformEventSubscriberConfig>'
[IO.File]::WriteAllText((Join-Path $directory 'GVPaymentVerification.platformEventSubscriberConfig-meta.xml'),$xml,(New-Object Text.UTF8Encoding($false)))
$result=& sf project deploy start --target-org $TargetOrg --source-dir (Split-Path $directory) --wait 10 --json
$exit=$LASTEXITCODE
$result | Set-Content -Encoding utf8 (Join-Path $PSScriptRoot '../subscriber-deploy-result.json')
if($exit -ne 0){throw 'Subscriber configuration deployment failed.'}
Write-Output 'Configured development subscriber with an existing authorized operations administrator.'
