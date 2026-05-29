# Quick Bridge Architecture Refactor - Implementation Plan

## [Overview]

Comprehensive architectural refactoring to address 10 critical issues in the Quick Bridge Salesforce integration platform.

This plan systematically addresses foundational architectural problems that currently limit scalability, maintainability, and reliability. The refactoring spans service layer consolidation, interface-driven design, resilience patterns (circuit breakers, throttling), error handling standardization, and technical debt reduction across the integration framework.

The implementation is structured in three priority tiers to enable incremental delivery while maintaining system stability. Each tier builds upon previous work, ensuring dependencies are resolved in the correct order. The plan focuses on backward compatibility where possible, with clear migration paths for breaking changes.

## [Types]

New interfaces, enums, and data structures required across all 10 issues.

### Issue #1: Service Layer Consolidation - Types

```apex
// Unified connector descriptor
public class ConnectorDescriptor {
    public String connectorKey;
    public String productKey;
    public String label;
    public Boolean active;
    public Date expiryDate;
    public Map<String, String> configValues;
    public List<String> capabilities;
}

// Configuration result wrapper
public class ConfigResult {
    public Boolean success;
    public String value;
    public String source; // 'instance', 'legacy', 'default'
    public String errorMessage;
}
```

### Issue #2: Interface Abstraction - Types

```apex
// Core work processing interfaces
public interface IWorkProcessor {
    void process(IntegrationWorkRequest request);
    Boolean canHandle(String workType);
    Integer priority();
}

public interface IWorkHandler {
    void handle(Integration_Work_Item__c item);
    String getSupportedIntegration();
    String getSupportedOperation();
}

public interface IWorkRouter {
    IWorkHandler resolveHandler(String integrationType, String operationType);
    List<String> getSupportedWorkTypes();
}

// Work request wrapper
public class IntegrationWorkRequest {
    public Integration_Work_Item__c item;
    public Map<String, Object> context;
    public Integer attemptNumber;
    public Datetime enqueuedAt;
}
```

### Issue #3: Pre-flight Throttling - Types

```apex
// Throttle decision result
public class ThrottleResult {
    public Boolean allowed;
    public String reason;
    public Integer remainingQuota;
    public Integer quotaLimit;
    public Datetime quotaResetAt;
}

// Throttle cache entry
public class ThrottleEntry {
    public String connectorKey;
    public Integer currentUsage;
    public Integer limit;
    public Datetime periodStart;
    public Datetime periodEnd;
}
```

### Issue #4: Centralized Error Handling - Types

```apex
// Standardized error context
public class ErrorContext {
    public String operationId;
    public String correlationId;
    public String componentName;
    public String operationName;
    public Map<String, Object> contextData;
    public Exception sourceException;
    public Integer httpStatusCode;
    public String externalReference;
}

// Error handling result
public class ErrorHandlingResult {
    public Boolean shouldRetry;
    public Integer retryDelaySeconds;
    public String errorCategory;
    public String userFriendlyMessage;
    public List<String> diagnosticMessages;
}
```

### Issue #5: Carrier Adapter Factory - Types

```apex
// Adapter registry entry
public class AdapterRegistration {
  public String carrierKey;
  public Type adapterClass;
  public Integer priority;
  public Boolean enabled;
}
```

### Issue #6: Circuit Breaker - Types

```apex
// Circuit breaker states
public enum CircuitState {
    CLOSED, OPEN, HALF_OPEN
}

// Circuit breaker configuration
public class CircuitBreakerConfig {
    public Integer failureThreshold;
    public Integer successThreshold;
    public Integer timeoutSeconds;
    public Integer openDurationSeconds;
}

// Circuit breaker status
public class CircuitStatus {
    public CircuitState state;
    public Integer failureCount;
    public Integer successCount;
    public Datetime lastFailureTime;
    public Datetime stateChangedAt;
}
```

### Issue #7: Migration Service - Types

```apex
// Migration plan
public class MigrationPlan {
    public String planId;
    public String connectorKey;
    public List<MigrationStep> steps;
    public Map<String, Object> rollbackData;
}

// Migration step
public class MigrationStep {
    public String stepId;
    public String stepName;
    public String stepType; // 'validate', 'backup', 'migrate', 'verify'
    public Boolean completed;
    public String result;
}

// Migration audit record
public class MigrationAudit {
    public String planId;
    public Datetime startedAt;
    public Datetime completedAt;
    public String status;
    public List<String> messages;
}
```

### Issue #8: Test Data Factory - Types

```apex
// Builder pattern interfaces
public interface ITestDataBuilder {
    SObject build();
    ITestDataBuilder with(String fieldName, Object value);
}

// Test data context
public class TestDataContext {
    public Map<String, List<SObject>> recordsByType;
    public Map<String, Map<String, SObject>> recordsByExternalId;
    public Boolean commitRecords;
}
```

### Issue #9: Batch Framework - Types

```apex
// Batch execution metrics
public class BatchMetrics {
    public Id batchJobId;
    public Integer totalRecords;
    public Integer processedRecords;
    public Integer successCount;
    public Integer failureCount;
    public Datetime startedAt;
    public Datetime completedAt;
}

// Dead letter entry
public class DeadLetterEntry {
    public String batchJobId;
    public SObject failedRecord;
    public String errorMessage;
    public Integer attemptCount;
    public Datetime firstFailedAt;
}
```

### Issue #10: Payment Gateway - Types

```apex
// Payment gateway interface
public interface IPaymentGateway {
    PaymentResult processPayment(PaymentRequest request);
    PaymentResult refund(String transactionId, Decimal amount);
    PaymentStatus getStatus(String transactionId);
    String getGatewayKey();
}

// Payment request wrapper
public class PaymentRequest {
    public Decimal amount;
    public String currency;
    public String customerToken;
    public String paymentMethodToken;
    public Map<String, Object> metadata;
}

// Payment result wrapper
public class PaymentResult {
    public Boolean success;
    public String transactionId;
    public String status;
    public String errorMessage;
    public Map<String, Object> gatewayResponse;
}
```

## [Files]

All file modifications, creations, and deletions organized by issue.

### Issue #1: Service Layer Consolidation

**New Files:**

- `force-app/main/default/classes/ConnectorConfigManager.cls` - Unified configuration manager
- `force-app/main/default/classes/ConnectorConfigManager.cls-meta.xml`
- `force-app/main/default/classes/ConnectorConfigManagerTest.cls`
- `force-app/main/default/classes/ConnectorConfigManagerTest.cls-meta.xml`

**Modified Files:**

- `force-app/main/default/classes/ConnectorConfigService.cls` - Delegate to ConnectorConfigManager
- `force-app/main/default/classes/ConnectorConfigResolver.cls` - Delegate to ConnectorConfigManager
- `force-app/main/default/classes/ConnectorRegistryService.cls` - Remove duplicate logic
- `force-app/main/default/classes/IntegrationConnectorRegistry.cls` - Facade pattern implementation

**Files to Mark as Deprecated (keep for backward compatibility):**

- Document deprecation in class headers for ConnectorConfigResolver and legacy methods in ConnectorConfigService

### Issue #2: Interface Abstraction

**New Files:**

- `force-app/main/default/classes/IWorkProcessor.cls`
- `force-app/main/default/classes/IWorkProcessor.cls-meta.xml`
- `force-app/main/default/classes/IWorkRouter.cls`
- `force-app/main/default/classes/IWorkRouter.cls-meta.xml`
- `force-app/main/default/classes/WorkProcessorFactory.cls`
- `force-app/main/default/classes/WorkProcessorFactory.cls-meta.xml`
- `force-app/main/default/classes/DefaultWorkProcessor.cls`
- `force-app/main/default/classes/DefaultWorkProcessor.cls-meta.xml`
- `force-app/main/default/classes/WorkProcessorFactoryTest.cls`
- `force-app/main/default/classes/WorkProcessorFactoryTest.cls-meta.xml`

**Modified Files:**

- `force-app/main/default/classes/IntegrationWorkHandler.cls` - Add new methods to interface
- `force-app/main/default/classes/IntegrationWorkRouter.cls` - Implement IWorkRouter
- `force-app/main/default/classes/IntegrationWorkProcessor.cls` - Use IWorkProcessor
- `force-app/main/default/classes/CarrierIntegrationWorker.cls` - Implement IWorkHandler updates

### Issue #3: Pre-flight Throttling

**New Files:**

- `force-app/main/default/classes/IntegrationThrottler.cls`
- `force-app/main/default/classes/IntegrationThrottler.cls-meta.xml`
- `force-app/main/default/classes/IntegrationThrottlerTest.cls`
- `force-app/main/default/classes/IntegrationThrottlerTest.cls-meta.xml`
- `force-app/main/default/classes/ThrottleCache.cls`
- `force-app/main/default/classes/ThrottleCache.cls-meta.xml`

**Modified Files:**

- `force-app/main/default/classes/IntegrationUsageService.cls` - Add throttle check method
- `force-app/main/default/classes/IntegrationWorkService.cls` - Add pre-flight throttle check
- `force-app/main/default/classes/IntegrationWorkDispatcher.cls` - Check throttle before dispatch

### Issue #4: Centralized Error Handling

**New Files:**

- `force-app/main/default/classes/IntegrationErrorHandler.cls`
- `force-app/main/default/classes/IntegrationErrorHandler.cls-meta.xml`
- `force-app/main/default/classes/IntegrationErrorHandlerTest.cls`
- `force-app/main/default/classes/IntegrationErrorHandlerTest.cls-meta.xml`
- `force-app/main/default/classes/ErrorContextBuilder.cls`
- `force-app/main/default/classes/ErrorContextBuilder.cls-meta.xml`

**Modified Files:**

- `force-app/main/default/classes/ErrorLogUtility.cls` - Integrate with IntegrationErrorHandler
- `force-app/main/default/classes/IntegrationWorkProcessor.cls` - Use IntegrationErrorHandler
- `force-app/main/default/classes/FedExCarrierAdapter.cls` - Use IntegrationErrorHandler
- `force-app/main/default/classes/AuthorizeNetPaymentService.cls` - Use IntegrationErrorHandler

### Issue #5: Carrier Adapter Factory

**New Files:**

- `force-app/main/default/classes/CarrierAdapterRegistry.cls`
- `force-app/main/default/classes/CarrierAdapterRegistry.cls-meta.xml`
- `force-app/main/default/classes/CarrierAdapterRegistryTest.cls`
- `force-app/main/default/classes/CarrierAdapterRegistryTest.cls-meta.xml`

**Modified Files:**

- `force-app/main/default/classes/CarrierAdapterFactory.cls` - Use registry pattern
- `force-app/main/default/classes/ConnectorRegistryService.cls` - Add adapter registration support

**Custom Metadata to Create:**

- `Carrier_Adapter_Config__mdt` - Metadata type for adapter registration

### Issue #6: Circuit Breaker

**New Files:**

- `force-app/main/default/classes/CircuitBreaker.cls`
- `force-app/main/default/classes/CircuitBreaker.cls-meta.xml`
- `force-app/main/default/classes/CircuitBreakerTest.cls`
- `force-app/main/default/classes/CircuitBreakerTest.cls-meta.xml`
- `force-app/main/default/classes/CircuitBreakerManager.cls`
- `force-app/main/default/classes/CircuitBreakerManager.cls-meta.xml`

**Custom Objects to Create:**

- `Circuit_Breaker_State__c` - Custom object to persist circuit state

**Modified Files:**

- `force-app/main/default/classes/FedExCarrierAdapter.cls` - Wrap HTTP calls with circuit breaker
- `force-app/main/default/classes/AuthorizeNetPaymentService.cls` - Wrap HTTP calls with circuit breaker

### Issue #7: Migration Service

**New Files:**

- `force-app/main/default/classes/MigrationOrchestrator.cls`
- `force-app/main/default/classes/MigrationOrchestrator.cls-meta.xml`
- `force-app/main/default/classes/MigrationOrchestratorTest.cls`
- `force-app/main/default/classes/MigrationOrchestratorTest.cls-meta.xml`
- `force-app/main/default/classes/MigrationValidator.cls`
- `force-app/main/default/classes/MigrationValidator.cls-meta.xml`

**Custom Objects to Create:**

- `Migration_Audit__c` - Audit trail for migrations

**Modified Files:**

- `force-app/main/default/classes/QuickbridgeConfigMigrationService.cls` - Use MigrationOrchestrator

### Issue #8: Test Data Factory

**New Files:**

- `force-app/main/default/classes/TestDataBuilder.cls`
- `force-app/main/default/classes/TestDataBuilder.cls-meta.xml`
- `force-app/main/default/classes/ConnectorTestDataBuilder.cls`
- `force-app/main/default/classes/ConnectorTestDataBuilder.cls-meta.xml`
- `force-app/main/default/classes/WorkRequestTestDataBuilder.cls`
- `force-app/main/default/classes/WorkRequestTestDataBuilder.cls-meta.xml`
- `force-app/main/default/classes/TestDataBuilderTest.cls`
- `force-app/main/default/classes/TestDataBuilderTest.cls-meta.xml`

**Modified Files:**

- `force-app/main/default/classes/IntegrationWorkTestFactory.cls` - Refactor to use builders

### Issue #9: Batch Framework

**New Files:**

- `force-app/main/default/classes/MonitoredBatchJob.cls`
- `force-app/main/default/classes/MonitoredBatchJob.cls-meta.xml`
- `force-app/main/default/classes/BatchProgressTracker.cls`
- `force-app/main/default/classes/BatchProgressTracker.cls-meta.xml`
- `force-app/main/default/classes/DeadLetterQueue.cls`
- `force-app/main/default/classes/DeadLetterQueue.cls-meta.xml`
- `force-app/main/default/classes/MonitoredBatchJobTest.cls`
- `force-app/main/default/classes/MonitoredBatchJobTest.cls-meta.xml`

**Custom Objects to Create:**

- `Batch_Execution_Log__c` - Track batch execution metrics
- `Dead_Letter_Record__c` - Store failed batch records

**Modified Files:**

- `force-app/main/default/classes/CarrierTrackingStatusBatch.cls` - Extend MonitoredBatchJob
- `force-app/main/default/classes/GenericScheduleDispatcher.cls` - Add monitoring hooks

### Issue #10: Payment Gateway

**New Files:**

- `force-app/main/default/classes/IPaymentGateway.cls`
- `force-app/main/default/classes/IPaymentGateway.cls-meta.xml`
- `force-app/main/default/classes/PaymentGatewayFactory.cls`
- `force-app/main/default/classes/PaymentGatewayFactory.cls-meta.xml`
- `force-app/main/default/classes/AuthorizeNetGatewayAdapter.cls`
- `force-app/main/default/classes/AuthorizeNetGatewayAdapter.cls-meta.xml`
- `force-app/main/default/classes/PaymentGatewayFactoryTest.cls`
- `force-app/main/default/classes/PaymentGatewayFactoryTest.cls-meta.xml`

**Modified Files:**

- `force-app/main/default/classes/AuthorizeNetPaymentService.cls` - Delegate to adapter
- `force-app/main/default/classes/PaymentMetadataService.cls` - Integrate gateway factory

## [Functions]

Key function modifications organized by issue.

### Issue #1: Service Layer Consolidation

**New Functions in ConnectorConfigManager:**

```apex
public static ConnectorDescriptor getConnector(String connectorKey)
public static ConfigResult getConfigValue(String connectorKey, String fieldKey)
public static Boolean isActive(String connectorKey)
public static void upsertConfigValue(String connectorKey, String fieldKey, String value)
private static ConnectorDescriptor loadFromInstance(String connectorKey)
private static ConnectorDescriptor loadFromLegacy(String connectorKey)
private static void hydrateCapabilities(ConnectorDescriptor descriptor)
```

**Modified Functions in ConnectorConfigService:**

```apex
// Delegate to ConnectorConfigManager
public static ConnectorConfig getConfig(String connectorKey) {
    return ConnectorConfigManager.getConnector(connectorKey);
}

public static String getConfigValue(String connectorKey, String fieldKey) {
    return ConnectorConfigManager.getConfigValue(connectorKey, fieldKey).value;
}
```

**Modified Functions in ConnectorConfigResolver:**

```apex
// Simple delegation
public static String getValue(String connectorKey, String fieldKey) {
    return ConnectorConfigManager.getConfigValue(connectorKey, fieldKey).value;
}
```

### Issue #2: Interface Abstraction

**New Functions in WorkProcessorFactory:**

```apex
public static IWorkProcessor getProcessor(String workType)
public static void registerProcessor(String workType, Type processorClass)
private static Map<String, Type> loadProcessorRegistry()
```

**Modified Functions in IntegrationWorkRouter:**

```apex
// Implement IWorkRouter interface
public IWorkHandler resolveHandler(String integrationType, String operationType)
public List<String> getSupportedWorkTypes()

// Existing process() method updated to use interface
public static void process(Integration_Work_Item__c item) {
    IWorkRouter router = new IntegrationWorkRouter();
    IWorkHandler handler = router.resolveHandler(item.Integration__c, item.Operation__c);
    handler.handle(item);
}
```

**New Functions in DefaultWorkProcessor:**

```apex
public void process(IntegrationWorkRequest request)
public Boolean canHandle(String workType)
public Integer priority()
private void validateRequest(IntegrationWorkRequest request)
```

### Issue #3: Pre-flight Throttling

**New Functions in IntegrationThrottler:**

```apex
public static ThrottleResult allowRequest(String connectorKey, Integer units)
public static ThrottleEntry getCurrentUsage(String connectorKey)
public static void recordUsage(String connectorKey, Integer units)
private static ThrottleEntry loadFromCache(String connectorKey)
private static void saveToCache(ThrottleEntry entry)
private static Integer getLimit(String connectorKey)
```

**Modified Functions in IntegrationUsageService:**

```apex
// New pre-flight check
public static void assertCanConsumeTask(String product, Integer units) {
    ThrottleResult result = IntegrationThrottler.allowRequest(product, units);
    if (!result.allowed) {
        throw new AuraHandledException(result.reason);
    }
}
```

**New Functions in IntegrationWorkDispatcher:**

```apex
// Add throttle check before dispatch
private static Boolean canDispatchWork(Integration_Work_Item__c item) {
    ThrottleResult result = IntegrationThrottler.allowRequest(item.Integration__c, 1);
    return result.allowed;
}
```

### Issue #4: Centralized Error Handling

**New Functions in IntegrationErrorHandler:**

```apex
public static void handleWithContext(Exception e, ErrorContext context)
public static ErrorHandlingResult analyzeError(Exception e, ErrorContext context)
public static void logError(ErrorContext context)
private static Boolean shouldRetry(Exception e, ErrorContext context)
private static String generateCorrelationId()
private static void notifyStakeholders(ErrorContext context)
```

**New Functions in ErrorContextBuilder:**

```apex
public ErrorContextBuilder withOperationId(String operationId)
public ErrorContextBuilder withComponent(String componentName, String operationName)
public ErrorContextBuilder withException(Exception e)
public ErrorContextBuilder withHttpStatus(Integer statusCode)
public ErrorContextBuilder addContext(String key, Object value)
public ErrorContext build()
```

**Modified Functions in ErrorLogUtility:**

```apex
// Integration point with new error handler
public static void logError(LogContext context) {
    ErrorContext errorContext = convertToErrorContext(context);
    IntegrationErrorHandler.logError(errorContext);
}
```

### Issue #5: Carrier Adapter Factory

**New Functions in CarrierAdapterRegistry:**

```apex
public static void registerAdapter(String carrierKey, Type adapterClass)
public static ICarrierAdapter getAdapter(String carrierKey)
public static List<String> getSupportedCarriers()
private static Map<String, AdapterRegistration> loadRegistry()
private static void validateAdapter(Type adapterClass)
```

**Modified Functions in CarrierAdapterFactory:**

```apex
// Simplified to use registry
public static ICarrierAdapter getAdapter(String carrierType) {
    return CarrierAdapterRegistry.getAdapter(normalizeCarrierKey(carrierType));
}
```

### Issue #6: Circuit Breaker

**New Functions in CircuitBreaker:**

```apex
public HttpResponse execute(HttpRequest request)
public Boolean allowRequest()
public void recordSuccess()
public void recordFailure()
private void transitionToOpen()
private void transitionToClosed()
private void transitionToHalfOpen()
private Boolean shouldAttemptReset()
```

**New Functions in CircuitBreakerManager:**

```apex
public static CircuitBreaker getCircuitBreaker(String serviceName)
public static CircuitStatus getStatus(String serviceName)
public static void resetCircuit(String serviceName)
private static CircuitBreaker createCircuitBreaker(String serviceName)
private static CircuitBreakerConfig loadConfig(String serviceName)
```

### Issue #7: Migration Service

**New Functions in MigrationOrchestrator:**

```apex
public MigrationResult execute(MigrationPlan plan)
public MigrationPlan createPlan(String connectorKey)
private void validatePreConditions(MigrationPlan plan)
private void executeStep(MigrationStep step, MigrationPlan plan)
private void rollback(MigrationPlan plan, Integer failedStepIndex)
private void createAuditRecord(MigrationPlan plan, String status)
```

**New Functions in MigrationValidator:**

```apex
public List<String> validateConnectorConfig(String connectorKey)
public Boolean canMigrate(String connectorKey)
public List<String> identifyConflicts(String connectorKey)
private void validateInstanceData(String connectorKey)
private void validateLegacyData(String connectorKey)
```

### Issue #8: Test Data Factory

**New Functions in TestDataBuilder:**

```apex
public static ConnectorTestDataBuilder connector()
public static WorkRequestTestDataBuilder workRequest()
public static TestDataContext createContext()
public static void commitAll(TestDataContext context)
```

**New Functions in ConnectorTestDataBuilder:**

```apex
public ConnectorTestDataBuilder withKey(String key)
public ConnectorTestDataBuilder withLabel(String label)
public ConnectorTestDataBuilder active()
public ConnectorTestDataBuilder inactive()
public ConnectorTestDataBuilder withCapability(String capability)
public Connector_Instance__c build()
```

**New Functions in WorkRequestTestDataBuilder:**

```apex
public WorkRequestTestDataBuilder forIntegration(String integrationType)
public WorkRequestTestDataBuilder withOperation(String operation)
public WorkRequestTestDataBuilder withPayload(Map<String, Object> payload)
public WorkRequestTestDataBuilder withStatus(String status)
public Integration_Work_Item__c build()
```

### Issue #9: Batch Framework

**New Functions in MonitoredBatchJob:**

```apex
public void start(Database.BatchableContext bc)
public void execute(Database.BatchableContext bc, List<SObject> scope)
public void finish(Database.BatchableContext bc)
protected abstract void processRecords(List<SObject> scope)
protected abstract void handleFailedRecord(SObject record, Exception e)
private void trackProgress(Integer processedCount)
private void logMetrics(Database.BatchableContext bc)
```

**New Functions in BatchProgressTracker:**

```apex
public static void initializeTracking(Id batchJobId, Integer totalRecords)
public static void updateProgress(Id batchJobId, Integer processedCount)
public static BatchMetrics getMetrics(Id batchJobId)
```

**New Functions in DeadLetterQueue:**

```apex
public static void addFailedRecord(String batchJobId, SObject record, String errorMessage)
public static List<DeadLetterEntry> getFailedRecords(String batchJobId)
public static void retryFailedRecords(String batchJobId)
public static void clearQueue(String batchJobId)
```

### Issue #10: Payment Gateway

**New Functions in PaymentGatewayFactory:**

```apex
public static IPaymentGateway getGateway(String gatewayKey)
public static void registerGateway(String gatewayKey, Type gatewayClass)
public static List<String> getSupportedGateways()
private static Map<String, Type> loadGatewayRegistry()
```

**New Functions in AuthorizeNetGatewayAdapter:**

```apex
public PaymentResult processPayment(PaymentRequest request)
public PaymentResult refund(String transactionId, Decimal amount)
public PaymentStatus getStatus(String transactionId)
public String getGatewayKey()
private HttpResponse sendRequest(String endpoint, Map<String, Object> body)
```

## [Classes]

Class-level modifications organized by issue.

### Issue #1: Service Layer Consolidation

**New Class: ConnectorConfigManager**

- Purpose: Single source of truth for connector configuration
- Key Responsibilities:
  - Load configuration from Connector_Instance**c and Connector_Config_Value**c
  - Fallback to legacy Quickbridge_Config\_\_mdt
  - Cache configuration in static variables
  - Provide unified API for all configuration access

**Modified Class: ConnectorConfigService**

- Change: Becomes a facade that delegates to ConnectorConfigManager
- Maintains public API for backward compatibility
- All implementation logic moves to ConnectorConfigManager

**Modified Class: ConnectorConfigResolver**

- Change: Simplifies to pure delegation wrapper
- Marked as deprecated in class documentation
- Maintains API for existing consumers during transition

**Modified Class: IntegrationConnectorRegistry**

- Change: Remove duplicate fromCanonical() logic
- Delegate to ConnectorRegistryService directly
- Simplify byKey() and connectors() methods

### Issue #2: Interface Abstraction

**New Interface: IWorkProcessor**

- Methods: process(), canHandle(), priority()
- Purpose: Define contract for work item processors

**New Interface: IWorkRouter**

- Methods: resolveHandler(), getSupportedWorkTypes()
- Purpose: Define contract for work routing logic

**New Class: WorkProcessorFactory**

- Purpose: Registry and factory for IWorkProcessor implementations
- Uses metadata-driven registration via Custom Metadata
- Supports dynamic processor registration at runtime

**New Class: DefaultWorkProcessor**

- Implements: IWorkProcessor
- Purpose: Standard implementation for common work types
- Handles validation, routing, and error wrapping

**Modified Class: IntegrationWorkRouter**

- Change: Implements IWorkRouter interface
- Adds getSupportedWorkTypes() method
- Refactors process() to use interface methods

**Modified Class: IntegrationWorkProcessor**

- Change: Uses IWorkProcessor for execution
- Retrieves processor from WorkProcessorFactory
- Simplified error handling using interface contracts

### Issue #3: Pre-flight Throttling

**New Class: IntegrationThrottler**

- Purpose: Pre-flight throttle checking and enforcement
- Uses Platform Cache for performance
- Checks limits before work execution
- Records usage atomically

**New Class: ThrottleCache**

- Purpose: Platform Cache wrapper for throttle state
- Manages cache partitions
- Handles cache misses gracefully
- Provides TTL-based expiration

### Issue #4: Centralized Error Handling

**New Class: IntegrationErrorHandler**

- Purpose: Centralized error handling with correlation IDs
- Analyzes errors for retry eligibility
- Generates structured error logs
- Integrates with ErrorLogUtility

**New Class: ErrorContextBuilder**

- Purpose: Fluent API for building ErrorContext objects
- Validates required fields
- Generates correlation IDs automatically
- Captures stack traces and contextual data

**Modified Class: ErrorLogUtility**

- Change: Integration point for IntegrationErrorHandler
- Converts LogContext to ErrorContext
- Maintains backward compatibility
- Adds correlation ID to all logs

### Issue #5: Carrier Adapter Factory

**New Class: CarrierAdapterRegistry**

- Purpose: Metadata-driven adapter registration
- Loads from Carrier_Adapter_Config\_\_mdt
- Validates adapter classes implement ICarrierAdapter
- Provides thread-safe singleton access

**Modified Class: CarrierAdapterFactory**

- Change: Delegates to CarrierAdapterRegistry
- Removes hard-coded carrier logic
- Simplified error handling
- Maintains public API

### Issue #6: Circuit Breaker

**New Class: CircuitBreaker**

- Purpose: Circuit breaker implementation for HTTP calls
- States: CLOSED, OPEN, HALF_OPEN
- Tracks failure/success counts
- Auto-recovery after timeout

**New Class: CircuitBreakerManager**

- Purpose: Manages circuit breaker instances
- One circuit per external service
- Persists state in Circuit_Breaker_State\_\_c
- Provides manual reset capability

**Modified Class: FedExCarrierAdapter**

- Change: Wrap all HTTP calls with CircuitBreaker
- Handle CircuitOpenException gracefully
- Log circuit breaker events

**Modified Class: AuthorizeNetPaymentService**

- Change: Wrap all HTTP calls with CircuitBreaker
- Handle CircuitOpenException gracefully
- Log circuit breaker events

### Issue #7: Migration Service

**New Class: MigrationOrchestrator**

- Purpose: Saga pattern for configuration migrations
- Creates migration plans with rollback data
- Executes steps with savepoints
- Creates audit trail

**New Class: MigrationValidator**

- Purpose: Pre-migration validation
- Checks for data conflicts
- Validates metadata integrity
- Provides migration readiness report

**Modified Class: QuickbridgeConfigMigrationService**

- Change: Delegate to MigrationOrchestrator
- Maintain public API for backward compatibility
- Add idempotency checks

### Issue #8: Test Data Factory

**New Class: TestDataBuilder**

- Purpose: Factory for creating test data builders
- Provides fluent API entry points
- Manages TestDataContext
- Supports batch inserts

**New Class: ConnectorTestDataBuilder**

- Purpose: Builder for Connector_Instance\_\_c test data
- Fluent API for common configurations
- Handles related Connector_Config_Value\_\_c records
- Supports realistic test scenarios

**New Class: WorkRequestTestDataBuilder**

- Purpose: Builder for Integration_Work_Item\_\_c test data
- Fluent API for common work types
- Creates related lock records
- Supports various work statuses

**Modified Class: IntegrationWorkTestFactory**

- Change: Refactor to use new builders
- Maintain existing public methods
- Deprecate old methods with @deprecated annotation

### Issue #9: Batch Framework

**New Abstract Class: MonitoredBatchJob**

- Purpose: Base class for all batch jobs
- Implements Database.Batchable<SObject>
- Auto-tracks progress and metrics
- Handles failed records via DeadLetterQueue
- Logs execution metrics

**New Class: BatchProgressTracker**

- Purpose: Real-time batch progress tracking
- Uses Batch_Execution_Log\_\_c for persistence
- Provides progress percentage
- Estimates completion time

**New Class: DeadLetterQueue**

- Purpose: Failed record management
- Stores failures in Dead_Letter_Record\_\_c
- Supports retry with backoff
- Provides failure analysis

**Modified Class: CarrierTrackingStatusBatch**

- Change: Extend MonitoredBatchJob
- Implement processRecords() method
- Override handleFailedRecord() for custom logic

### Issue #10: Payment Gateway

**New Interface: IPaymentGateway**

- Methods: processPayment(), refund(), getStatus(), getGatewayKey()
- Purpose: Define contract for payment gateways

**New Class: PaymentGatewayFactory**

- Purpose: Factory for IPaymentGateway implementations
- Metadata-driven gateway registration
- Supports multiple payment providers
- Thread-safe singleton pattern

**New Class: AuthorizeNetGatewayAdapter**

- Implements: IPaymentGateway
- Purpose: Authorize.Net specific implementation
- Handles authentication and API calls
- Integrates with ConnectorConfigService

**Modified Class: AuthorizeNetPaymentService**

- Change: Delegate to AuthorizeNetGatewayAdapter
- Maintain public API for backward compatibility
- Add gateway factory integration

## [Dependencies]

No new external dependencies required for this refactoring.

All implementations use standard Salesforce platform capabilities:

- Apex Classes and Interfaces
- Custom Objects and Custom Metadata Types
- Platform Cache (for throttling)
- Database.Batchable interface (for batch framework)
- Standard HTTP and JSON libraries

### Platform Requirements

- Salesforce API Version: 61.0 (already in use)
- Platform Cache: Required for throttling (included in all Salesforce editions)
- Custom Metadata Types: Used extensively (already in use)
- Custom Objects: For audit trails and state persistence

### Existing Dependencies

The refactoring maintains compatibility with existing dependencies:

- All current Quickbridge_Config\_\_mdt records
- Existing Connector_Instance**c and Connector_Config_Value**c records
- Current Integration_Work_Item**c and Integration_Work_Lock**c infrastructure

## [Testing]

Comprehensive testing strategy covering all 10 issues.

### Test Coverage Requirements

- Minimum 85% code coverage for all new classes
- 100% coverage for critical path methods (error handling, throttling, circuit breakers)
- Integration tests for cross-component interactions
- Negative test cases for all error handling paths

### Issue #1: Service Layer Consolidation - Testing

**ConnectorConfigManagerTest.cls:**

```apex
@isTest
private class ConnectorConfigManagerTest {
    @isTest static void testGetConnector_WithInstance()
    @isTest static void testGetConnector_WithLegacy()
    @isTest static void testGetConfigValue_HitAndMiss()
    @isTest static void testIsActive_Various Scenarios()
    @isTest static void testUpsertConfigValue_NewAndExisting()
    @isTest static void testCaching()
    @isTest static void testBulkOperations()
}
```

**Existing Test Modifications:**

- Update all tests that reference ConnectorConfigService
- Add assertions for delegation to ConnectorConfigManager
- Test backward compatibility

### Issue #2: Interface Abstraction - Testing

**WorkProcessorFactoryTest.cls:**

```apex
@isTest
private class WorkProcessorFactoryTest {
    @isTest static void testGetProcessor_RegisteredType()
    @isTest static void testGetProcessor_UnregisteredType()
    @isTest static void testRegisterProcessor()
    @isTest static void testMetadataDrivenRegistration()
    @isTest static void testProcessorPriority()
}
```

**Integration Tests:**

- Test complete work processing flow with interfaces
- Verify handler resolution through factory
- Test multiple processor implementations

### Issue #3: Pre-flight Throttling - Testing

**IntegrationThrottlerTest.cls:**

```apex
@isTest
private class IntegrationThrottlerTest {
    @isTest static void testAllowRequest_WithinLimit()
    @isTest static void testAllowRequest_ExceedsLimit()
    @isTest static void testRecordUsage()
    @isTest static void testCacheExpiration()
    @isTest static void testConcurrentRequests()
    @isTest static void testQuotaReset()
}
```

**Performance Tests:**

- Test Platform Cache performance
- Verify throttle check latency < 50ms
- Test high-concurrency scenarios

### Issue #4: Centralized Error Handling - Testing

**IntegrationErrorHandlerTest.cls:**

```apex
@isTest
private class IntegrationErrorHandlerTest {
    @isTest static void testHandleWithContext_RetryableError()
    @isTest static void testHandleWithContext_NonRetryableError()
    @isTest static void testAnalyzeError_VariousExceptions()
    @isTest static void testCorrelationIdGeneration()
    @isTest static void testErrorLogging()
    @isTest static void testStakeholderNotification()
}
```

**ErrorContextBuilderTest.cls:**

- Test fluent API builder pattern
- Verify required field validation
- Test correlation ID assignment

### Issue #5-10: Testing Strategy

Each remaining issue follows similar testing patterns:

- Unit tests for all new classes (85%+ coverage)
- Integration tests for cross-component interactions
- Negative tests for error scenarios
- Performance tests where applicable (throttling, caching, circuit breakers)

## [Implementation Order]

Phased implementation sequence to minimize risk and ensure stability.

### Phase 1: Foundation (High Priority - Issues #1-4)

**Week 1-2: Issue #1 - Service Layer Consolidation**

1. Create ConnectorConfigManager with comprehensive tests
2. Update ConnectorConfigService to delegate
3. Update ConnectorConfigResolver to delegate
4. Run full test suite - ensure 100% backward compatibility
5. Deploy to sandbox for validation

**Week 3-4: Issue #2 - Interface Abstraction**

1. Create IWorkProcessor, IWorkRouter, IWorkHandler interfaces
2. Create WorkProcessorFactory with registry
3. Create DefaultWorkProcessor implementation
4. Update IntegrationWorkRouter to implement IWorkRouter
5. Update IntegrationWorkProcessor to use factory
6. Update existing handlers to implement new interface methods
7. Run integration tests across work processing chain
8. Deploy to sandbox for validation

**Week 5-6: Issue #3 - Pre-flight Throttling**

1. Create ThrottleCache wrapper for Platform Cache
2. Create IntegrationThrottler with throttle logic
3. Update IntegrationUsageService with throttle checks
4. Update IntegrationWorkDispatcher with pre-flight checks
5. Performance test throttling logic
6. Deploy to sandbox and monitor cache performance

**Week 7-8: Issue #4 - Centralized Error Handling**

1. Create ErrorContext and ErrorContextBuilder
2. Create IntegrationErrorHandler
3. Update ErrorLogUtility to integrate
4. Update IntegrationWorkProcessor error handling
5. Update carrier adapters (FedEx) error handling
6. Update payment services error handling
7. Test correlation ID tracking end-to-end
8. Deploy to sandbox for validation

**Phase 1 Validation:**

- All existing functionality preserved
- No regressions in test suite
- Performance benchmarks met
- Error logging includes correlation IDs

### Phase 2: Extensibility (Medium Priority - Issues #5-7)

**Week 9-10: Issue #5 - Carrier Adapter Factory**

1. Create Carrier_Adapter_Config\_\_mdt metadata type
2. Create CarrierAdapterRegistry
3. Update CarrierAdapterFactory to use registry
4. Create metadata records for FedEx and UPS
5. Test adapter resolution through registry
6. Deploy to sandbox for validation

**Week 11-12: Issue #6 - Circuit Breaker**

1. Create Circuit_Breaker_State\_\_c custom object
2. Create CircuitBreaker class with state machine
3. Create CircuitBreakerManager
4. Update FedExCarrierAdapter HTTP calls
5. Update AuthorizeNetPaymentService HTTP calls
6. Test circuit transitions (CLOSED → OPEN → HALF_OPEN → CLOSED)
7. Test auto-recovery after timeout
8. Deploy to sandbox and monitor circuit states

**Week 13-14: Issue #7 - Migration Service**

1. Create Migration_Audit\_\_c custom object
2. Create MigrationValidator for pre-checks
3. Create MigrationOrchestrator with saga pattern
4. Update QuickbridgeConfigMigrationService
5. Test rollback on migration failure
6. Test idempotency of migrations
7. Deploy to sandbox and run test migrations

**Phase 2 Validation:**

- Carrier adapters extensible via metadata
- Circuit breakers protect against external failures
- Migrations are safe with rollback capability

### Phase 3: Technical Debt (Low Priority - Issues #8-10)

**Week 15-16: Issue #8 - Test Data Factory**

1. Create ITestDataBuilder interface
2. Create TestDataBuilder factory class
3. Create ConnectorTestDataBuilder
4. Create WorkRequestTestDataBuilder
5. Update IntegrationWorkTestFactory
6. Refactor existing tests to use builders
7. Measure test execution time improvement

**Week 17-18: Issue #9 - Batch Framework**

1. Create Batch_Execution_Log\_\_c custom object
2. Create Dead_Letter_Record\_\_c custom object
3. Create MonitoredBatchJob abstract class
4. Create BatchProgressTracker
5. Create DeadLetterQueue
6. Update CarrierTrackingStatusBatch to extend MonitoredBatchJob
7. Test progress tracking and dead letter queue
8. Deploy to sandbox and monitor batch execution

**Week 19-20: Issue #10 - Payment Gateway**

1. Create IPaymentGateway interface
2. Create PaymentGatewayFactory
3. Create AuthorizeNetGatewayAdapter
4. Update AuthorizeNetPaymentService to delegate
5. Test gateway abstraction
6. Deploy to sandbox for validation

**Phase 3 Validation:**

- Test data creation simplified
- Batch jobs monitored with progress tracking
- Payment gateways extensible via factory

### Cross-Phase Activities

**Throughout Implementation:**

- Update documentation as components are refactored
- Maintain backward compatibility at all times
- Run full test suite after each change
- Performance benchmark after each phase
- Security review for new platform cache and custom objects
- Code review all changes before deployment

**Deployment Strategy:**

1. All changes deployed first to Developer Sandbox
2. Automated test execution in sandbox
3. Manual UAT in Full Sandbox
4. Incremental deployment to Production (one phase at a time)
5. Monitor Production for 48 hours after each deployment
6. Rollback plan documented for each phase

### Success Criteria

**Phase 1 Complete When:**

- All service layer calls routed through ConnectorConfigManager
- All work processing uses interface-based design
- Throttling prevents quota violations
- All errors include correlation IDs

**Phase 2 Complete When:**

- Carrier adapters registered via metadata
- Circuit breakers protect all external HTTP calls
- Config migrations support rollback

**Phase 3 Complete When:**

- Test data builders used in 80%+ of tests
- All batch jobs extend MonitoredBatchJob
- Payment gateway abstraction supports multiple providers

### Risk Mitigation

**High Risk Items:**

- **Service Layer Changes (Issue #1):** Extensive testing required due to broad impact
  - Mitigation: Feature toggle to switch between old and new implementations
- **Circuit Breaker (Issue #6):** Could block legitimate requests if misconfigured
  - Mitigation: Conservative failure thresholds, manual reset capability
- **Migration Service (Issue #7):** Data loss risk during migrations
  - Mitigation: Mandatory backups, dry-run capability, rollback testing

**Medium Risk Items:**

- **Throttling (Issue #3):** Could reject valid requests if limits misconfigured
  - Mitigation: Generous initial limits, monitoring dashboards
- **Batch Framework (Issue #9):** Failed record handling complexity
  - Mitigation: Comprehensive dead letter queue testing

**Low Risk Items:**

- **Test Data Factory (Issue #8):** No production impact
- **Payment Gateway (Issue #10):** Isolated to payment processing

---

## Summary

This implementation plan provides a comprehensive roadmap for addressing all 10 architectural issues in Quick Bridge. The phased approach ensures:

1. **Foundation First:** Critical service layer and interface issues resolved early
2. **Incremental Delivery:** Each phase delivers standalone value
3. **Backward Compatibility:** Existing functionality preserved throughout
4. **Risk Management:** High-risk changes include mitigation strategies
5. **Testing First:** Comprehensive test coverage for all changes
6. **Production Safety:** Careful deployment with monitoring and rollback plans

**Estimated Timeline:** 20 weeks for complete implementation
**Team Size:** 2-3 developers (1 lead, 1-2 supporting)
**Total Effort:** Approximately 40-60 person-weeks

The plan prioritizes high-value architectural improvements that will establish a solid foundation for future Quick Bridge development while maintaining system stability and reliability.
