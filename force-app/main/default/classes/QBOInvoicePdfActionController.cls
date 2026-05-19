public with sharing class QBOInvoicePdfActionController {
  public class PanelData {
    @AuraEnabled
    public Boolean isConfigured;
    @AuraEnabled
    public Boolean qboIdPresent;
    @AuraEnabled
    public String message;
    public PanelData() {
      isConfigured = false;
      qboIdPresent = false;
      message = '';
    }
  }

  @AuraEnabled(cacheable=false)
  public static PanelData getPanelData(Id recordId, String objectApiName) {
    try {
      PanelData data = new PanelData();

      QBOInvoiceMappingResolver.ResolverResult resolved = QBOInvoiceMappingResolver.resolve();

      if (!objectMatches(objectApiName, resolved.invoiceSourceObject)) {
        data.message =
          'QBO Invoice PDF is not configured for this object (' +
          objectApiName +
          '). ' +
          'The configured invoice source object is ' +
          resolved.invoiceSourceObject +
          '.';
        return data;
      }

      if (String.isBlank(resolved.qboIdField)) {
        data.message = 'No QBO Invoice Id field mapping found. Configure a QBO to SF mapping for the Invoice Id field.';
        return data;
      }

      data.isConfigured = true;

      String qboId = fetchQboId(recordId, objectApiName, resolved.qboIdField);
      data.qboIdPresent = String.isNotBlank(qboId);

      if (!data.qboIdPresent) {
        data.message = 'This record has not been synced to QBO yet. Sync it to QBO before downloading the PDF.';
      }

      return data;
    } catch (QBOInvoiceMappingResolver.ResolverException e) {
      logException('getPanelData', e, objectApiName, recordId);
      throw new AuraHandledException(e.getMessage());
    } catch (AuraHandledException e) {
      logException('getPanelData', e, objectApiName, recordId);
      throw e;
    } catch (Exception e) {
      logException('getPanelData', e, objectApiName, recordId);
      throw new AuraHandledException(e.getMessage());
    }
  }

  @AuraEnabled(cacheable=false)
  public static Map<String, String> downloadPdf(
    Id recordId,
    String objectApiName
  ) {
    try {
      QBOInvoiceMappingResolver.ResolverResult resolved = QBOInvoiceMappingResolver.resolve();

      if (!objectMatches(objectApiName, resolved.invoiceSourceObject)) {
        throw new AuraHandledException(
          'This action is only available on the QBO Invoice source object (' +
            resolved.invoiceSourceObject +
            '). This record is a ' +
            objectApiName +
            '.'
        );
      }

      if (String.isBlank(resolved.qboIdField)) {
        throw new AuraHandledException(
          'No QBO Invoice Id field mapping found. Configure a QBO to SF mapping for the Invoice Id field.'
        );
      }

      String qboId = fetchQboId(recordId, objectApiName, resolved.qboIdField);
      if (String.isBlank(qboId)) {
        throw new AuraHandledException(
          'This record has not been synced to QBO yet. Sync it to QBO before downloading the PDF.'
        );
      }

      String displayName = fetchDisplayName(
        recordId,
        objectApiName,
        resolved.displayNameField
      );

      HttpResponse res = QuickBooksAuthHandler.makeBinaryApiCall(
        '/invoice/' + qboId + '/pdf'
      );

      if (res.getStatusCode() != 200) {
        throw new AuraHandledException(
          'QBO returned HTTP ' +
            res.getStatusCode() +
            ' when fetching the invoice PDF. ' +
            'Verify the QBO connection and invoice status.'
        );
      }

      Blob pdfBlob = res.getBodyAsBlob();
      if (pdfBlob == null || pdfBlob.size() == 0) {
        throw new AuraHandledException(
          'QBO returned an empty PDF body. Please try again.'
        );
      }

      // Title includes QBO id so each distinct invoice gets its own file;
      // re-downloading the same invoice adds a new version to that same file.
      String fileTitle =
        'QBO Invoice PDF' +
        (String.isNotBlank(displayName) ? ' - ' + displayName : '') +
        ' (' +
        qboId +
        ')';
      String contentDocumentId = savePdf(recordId, pdfBlob, fileTitle);

      Map<String, String> result = new Map<String, String>();
      result.put('contentDocumentId', contentDocumentId);
      result.put('message', 'PDF saved successfully.');
      return result;
    } catch (QBOInvoiceMappingResolver.ResolverException e) {
      logException('downloadPdf', e, objectApiName, recordId);
      throw new AuraHandledException(e.getMessage());
    } catch (AuraHandledException e) {
      logException('downloadPdf', e, objectApiName, recordId);
      throw e;
    } catch (Exception e) {
      logException('downloadPdf', e, objectApiName, recordId);
      throw new AuraHandledException(e.getMessage());
    }
  }

  // Dynamically queries the QBO id field from the record.
  private static String fetchQboId(
    Id recordId,
    String objectApiName,
    String qboIdField
  ) {
    String query =
      'SELECT ' +
      qboIdField +
      ' FROM ' +
      objectApiName +
      ' WHERE Id = :recordId LIMIT 1';
    List<SObject> records = Database.query(query);
    if (records.isEmpty())
      return null;
    Object val = records[0].get(qboIdField);
    return val == null ? null : String.valueOf(val);
  }

  // Dynamically queries the display name field. Gracefully returns null if no Name field exists.
  private static String fetchDisplayName(
    Id recordId,
    String objectApiName,
    String displayNameField
  ) {
    if (String.isBlank(displayNameField))
      return null;
    try {
      String query =
        'SELECT ' +
        displayNameField +
        ' FROM ' +
        objectApiName +
        ' WHERE Id = :recordId LIMIT 1';
      List<SObject> records = Database.query(query);
      if (records.isEmpty())
        return null;
      Object val = records[0].get(displayNameField);
      return val == null ? null : String.valueOf(val);
    } catch (Exception e) {
      return null;
    }
  }

  // Saves the PDF blob. Creates a new ContentVersion on an existing document if one already exists
  // for this record with the same title; otherwise creates a fresh document and links it.
  private static String savePdf(Id recordId, Blob pdfBlob, String fileTitle) {
    String safeTitle = fileTitle.replaceAll('[^A-Za-z0-9_ \\-]', '');
    String pathOnClient = safeTitle.replaceAll(' ', '_') + '.pdf';

    // Check for an existing ContentDocument linked to this record with the same title
    List<ContentDocumentLink> existing = [
      SELECT ContentDocumentId
      FROM ContentDocumentLink
      WHERE LinkedEntityId = :recordId AND ContentDocument.Title = :safeTitle
      LIMIT 1
    ];

    if (!existing.isEmpty()) {
      // Insert a new version on the existing document
      String existingDocId = existing[0].ContentDocumentId;
      ContentVersion newVersion = new ContentVersion(
        Title = safeTitle,
        PathOnClient = pathOnClient,
        VersionData = pdfBlob,
        ContentDocumentId = existingDocId
      );
      insert newVersion;
      return existingDocId;
    }

    // Create a brand-new document and link it
    ContentVersion cv = new ContentVersion(
      Title = safeTitle,
      PathOnClient = pathOnClient,
      VersionData = pdfBlob,
      Origin = 'H'
    );
    insert cv;

    cv = [
      SELECT ContentDocumentId
      FROM ContentVersion
      WHERE Id = :cv.Id
      LIMIT 1
    ];

    insert new ContentDocumentLink(
      ContentDocumentId = cv.ContentDocumentId,
      LinkedEntityId = recordId,
      ShareType = 'V',
      Visibility = 'AllUsers'
    );

    return cv.ContentDocumentId;
  }

  // Namespace-strips both names before comparing so namespace differences don't cause mismatches.
  private static Boolean objectMatches(
    String objectApiName,
    String configuredObject
  ) {
    return stripNamespace(objectApiName)
      .equalsIgnoreCase(stripNamespace(configuredObject));
  }

  private static String stripNamespace(String name) {
    if (String.isBlank(name))
      return '';
    if (name.endsWith('__c') && name.indexOf('__') != name.lastIndexOf('__')) {
      return name.substringAfter('__');
    }
    return name;
  }

  private static void logException(
    String methodName,
    Exception e,
    String objectApiName,
    Id recordId
  ) {
    ErrorLogUtility.LogContext ctx = new ErrorLogUtility.LogContext();
    ctx.gatewayName = 'QuickBooks';
    ctx.classMethodName = 'QBOInvoicePdfActionController.' + methodName;
    ctx.errorMessage = e.getTypeName() + ': ' + e.getMessage();
    ctx.stackTrace = e.getStackTraceString();
    ctx.sourceObjectApiName = objectApiName;
    ctx.sourceRecordId = recordId;
    ctx.sourceRecordIdText = recordId == null ? null : String.valueOf(recordId);
    ctx.errorCategory = 'Code Exception';
    ErrorLogUtility.logError(ctx);
  }
}
