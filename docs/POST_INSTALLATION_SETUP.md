# Quick Bridge Package v0.3.0.2 - Post-Installation Setup Guide

## Overview
After installing/upgrading the Quick Bridge package in your subscriber org sandbox, follow these steps to ensure proper configuration, validation, and functionality.

---

## Phase 1: Immediate Post-Installation Verification (5-10 minutes)

### 1.1 Verify Package Installation
1. **Navigate to:** Setup → Installed Packages
2. **Check:**
   - ✅ Quick Bridge v0.3.0.2 is listed
   - ✅ Status shows "Installed" or "Upgraded"
   - ✅ No error messages
3. **If upgrade from v0.4 Beta 3:**
   - Verify version was successfully replaced
   - Check Managed Package Activity log for any issues

### 1.2 Verify Custom Objects Exist
Run this SOQL query in Developer Console:
```soql
SELECT SObjectType FROM SObjectType 
WHERE NamespacePrefix = 'QuickBridge' 
ORDER BY SObjectType
LIMIT 100
```

**Expected Custom Objects (verify at least these core ones):**
- Credit_Memo__c
- CustomException__c
- Error_Log__c
- Integration_Product__c
- Integration_Work_Item__c
- Invoice__c
- Purchase_Order__c
- Integration_Work_Lock__c
- Item_Sales_Tax__c
- Portal_Payment_Transaction__c

### 1.3 Check for Installation Errors
**Location:** Setup → Setup Audit Trail
- Filter by: Last 24 hours
- Look for: "Package Installation" events
- Check: No errors or warnings about metadata conflicts

---

## Phase 2: Namespace & Visibility Validation (10 minutes)

### 2.1 Verify Namespace Prefix
```soql
SELECT ApiVersion, NamespacePrefix, IsSalesforceOwned 
FROM PackageSubscriber 
WHERE PackageName LIKE 'Quick Bridge%'
```

Expected NamespacePrefix: `QuickBridge`

### 2.2 Verify Global Classes Visibility
In Developer Console, execute:
```apex
List<ApexClass> classes = [
    SELECT NamespacePrefix, Name, ApiVersion 
    FROM ApexClass 
    WHERE NamespacePrefix = 'QuickBridge' 
    AND Name IN ('QBTriggerHandler', 'IntegrationWorkService', 'QuickBooksInvoiceHandler')
];
System.debug('Global Classes Found: ' + classes.size());
for(ApexClass cls : classes) {
    System.debug(cls.NamespacePrefix + '.' + cls.Name);
}
```

✅ Should return 3 classes (all global visibility enabled)

### 2.3 Check Field Type Changes
```soql
SELECT DeveloperName, Type 
FROM FieldDefinition 
WHERE EntityDefinition.DeveloperName = 'Credit_Memo__c' 
AND DeveloperName IN ('Billing_Address__c', 'Shipping_Address__c')
```

✅ Both fields should show `Type = "LONGTEXTAREA"` (not "ADDRESS")

---

## Phase 3: Custom Metadata Configuration (15-20 minutes)

### 3.1 Configure QuickBooks Connection
1. **Navigate to:** Setup → Custom Metadata Types → QuickBooks_Config
2. **Verify Existing Records:**
   - Default
   - Sandbox_Config
3. **If Missing - Create Default Configuration:**
   - Label: "Default"
   - Developer Name: "Default"
   - Minor_Version__c: "65"
   - QuickBooks_Is_Active__c: False (until QB connection established)
   - Named_Credential__c: [Select your QB Named Credential]
   - Realm_ID__c: [Your QB Realm ID]

### 3.2 Configure Named Credentials (if not existing)
1. **Navigate to:** Setup → Named Credentials
2. **Create if needed:**
   - **Label:** QuickBookSandbox
   - **Name:** QuickBookSandbox
   - **URL:** [Your QB API endpoint]
   - **Authentication Protocol:** OAuth 2.0
   - **Auth. Provider:** [Your QB Auth Provider]

### 3.3 Load Integration Metadata
The package includes 280+ custom metadata records for:
- API Callout Controls
- Connector Configurations
- Field Mappings
- Integration Products

✅ These auto-load; verify by:
1. Navigate to: Setup → Custom Metadata Types
2. Check each type has expected record counts:
   - Connector_Config_Field: ~65 records
   - Field_Mapping: ~100 records
   - Integration_Connector: ~11 records
   - Integration_Object_Map: ~31 records

---

## Phase 4: Trigger & Automation Verification (10 minutes)

### 4.1 Verify Triggers are Active
```soql
SELECT DeveloperName, Status, NamespacePrefix 
FROM ApexTrigger 
WHERE NamespacePrefix = 'QuickBridge'
ORDER BY DeveloperName
```

**Expected Active Triggers:**
- AccountTrigger (on Account)
- CreditMemoTrigger (on Credit_Memo__c)
- InvoiceTrigger (on Invoice__c)
- InvoiceLineTrigger (on Integration_Work_Item__c)
- OrderItemTrigger (on Order Item)
- OrderTrigger (on Order)
- ProductTrigger (on Product2)
- PurchaseOrderTrigger (on Purchase_Order__c)

✅ All should have Status = "Active"

### 4.2 Test Trigger Execution
Create a test record to verify triggers work:
```apex
// In Developer Console Execute Anonymous
Account testAccount = new Account(Name = 'QB Test Account');
insert testAccount;
System.debug('Account Created: ' + testAccount.Id);
```

**Check:**
- ✅ No exceptions in debug log
- ✅ Account record created successfully
- ✅ No "Type is not visible" errors in logs

### 4.3 Verify Flows
1. Navigate to: Setup → Flows
2. Look for flows with namespace "QuickBridge"
3. Expected flows:
   - QB Sync workflows
   - Error handling flows
   - Integration orchestration flows
4. **Status:** All should be "Active"

---

## Phase 5: Permission & Access Configuration (15 minutes)

### 5.1 Create Permission Set (if not auto-created)
1. **Navigate to:** Setup → Permission Sets
2. **Check for:** QuickBridge_Admin or similar
3. **If missing - Create:**
   - Name: QuickBridge_Admin
   - Label: Quick Bridge Admin
   - Assign Permissions:
     - All custom object permissions (CRUD)
     - Execute flows
     - Access flows
     - Apex class access

### 5.2 Assign Permission Sets to Users
1. **Navigate to:** Setup → Permission Sets
2. **Select:** QuickBridge_Admin (or equivalent)
3. **Assign to:**
   - System Administrator
   - Integration specialists
   - Any users needing QB sync functionality

### 5.3 Verify Object Permissions
For each custom object, users should have:
- ✅ Create
- ✅ Read
- ✅ Update
- ✅ Delete
- ✅ View All / Modify All (for admins)

---

## Phase 6: FlexiPage & UI Customization (10 minutes)

### 6.1 Verify Record Pages Load
1. **Navigate to:** Any Account record
2. **Check:**
   - ✅ Account_Record_Page FlexiPage loads without errors
   - ✅ No "component not available" messages
   - ✅ All sections render properly
   - ✅ Highlights Panel shows data
   - ✅ Related Lists display correctly

### 6.2 Check Removed Components
The FlexiPage no longer includes `cooper:companyInsightTeaserCard`
- ✅ Verify no component-missing errors
- ✅ Page renders without dependency warnings

### 6.3 Add Package Components to App
1. **Navigate to:** Setup → App Manager
2. **Create/Edit app for Quick Bridge:**
   - Add Custom Objects:
     - Credit_Memo__c
     - Invoice__c
     - Integration_Product__c
     - Integration_Work_Item__c
     - Purchase_Order__c
   - Add Navigation items for key flows
   - Set as default app for QB users

---

## Phase 7: Data Validation (20 minutes)

### 7.1 Verify Existing Data Integrity
```soql
-- Check for data in upgraded objects
SELECT COUNT() FROM QuickBridge__Credit_Memo__c;
SELECT COUNT() FROM QuickBridge__Invoice__c;
SELECT COUNT() FROM QuickBridge__Integration_Work_Item__c;
```

✅ All counts should match pre-upgrade counts

### 7.2 Check Address Fields Migration
```soql
-- Verify Billing_Address__c still contains data (now as LongTextArea)
SELECT Id, Billing_Address__c 
FROM QuickBridge__Credit_Memo__c 
WHERE Billing_Address__c != NULL 
LIMIT 5
```

✅ Data should persist (field type changed from Address → LongTextArea)

### 7.3 Validate Relationships
```soql
-- Verify parent-child relationships intact
SELECT Id, QuickBridge__Customer__c 
FROM QuickBridge__Credit_Memo__c 
WHERE QuickBridge__Customer__c != NULL 
LIMIT 10
```

✅ All foreign key relationships should be intact

---

## Phase 8: Integration Configuration (30-60 minutes)

### 8.1 Configure Integration Work Settings
1. **Navigate to:** Custom Metadata Type: Integration_Work_Setting
2. **Verify/Configure:**
   - Batch size for processing
   - Retry policies
   - Error handling preferences
   - Logging levels

### 8.2 Setup QuickBooks Connection
1. **Navigate to:** Setup → External Data Sources (if using)
2. **Configure:**
   - QB API endpoint
   - Authentication details
   - Timeout settings
3. **Test connection:**
   - Use Validate Connection button
   - Verify credentials work

### 8.3 Enable Usage Tracking
1. **Navigate to:** Setup → Custom Settings → Integration_Usage_Limit
2. **Configure:**
   - Daily API call limits
   - Error rate thresholds
   - Auto-disable triggers if limits exceeded

### 8.4 Setup Error Logging
1. **Navigate to:** Setup → Custom Settings → Error Log Settings (if available)
2. **Configure:**
   - Log retention period
   - Error notification recipients
   - Severity level filters

---

## Phase 9: Test Critical Workflows (30-45 minutes)

### 9.1 Test Account Sync
1. **Create test account:**
   - Name: "QB Test Account"
   - Industry: "Technology"
   - Add relevant fields
2. **Verify:**
   - ✅ Account trigger executes
   - ✅ Integration Work Item created
   - ✅ No errors in logs

### 9.2 Test Invoice Operations
1. **Create test invoice:**
   - Add to existing account
   - Include line items
2. **Verify:**
   - ✅ InvoiceTrigger executes
   - ✅ QB sync initiated
   - ✅ Batch job processes successfully

### 9.3 Test Credit Memo Processing
1. **Create credit memo:**
   - Link to existing invoice
   - Add amount
2. **Verify:**
   - ✅ Address fields display correctly (LongTextArea format)
   - ✅ Trigger processes without errors

### 9.4 Test Error Handling
1. **Intentionally create an error:**
   - Invalid QB credentials
   - Missing required field
2. **Verify:**
   - ✅ Error logged in Error_Log__c
   - ✅ User receives notification (if configured)
   - ✅ System recovers gracefully

---

## Phase 10: Performance & Monitoring (15 minutes)

### 10.1 Monitor API Usage
1. **Navigate to:** Setup → System Overview
2. **Check:**
   - ✅ API call count reasonable
   - ✅ No runaway batch jobs
   - ✅ CPU time under control

### 10.2 Check Apex Debug Logs
1. **Navigate to:** Developer Console → Debug → Logs
2. **Filter for:**
   - QBTriggerHandler
   - IntegrationWorkService
   - QuickBooksInvoiceHandler
3. **Verify:**
   - ✅ Classes execute without "Type not visible" errors
   - ✅ No repetitive error patterns

### 10.3 Verify Scheduled Jobs
1. **Navigate to:** Setup → Scheduled Jobs
2. **Look for:**
   - Any QB sync scheduled jobs
   - Batch cleanup jobs
   - Metadata refresh jobs
3. **Status:** All should be "Scheduled" or completed successfully

### 10.4 Monitor AsyncApexJob
```apex
// Monitor batch processing
SELECT Id, ApexClassID, Status, JobType, NumberBatchesSent, NumberBatchesCompleted
FROM AsyncApexJob 
WHERE CreatedDate = TODAY 
ORDER BY CreatedDate DESC
LIMIT 10
```

✅ All batch jobs should show Status = "Completed"

---

## Phase 11: Documentation & Communication (10 minutes)

### 11.1 Document Configuration
Create a setup document including:
- ✅ QB connection credentials (secure storage)
- ✅ Permission sets assigned
- ✅ Configured metadata values
- ✅ Approved users & roles
- ✅ Sync frequency/schedule

### 11.2 User Communication
Send to affected users:
1. **Installation announcement**
   - Package version (0.3.0.2)
   - Key features/fixes
   - Known limitations

2. **User guide:**
   - How to sync records
   - How to report errors
   - Support contact info

3. **Training:**
   - Schedule training session
   - Cover new features
   - Q&A session

---

## Troubleshooting Checklist

### Common Issues & Solutions

| Issue | Cause | Solution |
|-------|-------|----------|
| Trigger not executing | Class not global | Verify class visibility via SOQL |
| Address field errors | Type mismatch | Verify field type is LongTextArea |
| Component missing errors | FlexiPage reference issue | Clear browser cache, reload page |
| QB connection failing | Named credential issue | Test credential in Setup |
| Batch job stuck | Governor limits | Check AsyncApexJob status |
| Permission denied | Missing permission set | Assign QuickBridge_Admin |
| Data not syncing | Trigger disabled | Enable trigger in class |

---

## Post-Installation Validation Sign-Off

**Checklist for Sandbox Validation:**

- [ ] Package installed successfully
- [ ] All custom objects exist
- [ ] Triggers verified and active
- [ ] Global classes accessible
- [ ] Metadata records loaded
- [ ] Permissions assigned
- [ ] Address field type verified (LongTextArea)
- [ ] QB connection configured
- [ ] Test records sync successfully
- [ ] No errors in debug logs
- [ ] Performance metrics acceptable
- [ ] Users trained and notified
- [ ] Documentation completed
- [ ] Ready for production deployment

**Sign-off:**
- Implementation Date: ___________
- Validated By: ___________
- Approved By: ___________

---

## Next Steps

1. ✅ **Complete all 11 phases** in sandbox
2. ✅ **Gather stakeholder approval**
3. ✅ **Create rollback plan** if issues occur
4. ✅ **Schedule production upgrade** during maintenance window
5. ✅ **Plan post-upgrade communication** to end users

---

## Support & Escalation

**For Issues:**
1. Check troubleshooting checklist above
2. Review debug logs in Developer Console
3. Check Setup Audit Trail for errors
4. Contact: [Your Support Team]

**For Questions:**
- Documentation: See docs/ folder
- Known Issues: See KNOWN_ISSUES.md
- FAQ: See FAQ.md

---

## Important Notes

⚠️ **Address Field Change:**
- Billing_Address__c and Shipping_Address__c changed from Address type to LongTextArea
- Existing data preserved
- May affect any custom formatting logic

⚠️ **Class Visibility:**
- QBTriggerHandler, IntegrationWorkService, QuickBooksInvoiceHandler now global
- Allows proper package interop
- No breaking changes for subscribers

⚠️ **Tab Management:**
- CustomTabs now inherited from base package
- No duplicate tab errors during upgrade
- Tab behavior unchanged

---

**Generated:** 2026-08-17
**Package Version:** 0.3.0.2
**Namespace:** QuickBridge
**Status:** Ready for Production

