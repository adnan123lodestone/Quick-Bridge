# Meta Activation Checklist

Use this checklist only after the Meta source has been deployed. Do not paste access tokens, app secrets, or webhook secrets into Salesforce fields, source control, or support tickets.

1. In Meta Business Manager, confirm the app has access to the selected Facebook Page, ad account, and Instagram Business Account. Grant only the approved lead, page-engagement, and ads-read permissions required by the configured features.
2. In Salesforce, create or update the Meta Named Credential and External Credential. Store token and secret material only in the approved credential store; QuickBridge configuration must contain references, not secret values.
3. Populate the Meta connector instance with the Page ID, ad account ID, Instagram Business Account ID, and credential-reference names. Configure lead source, Campaign Member status, lead creation mode, keyword rules, and field mappings.
4. Run `scripts/validateMetaConnector.apex`. Resolve every missing-field or placeholder failure before proceeding.
5. Run `scripts/activateMetaSchedules.apex`. It validates ad-account, Page, and configured Instagram-asset access before changing the paused Campaign and Insights schedules to `Ready`.
6. Configure the Meta webhook endpoint to the deployed `/services/apexrest/meta-webhook/` route and subscribe only to the supported Lead Ads and comment events. Confirm the GET challenge and signed POST validation.
7. Run controlled QA for one Facebook Lead Ad, one Instagram-placement Lead Ad, one Facebook comment, one Instagram comment, campaign hierarchy sync, insights sync, duplicate delivery, and a rejected-permission case.
8. Review Integration Work Items, Error Logs, and connector health. Do not enable recurring traffic until all expected jobs complete and any permission or payload errors are resolved.

Salesforce lead assignment, tasks, notifications, and nurture automation remain customer-specific. Configure those after the integration has produced correctly attributed Leads and Campaign Members.
