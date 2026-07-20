MetaConnectionValidator.ValidationResult validation = MetaConnectionValidator.validateConnection();
if (!validation.success) {
    System.assert(false, 'Meta schedule activation blocked: ' + validation.message);
}

Integer scheduleCount = MetaScheduleService.activateDefaultSchedules();
System.debug('Activated ' + scheduleCount + ' Meta schedules. The scheduled heartbeat will dispatch campaign and insights sync work.');
