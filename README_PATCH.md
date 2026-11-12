# GoldVuee Direct Update Patch v4

Fixes the exact errors from dry-run 0AfjV000006MuJSSA0:

- `GVCartController.cls` contains an instance `InventoryAvailabilityReader.available()` method and **both** call sites instantiate the reader.
- Apex source is saved as UTF-8 **without BOM** to avoid `Invalid identifier` at line 1.
- `GVAbandonedCheckoutService.cls` and metadata are included alongside checkout classes.
- Deployment script uses explicit source files and validates local tests in dry-run mode by default.

## Install

1. Back up the existing `force-app` directory.
2. Extract this ZIP **into the Salesforce project root** (the directory containing `sfdx-project.json`), merging `force-app` and replacing the patch files.
3. From that directory, validate:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\deploy-goldvuee-patch.ps1" -TargetOrg goldvuee-dev
```

Do **not** deploy unless validation passes. This patch has not been tested against your org. Do not run the earlier PowerShell `Set-Content -Encoding UTF8` fix on Apex source: Windows PowerShell 5.1 writes a BOM.

If errors remain, share the full component failures and test failures; do not deploy.
