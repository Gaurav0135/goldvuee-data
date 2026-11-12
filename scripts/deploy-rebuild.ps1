param([string]$TargetOrg='goldvuee-dev')
$ErrorActionPreference='Stop'
Push-Location (Join-Path $PSScriptRoot '..')
try {
    $org=& sf data query --target-org $TargetOrg --query 'SELECT OrganizationType,IsSandbox FROM Organization' --json | ConvertFrom-Json
    if($org.status -ne 0 -or !($org.result.records[0].IsSandbox -or $org.result.records[0].OrganizationType -eq 'Developer Edition')){throw 'Refusing deployment: target is not a verified development/test org.'}
    & sf apex run --target-org $TargetOrg --file scripts/pause-reconciliation-for-deploy.apex --json | Set-Content -Encoding utf8 reconciliation-pause-result.json
    if($LASTEXITCODE -ne 0){throw 'Unable to pause the rebuild maintenance schedule.'}
    $result=& sf project deploy start --target-org $TargetOrg --source-dir force-app --test-level RunLocalTests --wait 30 --json
    $code=$LASTEXITCODE
    $result | Set-Content -Encoding utf8 rebuild-deploy.json
    if($code -ne 0){throw 'Full deployment/test gate failed. See rebuild-deploy.json.'}
    & "$PSScriptRoot/configure-subscriber.ps1" -TargetOrg $TargetOrg
    & sf community publish --target-org $TargetOrg --name GoldVuee --json | Set-Content -Encoding utf8 site-publish-result.json
    if($LASTEXITCODE -ne 0){throw 'Experience site publication failed.'}
} finally {
    & sf apex run --target-org $TargetOrg --file scripts/enable-reconciliation.apex --json | Set-Content -Encoding utf8 reconciliation-setup-result.json
    Pop-Location
}
