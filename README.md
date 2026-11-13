# Salesforce DX Project

Salesforce DX is a development approach that brings source-driven development, team collaboration, and continuous integration to the Salesforce Platform. Instead of working directly in an org through a web browser, you work with metadata as source files in a local DX project, track changes in version control, and deploy through automated processes.

This project template gets you started with the tools and structure you need to build Salesforce applications using source control, scratch orgs, and the Salesforce CLI.

## Prerequisites

Before you start, make sure you have:

- **Salesforce CLI** - Download from [developer.salesforce.com/tools/salesforcecli](https://developer.salesforce.com/tools/salesforcecli). See [Install Salesforce CLI](https://developer.salesforce.com/docs/atlas.en-us.sfdx_setup.meta/sfdx_setup/sfdx_setup_install_cli.htm) for details.
- **VS Code with Salesforce Extension Pack** - See [Installation Instructions](https://developer.salesforce.com/docs/platform/sfvscode-extensions/guide/install.html) for details. Includes the Agentforce Vibes extension.
- **A development org** - Sign up for a free Developer Edition org [here](https://developer.salesforce.com/signup).
- **Dev Hub enabled** (optional, required to create scratch orgs) - You can enable Dev Hub in your development org under Setup > Dev Hub.  See [Provide Developers Access to Salesforce DX Tools](https://developer.salesforce.com/docs/atlas.en-us.sfdx_dev.meta/sfdx_dev/sfdx_setup_dx_tools.htm).

## Project Structure

Your DX project follows this structure:

- **`force-app/main/default/`** - Your metadata source files live in this default package directory. You can configure additional package directories in the `sfdx-project.json` file.
- **`config/`** - Scratch org definitions and project settings
- **`scripts/`** - Automation scripts for common tasks
- **`sfdx-project.json`** - Project manifest that defines package directories, namespace, API version, and other project-level settings

See [Salesforce DX Project Configuration](https://developer.salesforce.com/docs/atlas.en-us.sfdx_dev.meta/sfdx_dev/sfdx_dev_ws_config.htm).

## Get Started

Ready to start developing? The [Get Started with Salesforce DX](https://developer.salesforce.com/docs/atlas.en-us.sfdx_dev.meta/sfdx_dev/sfdx_dev_get_started_dx.htm) guide walks you through your first project, from creating a scratch org to creating a simple Apex class or LWC to deploying your code to a sandbox.

## Common Salesforce CLI Commands

Here are common CLI commands that you'll use the most:

- `sf org login web`: Authorize an org
- `sf org open`: Open your org in a browser
- `sf org create scratch`: Create a scratch org
- `sf project deploy start`: Deploy metadata to your org
- `sf project retrieve start`: Retrieve metadata from your org
- `sf template generate <artifact>`: Scaffold new components, such as Apex classes and triggers, LWC components, Lightning apps, and more
- `sf apex <command>`: Run Apex tests, run anonymous Apex blocks, and view logs
- `sf data <command>`: Work with test data
- `sf alias <command>`: Manage org aliases
- `sf config <command>`: Configure CLI settings

## Use Agentforce Vibes to Build Lightning Apps

Transform your ideas into custom Lightning apps that extend CRM workflows directly in Lightning Experience. Through natural conversations with Agentforce Vibes, implement custom objects and fields, complex business logic, and dynamic UI components. See [Build a Lightning App Using Agentforce Vibes](https://developer.salesforce.com/docs/platform/einstein-for-devs/guide/lexapp-overview.html).

## Additional Resources

- [Agentforce Vibes Developer Guide](https://developer.salesforce.com/docs/platform/einstein-for-devs/guide/einstein-overview.html)
- [Salesforce CLI Installation Guide](https://developer.salesforce.com/docs/atlas.en-us.sfdx_setup.meta/sfdx_setup/sfdx_setup_intro.htm)
- [Salesforce DX Developer Guide](https://developer.salesforce.com/docs/atlas.en-us.sfdx_dev.meta/sfdx_dev/)
- [Salesforce CLI Command Reference](https://developer.salesforce.com/docs/atlas.en-us.sfdx_cli_reference.meta/sfdx_cli_reference/)
- [Salesforce CLI Plugin Development Guide](https://developer.salesforce.com/docs/platform/salesforce-cli-plugin/guide/conceptual-overview.html)
- [Salesforce VS Code Extensions Documentation](https://developer.salesforce.com/tools/vscode/)

## GoldVuee navbar

The runnable browser prototype is in [`prototype/`](C:/GoldVuee/goldvuee/prototype).
Open [`prototype/index.html`](C:/GoldVuee/goldvuee/prototype/index.html) directly in a
browser, or serve it with:

```text
cd C:\GoldVuee\goldvuee\prototype
py -m http.server 8080
```

Then visit `http://localhost:8080`. Its navigation, search, counts, and account toggle
are demo behavior only; it does not perform checkout or authentication.

The Salesforce Experience Cloud component is
[`goldvueeHeader`](C:/GoldVuee/goldvuee/force-app/main/default/lwc/goldvueeHeader).
Deploy it with:

```text
sf project deploy start --source-dir force-app/main/default/lwc/goldvueeHeader
```

Add **GoldVuee Luxury Navbar** to an Experience Builder page. `wishlistCount` and
`bagCount` are configurable properties. `routes` accepts optional JSON overrides, such
as `{"collections":"/shop"}`. The component uses Salesforce guest context and
`lightning/navigation` for internal navigation.

Live wishlist and bag counts still need to be supplied by the storefront state layer or
an Apex/Commerce API integration. No custom object or field API names are assumed.
Login, registration, logout, and session handling must be configured in Experience
Cloud authentication; the component does not invent authentication or checkout.

## Clean hosted checkout (13 November 2026)

The active checkout uses `GVCartController`, `GVCheckoutController`, `GVRazorpayController`, `GVPaymentWebhook` and internal `GVCheckoutService`. Cart/checkout/result UI is LWC; hosted Razorpay Payment Links handle payment entry. New checkout never creates stock reservations. Inventory is deducted only after verified capture, and captured stock exceptions remain paid.

Use the narrow `manifest/clean-checkout.xml` deployment manifest. Read [the operational runbook](verification/clean-checkout/RUNBOOK.md), [actual validation results](verification/clean-checkout/RESULTS.md), [schema mapping](verification/clean-checkout/SCHEMA-MAPPING.md) and [retrieved field definitions](verification/clean-checkout/FIELD-METADATA.md) before enabling payments. Test Mode, webhook access/signing configuration and live end-to-end acceptance still require completion. Archived source is under `backups/clean-checkout-20261113/source`; it is outside the deployment package. Org metadata deletion needs a separate dependency review and was not executed.

## Urgent cart and checkout corrections

The deployed follow-up removes payment-based cart freezing, preserves old payable snapshots while editing an independent current bag, fixes address normalization/navigation and adds the 120-second verified-payment monitoring window. See [the current fix report and remaining payment setup](verification/urgent-checkout/REPORT.md). This supersedes the earlier frozen-cart behavior. Deployment 0AfjV000006QL3lSAG passed 28 Apex tests; the local LWC suite passed 32 tests. Actual hosted-payment acceptance still requires the configuration listed in the report.
