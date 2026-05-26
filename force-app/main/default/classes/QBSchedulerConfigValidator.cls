/**
 * @description Validates QuickBooks configuration before scheduler creation or edits.
 */
public with sharing class QBSchedulerConfigValidator implements SchedulerConfigurationValidator {
    /**
     * @description Runs QuickBooks connection configuration validation.
     */
    public void validate() {
        QuickBooksAuthHandler.validateConfiguration();
    }
}