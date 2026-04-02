public class QBObjectMappings {
    // Account to Customer mapping
    public static Map<String, String> getAccountToCustomerMapping() {
        return new Map<String, String>{
            'Name' => 'CompanyName',
            'AccountNumber' => 'AcctNum',
            'PrimaryEmailAddr__c' => 'PrimaryEmailAddr.Address',
            'Phone' => 'PrimaryPhone.FreeFormNumber',
            'BillingStreet' => 'BillAddr.Line1',
            'BillingCity' => 'BillAddr.City',
            'BillingState' => 'BillAddr.CountrySubDivisionCode',
            'BillingPostalCode' => 'BillAddr.PostalCode',
            'BillingCountry' => 'BillAddr.Country',
            'GivenName__c' => 'GivenName',
            'MiddleName__c' => 'MiddleName',
            'FamilyName__c' => 'FamilyName',
            'Suffix__c' => 'Suffix',
            'Title__c' => 'Title',
            
            'Description' => 'Notes'
        };
    }
    
    // Customer to Account mapping (for potential reverse sync)
    public static Map<String, String> getCustomerToAccountMapping() {
        return new Map<String, String>{
            'CompanyName' => 'Name',
            'AcctNum' => 'AccountNumber',
            'PrimaryEmailAddr.Address' => 'PrimaryEmailAddr__c',
            'PrimaryPhone.FreeFormNumber' => 'Phone',
            'BillAddr.Line1' => 'BillingStreet',
            'BillAddr.City' => 'BillingCity',
            'BillAddr.CountrySubDivisionCode' => 'BillingState',
            'BillAddr.PostalCode' => 'BillingPostalCode',
            'BillAddr.Country' => 'BillingCountry',
            'GivenName' => 'GivenName__c',
            'MiddleName' => 'MiddleName__c',
            'FamilyName' => 'FamilyName__c',
            'Suffix' => 'Suffix__c',
            'Title' => 'Title__c',
            'WebAddr.URI' => 'Website',
            'Notes' => 'Description'
        };
    }
    
    // Product to Item mapping
    public static Map<String, String> getProductToItemMapping() {
        return new Map<String, String>{
            'Name' => 'Name',
            'Description' => 'Description',
            'ProductCode' => 'Sku',
            'IsActive' => 'Active',
            'QtyOnHand__c' => 'QtyOnHand',
            'TrackQtyOnHand__c' => 'TrackQtyOnHand',
            'InvStartDate__c' => 'InvStartDate',
                'Unit_Price__c' => 'UnitPrice',
                 'IsActive' =>                   'Active'
        };
    }
    
    public static Map<String, String> getOrderToInvoiceMapping() {
        return new Map<String, String>{
            'EffectiveDate' => 'TxnDate',
            'TotalAmount' => 'TotalAmt',
            'Description' => 'CustomerMemo.value'
        };
    }
    
  
}