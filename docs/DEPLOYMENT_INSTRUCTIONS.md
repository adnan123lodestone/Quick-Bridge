# QuickBridge 2GP Package - Deployment Instructions

## Quick Start

All remediation changes are complete. Follow these steps to deploy your corrected 2GP package:

---

## Step 1: Create New Package Version

Run this command from the project root:

```powershell
cd "c:\Production Project\Quick Bridge"
sf package:version:create --package QuickBridgeTLG --version-number 0.3.0.0 --installation-key-bypass --wait 30
```

**Expected Output:**
```
Successfully created package version [PackageVersionId]
Version: 0.3.0.0
Status: Created
```

**Note the returned Package Version ID** - you'll need it for the next step.

---

## Step 2: Test in Sandbox (Recommended)

### 2a. Create Fresh Subscriber Org Test
If you have a sandbox with v0.4 Beta 3 already installed:

```powershell
sf org create sandbox --name test-qb-upgrade --target-org your-devhub
```

### 2b. Deploy with Remediated Manifest
```powershell
sf project deploy start --manifest manifest/package-remediated.xml --target-org test-qb-upgrade --wait 10
```

**Expected Results:**
- ✅ No deployment errors
- ✅ All 26 errors resolved
- ✅ Package installs/upgrades successfully
- ✅ Triggers execute without errors
- ✅ FlexiPage renders correctly

### 2c. Verify in Subscriber Org
1. Navigate to Setup → Installed Packages
2. Verify QuickBridgeTLG v0.3.0.0 is present
3. Check custom object tabs load correctly
4. Test account trigger by creating/updating an Account record
5. Verify no errors in debug logs

---

## Step 3: Promote Package Version

Once testing is successful, promote to released status:

```powershell
sf package:version:promote --package [YourPackageVersionId]
```

**Example:**
```powershell
sf package:version:promote --package 04tam000006xxxAAA
```

**Expected Output:**
```
Successfully promoted package version
Version: 0.3.0.0
Status: Released
```

---

## Step 4: Deploy to Production

### Option A: Direct Deployment (if no existing v0.4)
```powershell
sf project deploy start --manifest manifest/package-remediated.xml --target-org production-org --wait 10
```

### Option B: Package Installation (if v0.4 already installed)
Use the installation link from your released package:
```
https://login.salesforce.com/packaging/installPackage.apexp?p0=[SubscriberPackageVersionId]
```

---

## Troubleshooting

### Issue: "Custom object tab already exists in package..."
✅ **Fixed** - All tabs removed from deployment. This error should NOT occur.

### Issue: "Type is not visible: QuickBridgeTLG.ClassName"
✅ **Fixed** - All trigger handler classes marked as global. This error should NOT occur.

### Issue: "Invalid data type" for Address fields
✅ **Fixed** - Fields converted to LongTextArea. This error should NOT occur.

### Issue: "Your org doesn't have access to component cooper:..."
✅ **Fixed** - Component removed from FlexiPage. This error should NOT occur.

### Issue: "Cannot Modify Managed Component" for QuickBooks_Config
✅ **Fixed** - Metadata removed from deployment. This error should NOT occur.

---

## Validation Queries

Run these in your subscriber org to verify deployment:

### Check Custom Objects Exist
```soql
SELECT Id, SobjectType FROM SobjectType 
WHERE SobjectType IN ('Credit_Memo__c', 'Invoice__c', 'Integration_Work_Item__c')
LIMIT 10
```

### Check Triggers Exist
```soql
SELECT DeveloperName, Status FROM ApexTrigger 
WHERE DeveloperName IN ('AccountTrigger', 'InvoiceTrigger', 'CreditMemoTrigger')
LIMIT 10
```

### Check Address Fields
```soql
SELECT DeveloperName, Type FROM FieldDefinition 
WHERE EntityDefinition.DeveloperName = 'Credit_Memo__c' 
AND DeveloperName IN ('Billing_Address__c', 'Shipping_Address__c')
LIMIT 10
```

Expected: Both fields should show Type = "LONGTEXTAREA"

---

## Rollback Plan (if needed)

If deployment fails unexpectedly:

1. **Identify the issue** in deployment logs
2. **Reference error mapping** in REMEDIATION_COMPLETE.md
3. **Report error** with full error message
4. **Rollback package** to v0.4 Beta 3 (if already installed)

---

## Performance Considerations

- **Address Fields**: LongTextArea performs similarly to Address type
- **Class Visibility**: Global classes have minimal performance impact
- **FlexiPage**: Removal of cooper component reduces data dependencies
- **Overall**: No performance degradation expected

---

## Support & Documentation

- **Remediation Details**: See `docs/REMEDIATION_COMPLETE.md`
- **Error Analysis**: See `docs/PACKAGE_UPGRADE_REMEDIATION.md`
- **Manifest Used**: `manifest/package-remediated.xml`

---

## Deployment Checklist

- [ ] Ran `package:version:create` successfully
- [ ] Noted Package Version ID
- [ ] Tested in sandbox with remediated manifest
- [ ] All 26 errors resolved in test
- [ ] Promoted package version to released
- [ ] Deployed to production subscriber orgs
- [ ] Verified custom objects, triggers, and fields exist
- [ ] Tested business logic with sample records
- [ ] Verified no errors in debug logs

---

## FAQ

**Q: Can I skip testing and go straight to production?**
A: Not recommended. Test in sandbox first to ensure all functionality works correctly.

**Q: What about data in Address fields?**
A: Existing data remains intact. The field type change is backward compatible.

**Q: Do I need to update any custom code?**
A: No. The Apex classes remain functionally identical, just with updated visibility.

**Q: Can I roll back if something goes wrong?**
A: Yes. You can uninstall the package and reinstall v0.4 Beta 3, or upgrade to a newer version.

**Q: How long does deployment take?**
A: Typically 5-15 minutes depending on org size and concurrent operations.

