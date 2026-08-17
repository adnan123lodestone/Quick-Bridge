# QuickBridge Package Upgrade - Error Remediation Plan

## Executive Summary
Your 2GP package upgrade is failing due to 26 deployment errors across 6 categories. These errors stem from incompatibilities with the existing managed package (0.4 Beta 3) already installed in the subscriber org, unsupported field types, and missing class visibility declarations.

---

## Error Categories & Remediation

### 1. ❌ CRITICAL: Address Field Type Not Supported in Managed Packages (Errors #1-2)
**Problem:** `Credit_Memo__c.Billing_Address__c` and `Credit_Memo__c.Shipping_Address__c` use the `Address` data type, which is NOT supported in 2GP managed packages.

**Impact:** These fields will fail to deploy in any managed package.

**Solution:** Convert to `LongTextArea` or `TextArea` fields
- Billing_Address__c: Change type from Address → LongTextArea (32,000 chars)
- Shipping_Address__c: Change type from Address → LongTextArea (32,000 chars)

**Files to Fix:**
- `force-app/main/default/objects/Credit_Memo__c/fields/Billing_Address__c.field-meta.xml`
- `force-app/main/default/objects/Credit_Memo__c/fields/Shipping_Address__c.field-meta.xml`

---

### 2. ❌ MAJOR: CustomTab Conflicts with Existing Managed Package (Errors #3-15)
**Problem:** Package 033ak000000aahhAAA (the old managed package) already contains these tabs. The 2GP upgrade cannot create duplicate tabs.

**Affected Tabs:**
- Credit_Memo__c
- CustomException__c
- Error_Log__c
- Integration_Product__c
- Integration_Work_Admin
- Integration_Work_Item__c
- Integration_Work_Lock__c
- Invoice__c
- Item_Sales_Tax__c
- Payment_Config_Panel
- Payment_Configuration
- Portal_Payment_Transaction__c
- Purchase_Order__c

**Solution:** Remove ALL CustomTab entries from your package manifest and force-app/main/default/tabs/ since they already exist in the base managed package.

**Action:** Delete all .tab-meta.xml files from `force-app/main/default/tabs/` directory

---

### 3. ❌ CRITICAL: Cannot Modify Managed Components (Errors #16-17)
**Problem:** `QuickBooks_Config.Default` and `QuickBooks_Config.Sandbox_Config` are managed components in the old package and cannot be modified.

**Solution:** Remove these from your package manifest. They should remain under the old package's management.

**Files to Remove:**
- `force-app/main/default/customMetadata/QuickBooks_Config.Default.md-meta.xml`
- `force-app/main/default/customMetadata/QuickBooks_Config.Sandbox_Config.md-meta.xml`

---

### 4. ⚠️ CRITICAL: Missing Global Class Visibility (Errors #18-25)
**Problem:** Triggers reference Apex classes that are NOT marked as `global`, making them invisible to other namespaces.

**Affected Classes:**
- QBTriggerHandler (public → needs to be global)
- IntegrationWorkService (public → needs to be global)
- QuickBooksInvoiceHandler (public → needs to be global)

**Solution:** Change class declaration from `public class` to `global class` for all classes referenced by triggers:
1. QBTriggerHandler.cls
2. IntegrationWorkService.cls
3. QuickBooksInvoiceHandler.cls

---

### 5. ⚠️ MAJOR: Missing Lightning Component Dependency (Error #26)
**Problem:** `Account_Record_Page` FlexiPage references `cooper:companyInsightTeaserCard` component which is not available in the subscriber org.

**Solution (Choose One):**
- **Option A:** Remove the cooper:companyInsightTeaserCard component from the FlexiPage
- **Option B:** Make component usage conditional/optional

**File:** `force-app/main/default/flexipages/Account_Record_Page.flexipage-meta.xml`

---

## Implementation Steps

1. **Fix Address Fields** (2 files)
2. **Remove CustomTabs** (13 .tab-meta.xml files)
3. **Remove Managed Metadata** (2 .md-meta.xml files)
4. **Make Classes Global** (3 classes)
5. **Fix FlexiPage** (1 file)
6. **Update package manifest** to exclude removed components
7. **Create new package version** with corrected metadata
8. **Test upgrade** in sandbox subscriber org

---

## Package Contents After Remediation

✅ Keep: All Apex classes, triggers, custom objects (except address fields), layouts, flows, LWC components
❌ Remove: Address-type fields, CustomTabs, managed metadata, unavailable component references

---

## Testing Checklist

- [ ] Create fresh test org with old package 0.4 Beta 3
- [ ] Deploy fixed package version
- [ ] Verify no field type errors
- [ ] Verify no tab conflicts
- [ ] Verify trigger execution succeeds
- [ ] Verify FlexiPage renders without errors
- [ ] Test package upgrade in production-like org

