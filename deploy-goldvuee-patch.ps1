param(
    [string]$TargetOrg = "goldvuee-dev",
    [switch]$Deploy
)

$ErrorActionPreference = "Stop"

if (-not (Get-Command sf -ErrorAction SilentlyContinue)) {
    throw "Salesforce CLI (sf) is not installed or is not on PATH."
}
if (-not (Test-Path "sfdx-project.json")) {
    throw "Run from the Salesforce project root containing sfdx-project.json."
}

$paths = @(
    "force-app/main/default/classes/GVCartController.cls",
    "force-app/main/default/classes/GVCheckoutController.cls",
    "force-app/main/default/classes/GVCheckoutControllerTest.cls",
    "force-app/main/default/classes/GVAbandonedCheckoutService.cls",
    "force-app/main/default/objects/Jewellery_Product__c/fields/Availability_Status__c.field-meta.xml"
)

# Fail early if the old invalid cart method is still installed.
$cartCode = Get-Content "force-app/main/default/classes/GVCartController.cls" -Raw
if ($cartCode -match 'private\s+static\s+Decimal\s+available\s*\(') {
    throw "Old GVCartController is still installed: remove static from the inner class available() method before validation."
}
if ($cartCode -notmatch 'private\s+Decimal\s+available\s*\(') {
    throw "Expected corrected instance availability method was not found."
}
if (($cartCode | Select-String -Pattern '\(new InventoryAvailabilityReader\(\)\)\.available\(' -AllMatches).Matches.Count -ne 2) {
    throw "Expected both cart availability call sites to instantiate InventoryAvailabilityReader."
}
$cartBytes = [System.IO.File]::ReadAllBytes((Resolve-Path "force-app/main/default/classes/GVCartController.cls").Path)
if ($cartBytes.Length -ge 3 -and $cartBytes[0] -eq 239 -and $cartBytes[1] -eq 187 -and $cartBytes[2] -eq 191) {
    throw "GVCartController.cls has a UTF-8 BOM. Install the v4 source file."
}
Write-Host "Cart Apex preflight: OK" -ForegroundColor Green

foreach ($path in $paths) {
    if (-not (Test-Path $path)) {
        throw "Required patch file missing: $path"
    }
}

$sfArgs = @("project", "deploy", "start", "--target-org", $TargetOrg)
foreach ($path in $paths) {
    $sfArgs += @("--source-dir", $path)
}
$sfArgs += @("--test-level", "RunLocalTests", "--wait", "30")

if (-not $Deploy) {
    $sfArgs += "--dry-run"
    Write-Host "MODE: VALIDATION ONLY - no changes to org" -ForegroundColor Cyan
} else {
    Write-Host "MODE: DEPLOYMENT to $TargetOrg" -ForegroundColor Yellow
}

Write-Host "Target org: $TargetOrg"
& sf @sfArgs
if ($LASTEXITCODE -ne 0) {
    throw "Salesforce validation or deployment failed (exit code $LASTEXITCODE)."
}
Write-Host "Salesforce command completed successfully." -ForegroundColor Green
