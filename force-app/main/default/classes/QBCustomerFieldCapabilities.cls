public inherited sharing class QBCustomerFieldCapabilities {
    private static final Set<String> OUTBOUND_WRITABLE_FIELDS = new Set<String>{
        'DisplayName',
        'CompanyName',
        'GivenName',
        'MiddleName',
        'FamilyName',
        'Suffix',
        'Title',
        'AcctNum',
        'Notes',
        'Active',
        'PrimaryEmailAddr.Address',
        'PrimaryPhone.FreeFormNumber',
        'BillAddr.Line1',
        'BillAddr.City',
        'BillAddr.CountrySubDivisionCode',
        'BillAddr.PostalCode',
        'BillAddr.Country',
        'ShipAddr.Line1',
        'ShipAddr.City',
        'ShipAddr.CountrySubDivisionCode',
        'ShipAddr.PostalCode',
        'ShipAddr.Country',
        'SalesTermRef.value'
    };

    public static Boolean isInboundReadable(String externalField) {
        return String.isNotBlank(externalField);
    }

    public static Boolean isOutboundWritable(String externalField) {
        return String.isNotBlank(externalField) &&
            OUTBOUND_WRITABLE_FIELDS.contains(externalField);
    }

    public static Map<String, String> filterOutboundMappings(
        Map<String, String> mappings
    ) {
        Map<String, String> safeMappings = new Map<String, String>();
        if (mappings == null) {
            return safeMappings;
        }
        for (String salesforceField : mappings.keySet()) {
            String externalField = mappings.get(salesforceField);
            if (isOutboundWritable(externalField)) {
                safeMappings.put(salesforceField, externalField);
            }
        }
        return safeMappings;
    }
}
