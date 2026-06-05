public with sharing class QuickBooksScheduledOperationAdapter implements ScheduledOperationAdapter {
  @TestVisible
  private static Boolean skipExecutionForTests = false;

  public void execute(Scheduled_Integration_Job__c job) {
    if (Test.isRunningTest() && skipExecutionForTests == true) {
      return;
    }
    run(job.Source_Object__c, job.Direction__c);
  }

  public static void run(String targetObject, String direction) {
    try {
      IntegrationUsageService.incrementTaskUsage('QuickBooks', 1);
      String safeDirection = String.isBlank(direction) ? 'Out' : direction;

      if (targetObject == 'Account' || targetObject == 'Accounts') {
        if (safeDirection == 'In') {
          Database.executeBatch(new QBCustomerToAccountSyncBatch(), 50);
        } else {
          String accountFields = buildAccountQueryFields();
          List<Account> unsynced = Database.query(
            'SELECT ' + accountFields
            + ' FROM Account WHERE QuickBridgeTLG__QuickbookID__c = NULL AND IsPersonAccount = FALSE'
          );
          if (!unsynced.isEmpty()) {
            Database.executeBatch(new QBAccountBatch(unsynced, true), 50);
          }
        }
      } else if (targetObject == 'Vendor' || targetObject == 'Vendors') {
        if (safeDirection == 'In') {
          Database.executeBatch(new QBVendorToAccountSyncBatch(), 50);
        } else {
          List<RecordType> vendorRTs = [
            SELECT Id
            FROM RecordType
            WHERE
              SobjectType = 'Account'
              AND IsActive = TRUE
              AND (Name = 'Vendor'
              OR DeveloperName = 'Vendor')
            LIMIT 1
          ];
          if (!vendorRTs.isEmpty()) {
            String accountFields = buildAccountQueryFields();
            List<Account> unsynced = Database.query(
              'SELECT ' + accountFields
              + ' FROM Account WHERE QuickBridgeTLG__QuickbookID__c = NULL AND RecordTypeId = \'' + vendorRTs[0].Id + '\''
            );
            if (!unsynced.isEmpty()) {
              Database.executeBatch(new QBAccountBatch(unsynced, true), 50);
            }
          }
        }
      } else if (targetObject == 'Product' || targetObject == 'Products') {
        if (safeDirection == 'In') {
          Database.executeBatch(new QBItemToProductSyncBatch(), 50);
        } else {
          List<Product2> unsynced = [
            SELECT Id
            FROM Product2
            WHERE QuickbookID__c = NULL AND IsActive = TRUE
          ];
          if (!unsynced.isEmpty()) {
            Database.executeBatch(new QBProductBatch(unsynced, true), 50);
          }
        }
      } else if (targetObject == 'Order' || targetObject == 'Orders') {
        if (safeDirection == 'In') {
          Database.executeBatch(new QBInvoiceToOrderSyncBatch(), 10);
        } else {
          List<Order> unsyncedOrders = [
            SELECT Id
            FROM Order
            WHERE QuickbookID__c = NULL AND Status IN ('Draft', 'Activated')
          ];
          if (!unsyncedOrders.isEmpty()) {
            Database.executeBatch(
              new QBSalesOrderSyncBatch(
                new Map<Id, Order>(unsyncedOrders).keySet(),
                true
              ),
              1
            );
          }
        }
      } else if (targetObject == 'Invoices' || targetObject == 'Invoice') {
        if (safeDirection == 'In') {
          Database.executeBatch(new QBInvoiceToOrderSyncBatch(), 10);
        } else {
          String mappedObj = QBObjectMappings.getInvoiceSourceObject();
          String query =
            'SELECT Id FROM ' +
            mappedObj +
            ' WHERE External_Id__c = null';
          List<SObject> unsyncedRecords = Database.query(query);

          if (!unsyncedRecords.isEmpty()) {
            Database.executeBatch(
              new QuickBooksInvoiceBatch(
                new Map<Id, SObject>(unsyncedRecords).keySet(),
                true
              ),
              10
            );
          }
        }
      } else if (
        targetObject == 'CreditMemos' ||
        targetObject == 'Credit Memo'
      ) {
        if (safeDirection == 'In') {
          Database.executeBatch(new QBCreditMemoInboundBatch(), 10);
        } else {
          Map<Id, Credit_Memo__c> unsyncedMemos = new Map<Id, Credit_Memo__c>(
            [
              SELECT Id
              FROM Credit_Memo__c
              WHERE External_Id__c = NULL
            ]
          );
          if (!unsyncedMemos.isEmpty()) {
            Database.executeBatch(
              new QuickBooksCreditMemoBatch(unsyncedMemos.keySet(), true),
              10
            );
          }
        }
      } else if (
        targetObject == 'PurchaseOrders' ||
        targetObject == 'Purchase Order'
      ) {
        if (safeDirection == 'In') {
          Database.executeBatch(new QBPurchaseOrderInboundBatch(), 10);
        } else {
          Map<Id, Purchase_Order__c> unsyncedPurchaseOrders = new Map<Id, Purchase_Order__c>(
            [
              SELECT Id
              FROM Purchase_Order__c
              WHERE External_Id__c = NULL
            ]
          );
          if (!unsyncedPurchaseOrders.isEmpty()) {
            Database.executeBatch(
              new QuickBooksPurchaseOrderBatch(
                unsyncedPurchaseOrders.keySet(),
                true
              ),
              10
            );
          }
        }
      } else if (
        targetObject == 'ItemSalesTax' ||
        targetObject == 'Item Sales Tax'
      ) {
        Database.executeBatch(new QBOItemSalesTaxBatch(), 1);
      }
    } catch (Exception e) {
      ErrorLogUtility.logException(
        'QuickBooks',
        'QuickBooksScheduledOperationAdapter.run',
        e,
        null,
        null
      );
      throw e;
    }
  }

  // Builds the Account SELECT field list for outbound sync queries.
  // Derives SF fields from the active field mapping so the query always matches
  // what QBAccountService reads. Extra identity/relationship fields are added
  // unconditionally; person-account fields are included only when they exist.
  private static String buildAccountQueryFields() {
    Map<String, Schema.SObjectField> schemaFields = Schema.SObjectType.Account.fields.getMap();
    Set<String> fieldApiNames = new Set<String>{'Id', 'Name', 'RecordTypeId'};

    // Add all SF-side fields from the active mapping (Customer and Vendor)
    for (String sfField : QBObjectMappings.getAccountToCustomerMapping().keySet()) {
      fieldApiNames.add(sfField);
    }
    for (String sfField : QBObjectMappings.getAccountToVendorMapping().keySet()) {
      fieldApiNames.add(sfField);
    }

    // Person-account fields — only include when enabled in this org
    List<String> personAccountFields = new List<String>{
      'IsPersonAccount', 'FirstName', 'LastName', 'PersonEmail', 'GivenName__c', 'FamilyName__c'
    };
    for (String f : personAccountFields) {
      if (schemaFields.containsKey(f.toLowerCase()) || schemaFields.containsKey('quickbridgetlg__' + f.toLowerCase())) {
        fieldApiNames.add(f);
      }
    }

    // Resolve each name to its actual schema API name (handles namespace prefix correctly)
    Set<String> resolvedFields = new Set<String>();
    for (String fieldName : fieldApiNames) {
      String keyLower = fieldName.toLowerCase();
      Schema.SObjectField token = schemaFields.get(keyLower);
      if (token == null) {
        token = schemaFields.get('quickbridgetlg__' + keyLower);
      }
      if (token != null) {
        resolvedFields.add(token.getDescribe().getName());
      }
    }

    return String.join(new List<String>(resolvedFields), ', ');
  }
}