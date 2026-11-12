/**
 * GoldVuee: release an abandoned, uninitialized, expired online checkout.
 *
 * Not exposed to LWC. Call only after the caller has established
 * the authenticated customer's Contact and locked their active cart.
 * NEVER cancels a payment with a Razorpay order ID or transaction ID.
 */
public without sharing class GVAbandonedCheckoutService {
    public class RecoveryException extends Exception {}

    public static Boolean recoverExpiredCheckout(Id cartId, Id contactId) {
        if (cartId == null || contactId == null) {
            throw new RecoveryException('Customer and shopping bag are required.');
        }

        List<Jewellery_Order__c> orders = [
            SELECT Id, Customer__c, Order_Status__c, Payment_Status__c
            FROM Jewellery_Order__c
            WHERE Shopping_Cart__c = :cartId
              AND Order_Status__c = 'pending'
            WITH SYSTEM_MODE
            LIMIT 2
            FOR UPDATE
        ];
        if (orders.isEmpty()) return false;
        if (orders.size() != 1) {
            throw new RecoveryException('Multiple pending orders need manual reconciliation.');
        }
        Jewellery_Order__c oldOrder = orders[0];
        if (oldOrder.Customer__c != contactId ||
            oldOrder.Payment_Status__c != 'Pending') {
            throw new RecoveryException('Existing checkout requires account review.');
        }

        List<Payment__c> payments = [
            SELECT Id, Payment_Status__c, Razorpay_Order_ID__c, Transaction_ID__c
            FROM Payment__c
            WHERE Jewellery_Order__c = :oldOrder.Id
            WITH SYSTEM_MODE
            LIMIT 2
            FOR UPDATE
        ];
        if (payments.size() != 1 || payments[0].Payment_Status__c != 'Pending') {
            throw new RecoveryException('Existing payment needs reconciliation.');
        }
        if (!String.isBlank(payments[0].Razorpay_Order_ID__c) ||
            !String.isBlank(payments[0].Transaction_ID__c)) {
            // A gateway order or transaction might have succeeded: do not reset.
            return false;
        }

        List<Stock_Reservation__c> reservations = [
            SELECT Id, Reservation_Status__c, Expires_At__c
            FROM Stock_Reservation__c
            WHERE Jewellery_Order__c = :oldOrder.Id
            WITH SYSTEM_MODE
            FOR UPDATE
        ];
        if (reservations.isEmpty()) {
            throw new RecoveryException('Missing inventory reservation needs review.');
        }
        Boolean foundExpiredActive = false;
        for (Stock_Reservation__c reservation : reservations) {
            if (reservation.Reservation_Status__c == 'Committed') {
                throw new RecoveryException('Committed stock must not be released.');
            }
            if (reservation.Reservation_Status__c == 'Active') {
                if (reservation.Expires_At__c == null ||
                    reservation.Expires_At__c > System.now()) {
                    // Keep the still-live checkout intact.
                    return false;
                }
                foundExpiredActive = true;
            } else if (reservation.Reservation_Status__c != 'Expired' &&
                       reservation.Reservation_Status__c != 'Released') {
                throw new RecoveryException('Unknown reservation status needs review.');
            }
        }
        if (!foundExpiredActive) return false;

        // Never guess Salesforce picklist values. If this org does not support
        // the required cancellation statuses, fail with no committed changes.
        String orderCancelledStatus = chooseStatus(
            Jewellery_Order__c.Order_Status__c.getDescribe(),
            new List<String>{'Cancelled','Canceled','Abandoned'}
        );
        String paymentCancelledStatus = chooseStatus(
            Payment__c.Payment_Status__c.getDescribe(),
            new List<String>{'Cancelled','Canceled','Failed'}
        );
        if (String.isBlank(orderCancelledStatus) ||
            String.isBlank(paymentCancelledStatus)) {
            throw new RecoveryException(
                'Cancellation statuses are not configured in this org. ' +
                'Review Order Status and Payment Status picklist values.'
            );
        }

        // releaseReservation updates Jewellery_Product__c.Reserved_Quantity__c
        // AND the reservation status atomically, without subtracting physical stock.
        for (Stock_Reservation__c reservation : reservations) {
            if (reservation.Reservation_Status__c == 'Active') {
                GVInventoryService.releaseReservation(reservation.Id);
            }
        }

        Database.update(
            new Payment__c(
                Id = payments[0].Id,
                Payment_Status__c = paymentCancelledStatus
            ), true, AccessLevel.SYSTEM_MODE
        );
        Database.update(
            new Jewellery_Order__c(
                Id = oldOrder.Id,
                Order_Status__c = orderCancelledStatus
            ), true, AccessLevel.SYSTEM_MODE
        );
        return true;
    }

    private static String chooseStatus(
        Schema.DescribeFieldResult fieldDesc,
        List<String> preferredValues
    ) {
        Set<String> available = new Set<String>();
        for (Schema.PicklistEntry entry : fieldDesc.getPicklistValues()) {
            if (entry.isActive()) available.add(entry.getValue());
        }
        for (String preferred : preferredValues) {
            if (available.contains(preferred)) return preferred;
        }
        return null;
    }
}