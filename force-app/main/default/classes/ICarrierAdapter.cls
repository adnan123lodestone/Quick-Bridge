public interface ICarrierAdapter {
    Map<String, Object> validateAddress(Map<String, Object> payload);
    Map<String, Object> getRateQuote(Map<String, Object> payload);
    Map<String, Object> createShipment(Map<String, Object> payload, Boolean includeLabel);
    Map<String, Object> generateLabel(String masterTrackingNumber, String externalShipmentId, Map<String, Object> payload);
    Map<String, Object> voidShipment(String masterTrackingNumber, String externalShipmentId);
    Map<String, Object> createReturnLabel(Map<String, Object> payload);
    Map<String, Object> syncTrackingStatus(String masterTrackingNumber);
    String getIntegrationType();
}