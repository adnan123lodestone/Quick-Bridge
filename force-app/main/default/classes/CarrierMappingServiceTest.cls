@IsTest
private class CarrierMappingServiceTest {
    @IsTest
    static void putAndGetPathSupportBracketArrays() {
        Map<String, Object> payload = new Map<String, Object>();

        CarrierMappingService.putPath(payload, 'recipient.address.streetLines[0]', '10 Main St');
        CarrierMappingService.putPath(payload, 'recipient.address.streetLines[1]', 'Suite 4');
        CarrierMappingService.putPath(payload, 'requestedPackageLineItems[0].weight.value', 5);

        System.assertEquals('10 Main St', CarrierMappingService.getPath(payload, 'recipient.address.streetLines[0]'));
        System.assertEquals('Suite 4', CarrierMappingService.getPath(payload, 'recipient.address.streetLines[1]'));
        System.assertEquals(5, CarrierMappingService.getPath(payload, 'requestedPackageLineItems[0].weight.value'));
    }

    @IsTest
    static void getPathKeepsNumericDotCompatibility() {
        Map<String, Object> payload = new Map<String, Object>{
            'trackResponse' => new Map<String, Object>{
                'shipment' => new List<Object>{
                    new Map<String, Object>{
                        'package' => new List<Object>{
                            new Map<String, Object>{ 'trackingNumber' => '1Z999' }
                        }
                    }
                }
            }
        };

        System.assertEquals('1Z999', CarrierMappingService.getPath(payload, 'trackResponse.shipment.0.package.0.trackingNumber'));
    }

    @IsTest
    static void buildRequestPayloadReadsRelationshipPaths() {
        Account parent = new Account(Name = 'Carrier Parent');
        insert parent;
        Contact contact = new Contact(LastName = 'Receiver', AccountId = parent.Id);
        insert contact;

        CarrierMappingService.MappingSet mappingSet = new CarrierMappingService.MappingSet();
        mappingSet.integration = 'ups';
        mappingSet.actionName = 'createShipment';
        mappingSet.sfObjectApiName = 'Contact';
        mappingSet.requestMappings.add(new Field_Mapping__mdt(
            SF_Field__c = 'Account.Name',
            External_Field__c = 'ShipTo.AttentionName',
            Sync_Direction__c = 'SF to Carrier'
        ));

        SObject queried = CarrierMappingService.queryMappedRecord(
            contact.Id,
            mappingSet,
            CarrierMappingService.DIRECTION_TO_CARRIER
        );
        Map<String, Object> payload = CarrierMappingService.buildRequestPayload(queried, mappingSet);

        System.assertEquals('Carrier Parent', CarrierMappingService.getPath(payload, 'ShipTo.AttentionName'));
    }

    @IsTest
    static void buildResponseUpdateTreatsProviderDirectionsAsCarrierToSf() {
        CarrierMappingService.MappingSet mappingSet = new CarrierMappingService.MappingSet();
        mappingSet.integration = 'fedex';
        mappingSet.actionName = 'syncTrackingStatus';
        mappingSet.sfObjectApiName = 'Account';
        mappingSet.responseMappings.add(new Field_Mapping__mdt(
            SF_Field__c = 'Phone',
            External_Field__c = 'tracking.latestStatus',
            Sync_Direction__c = 'FedEx to SF'
        ));

        Account account = new Account(Name = 'Mapping Target');
        insert account;

        SObject updateRecord = CarrierMappingService.buildResponseUpdate(
            account.Id,
            mappingSet,
            new Map<String, Object>{
                'tracking' => new Map<String, Object>{ 'latestStatus' => 'Delivered' }
            }
        );

        System.assertNotEquals(null, updateRecord);
        System.assertEquals('Delivered', updateRecord.get('Phone'));
    }
}