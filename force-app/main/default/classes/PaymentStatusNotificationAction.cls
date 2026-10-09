public class PaymentStatusNotificationAction {
    public class Request {
        @InvocableVariable
        public Id paymentId;
        @InvocableVariable
        public String paymentStatus;
        @InvocableVariable
        public String notificationBody;
    }

    @InvocableMethod
    public static void sendNotification(List<Request> requests) {
        if (requests == null || requests.isEmpty()) {
            return;
        }
        Set<Id> paymentIds = new Set<Id>();
        for (Request req : requests) {
            if (req.paymentId != null) {
                paymentIds.add(req.paymentId);
            }
        }
        if (paymentIds.isEmpty()) {
            return;
        }
        Map<Id, Payment__c> paymentsById = new Map<Id, Payment__c>(
            [SELECT Id, OwnerId FROM Payment__c WHERE Id IN :paymentIds WITH SECURITY_ENFORCED]
        );
        List<CustomNotificationType> notifTypes = [
            SELECT Id FROM CustomNotificationType WHERE DeveloperName = 'Payment_Status_Update' LIMIT 1
        ];
        if (notifTypes.isEmpty()) {
            return;
        }
        Id notifTypeId = notifTypes[0].Id;
        for (Request req : requests) {
            Payment__c pmt = (req.paymentId != null) ? paymentsById.get(req.paymentId) : null;
            if (pmt == null || pmt.OwnerId == null) {
                continue;
            }
            Messaging.CustomNotification notification = new Messaging.CustomNotification();
            notification.setTitle('Payment Status Update');
            notification.setBody(String.isNotBlank(req.notificationBody) ? req.notificationBody : 'A payment status has changed.');
            notification.setNotificationTypeId(notifTypeId);
            notification.setTargetId(req.paymentId);
            try {
                notification.send(new Set<String>{ pmt.OwnerId });
            } catch (Exception e) {
                System.debug(LoggingLevel.WARN, 'PaymentStatusNotificationAction: notification send failed - ' + e.getMessage());
            }
        }
    }
}