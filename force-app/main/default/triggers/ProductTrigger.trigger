trigger ProductTrigger on Product2 (after insert, after update) {
    if (Trigger.isAfter && (Trigger.isInsert || Trigger.isUpdate)) {
        QBTriggerHandler.handleProductTrigger(Trigger.new, Trigger.oldMap, Trigger.isInsert, Trigger.isUpdate);
    }
}