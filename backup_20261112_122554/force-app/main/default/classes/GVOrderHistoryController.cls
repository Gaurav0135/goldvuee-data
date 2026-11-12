
public without sharing class GVOrderHistoryController {

    public class OrderSummary {
        @AuraEnabled public Id orderId;
        @AuraEnabled public String orderNumber;
        @AuraEnabled public Datetime orderDate;
        @AuraEnabled public String orderStatus;
        @AuraEnabled public String paymentStatus;
        @AuraEnabled public Decimal grandTotal;
    }

    public class OrderItemDetail {
        @AuraEnabled public String productName;
        @AuraEnabled public Decimal quantity;
        @AuraEnabled public Decimal unitPrice;
        @AuraEnabled public Decimal discountAmount;
    }

    public class OrderDetail {
        @AuraEnabled public OrderSummary order;
        @AuraEnabled public String shippingAddress;
        @AuraEnabled public String shippingCity;
        @AuraEnabled public String shippingState;
        @AuraEnabled public String shippingPostalCode;
        @AuraEnabled public String shippingCountry;
        @AuraEnabled public List<OrderItemDetail> items;
    }

    private static Id getCustomerContactId() {
        List<User> users = [
            SELECT ContactId
            FROM User
            WHERE Id = :UserInfo.getUserId()
            WITH SYSTEM_MODE
            LIMIT 1
        ];

        if (users.isEmpty() || users[0].ContactId == null) {
            throw new AuraHandledException(
                'Please sign in to view your orders.'
            );
        }

        return users[0].ContactId;
    }

    private static OrderSummary mapOrder(Jewellery_Order__c rec) {
        OrderSummary result = new OrderSummary();

        result.orderId = rec.Id;
        result.orderNumber = rec.Name;
        result.orderDate = rec.Order_Date__c;
        result.orderStatus = rec.Order_Status__c;
        result.paymentStatus = rec.Payment_Status__c;
        result.grandTotal = rec.Grand_Total__c;

        return result;
    }

    @AuraEnabled(cacheable=true)
    public static List<OrderSummary> getMyOrders() {
        Id contactId = getCustomerContactId();

        List<OrderSummary> results = new List<OrderSummary>();

        for (Jewellery_Order__c rec : [
            SELECT
                Id,
                Name,
                Order_Date__c,
                Order_Status__c,
                Payment_Status__c,
                Grand_Total__c
            FROM Jewellery_Order__c
            WHERE Customer__c = :contactId
            WITH SYSTEM_MODE
            ORDER BY Order_Date__c DESC
            LIMIT 100
        ]) {
            results.add(mapOrder(rec));
        }

        return results;
    }

    @AuraEnabled(cacheable=true)
    public static OrderDetail getMyOrderDetail(Id orderId) {
        if (orderId == null) {
            throw new AuraHandledException('Order ID is required.');
        }

        Id contactId = getCustomerContactId();

        List<Jewellery_Order__c> orders = [
            SELECT
                Id,
                Name,
                Order_Date__c,
                Order_Status__c,
                Payment_Status__c,
                Grand_Total__c,
                Shipping_Address__c,
                Shipping_City__c,
                Shipping_State__c,
                Shipping_Postal_Code__c,
                Shipping_Country__c
            FROM Jewellery_Order__c
            WHERE Id = :orderId
            AND Customer__c = :contactId
            WITH SYSTEM_MODE
            LIMIT 1
        ];

        if (orders.isEmpty()) {
            throw new AuraHandledException(
                'Order not found or access denied.'
            );
        }

        Jewellery_Order__c rec = orders[0];

        OrderDetail detail = new OrderDetail();
        detail.order = mapOrder(rec);

        detail.shippingAddress = rec.Shipping_Address__c;
        detail.shippingCity = rec.Shipping_City__c;
        detail.shippingState = rec.Shipping_State__c;
        detail.shippingPostalCode = rec.Shipping_Postal_Code__c;
        detail.shippingCountry = rec.Shipping_Country__c;

        detail.items = new List<OrderItemDetail>();

        for (Jewellery_Order_Item__c item : [
            SELECT
                Jewellery_Product__r.Name,
                Quantity__c,
                Unit_Price__c,
                Discount_Amount__c
            FROM Jewellery_Order_Item__c
            WHERE Jewellery_Order__c = :orderId
            WITH SYSTEM_MODE
            LIMIT 200
        ]) {
            OrderItemDetail line = new OrderItemDetail();

            line.productName =
                item.Jewellery_Product__r == null
                ? 'Jewellery Product'
                : item.Jewellery_Product__r.Name;

            line.quantity = item.Quantity__c;
            line.unitPrice = item.Unit_Price__c;
            line.discountAmount = item.Discount_Amount__c;

            detail.items.add(line);
        }

        return detail;
    }
}