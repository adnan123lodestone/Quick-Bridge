NetSuiteActivationService.ActivationResult result = NetSuiteActivationService.validatePhaseOne();

if (!result.success) {
  System.debug(LoggingLevel.ERROR, 'NetSuite connector validation failed: ' + JSON.serialize(result));
  System.assert(false, 'NetSuite connector validation failed: ' + String.join(result.messages, ' | '));
}

System.debug('NetSuite connector validation passed: ' + JSON.serialize(result));
