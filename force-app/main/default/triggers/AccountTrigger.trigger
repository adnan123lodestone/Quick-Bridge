trigger AccountTrigger on Account (after insert, after update) {
    if (Trigger.isAfter && (Trigger.isInsert || Trigger.isUpdate) && !QBTriggerHandler.isAccountProcessing) {
        QBTriggerHandler.handleAccountTrigger(Trigger.new, Trigger.oldMap, Trigger.isInsert, Trigger.isUpdate);
    }
}