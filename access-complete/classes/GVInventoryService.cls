public without sharing class GVInventoryService {

    public class InventoryException extends Exception {}

    // ==================================================
    // 1. RESERVE STOCK
    // ==================================================
    // Reserve stock during checkout.
    // Physical stock remains unchanged.
    // Reservation expires after 15 minutes.
    // ==================================================

    public static Id reserveStock(
        Id productId,
        Decimal quantity,
        Id orderId
    ) {
        if (
            productId == null ||
            quantity == null ||
            quantity <= 0 ||
            quantity != quantity.setScale(0)
        ) {
            throw new InventoryException(
                'Invalid product or quantity.'
            );
        }

        Savepoint sp = Database.setSavepoint();

        try {
            List<Jewellery_Product__c> products = [
                SELECT
                    Id,
                    Name,
                    Active__c,
                    Stock_Quantity__c,
                    Reserved_Quantity__c
                FROM Jewellery_Product__c
                WHERE Id = :productId
                FOR UPDATE
            ];

            if (products.isEmpty()) {
                throw new InventoryException(
                    'Product not found.'
                );
            }

            Jewellery_Product__c product = products[0];

            Decimal stock =
                product.Stock_Quantity__c == null
                ? 0
                : product.Stock_Quantity__c;

            Decimal reserved =
                product.Reserved_Quantity__c == null
                ? 0
                : product.Reserved_Quantity__c;

            Decimal available = stock - reserved;

            if (product.Active__c != true) {
                throw new InventoryException(
                    'Product is inactive.'
                );
            }

            if (available < quantity) {
                throw new InventoryException(
                    'Insufficient stock for ' + product.Name
                );
            }

            if (orderId != null) {
                List<Stock_Reservation__c> existingReservations = [
                    SELECT Id, Reservation_Status__c, Expires_At__c
                    FROM Stock_Reservation__c
                    WHERE Jewellery_Product__c = :productId
                    AND Jewellery_Order__c = :orderId
                    AND Reservation_Status__c = 'Active'
                    WITH SYSTEM_MODE
                    LIMIT 2
                    FOR UPDATE
                ];

                if (existingReservations.size() > 1) {
                    throw new InventoryException(
                        'Multiple active reservations exist for this order.'
                    );
                }

                if (!existingReservations.isEmpty()) {
                    Stock_Reservation__c existingReservation =
                        existingReservations[0];

                    if (
                        existingReservation.Expires_At__c == null ||
                        existingReservation.Expires_At__c > System.now()
                    ) {
                        return existingReservation.Id;
                    }

                    throw new InventoryException(
                        'An expired reservation must be released before renewal.'
                    );
                }
            }

            // Increase reserved quantity.
            product.Reserved_Quantity__c =
                reserved + quantity;

            Database.update(
                product,
                true,
                AccessLevel.SYSTEM_MODE
            );

            // Create reservation record.
            Stock_Reservation__c reservation =
                new Stock_Reservation__c(
                    Jewellery_Product__c = productId,
                    Jewellery_Order__c = orderId,
                    Reserved_Quantity__c = quantity,
                    Reservation_Status__c = 'Active',
                    Reserved_At__c = System.now(),
                    Expires_At__c =
                        System.now().addMinutes(15),
                    Reservation_Reason__c = 'Checkout'
                );

            Database.insert(
                reservation,
                true,
                AccessLevel.SYSTEM_MODE
            );

            return reservation.Id;

        } catch (Exception e) {
            Database.rollback(sp);
            throw e;
        }
    }


    // ==================================================
    // 2. COMMIT RESERVATION
    // ==================================================
    // Called after verified payment success or
    // an approved COD order.
    //
    // Reduces physical stock and reserved stock.
    // Creates Inventory Movement history.
    // Prevents duplicate deductions.
    // ==================================================

    public static void commitReservation(
        Id reservationId
    ) {
        if (reservationId == null) {
            throw new InventoryException(
                'Reservation ID is required.'
            );
        }

        Savepoint sp = Database.setSavepoint();

        try {
            List<Stock_Reservation__c> reservations = [
                SELECT
                    Id,
                    Jewellery_Product__c,
                    Jewellery_Order__c,
                    Reserved_Quantity__c,
                    Reservation_Status__c,
                    Expires_At__c
                FROM Stock_Reservation__c
                WHERE Id = :reservationId
                WITH SYSTEM_MODE
                FOR UPDATE
            ];

            if (reservations.isEmpty()) {
                throw new InventoryException(
                    'Reservation not found.'
                );
            }

            Stock_Reservation__c reservation =
                reservations[0];

            // Prevent duplicate stock deductions.
            if (
                reservation.Reservation_Status__c ==
                'Committed'
            ) {
                return;
            }

            if (
                reservation.Reservation_Status__c !=
                'Active'
            ) {
                throw new InventoryException(
                    'Reservation is not active.'
                );
            }

            if (
                reservation.Expires_At__c != null &&
                reservation.Expires_At__c <= System.now()
            ) {
                throw new InventoryException(
                    'Reservation has expired.'
                );
            }

            Decimal qty =
                reservation.Reserved_Quantity__c;

            if (
                qty == null ||
                qty <= 0 ||
                qty != qty.setScale(0)
            ) {
                throw new InventoryException(
                    'Invalid reserved quantity.'
                );
            }

            List<Jewellery_Product__c> products = [
                SELECT
                    Id,
                    Name,
                    Stock_Quantity__c,
                    Reserved_Quantity__c
                FROM Jewellery_Product__c
                WHERE Id =
                    :reservation.Jewellery_Product__c
                    WITH SYSTEM_MODE
                FOR UPDATE
            ];

            if (products.isEmpty()) {
                throw new InventoryException(
                    'Product not found.'
                );
            }

            Jewellery_Product__c product = products[0];

            Decimal stock =
                product.Stock_Quantity__c == null
                ? 0
                : product.Stock_Quantity__c;

            Decimal reserved =
                product.Reserved_Quantity__c == null
                ? 0
                : product.Reserved_Quantity__c;

            if (
                stock < qty ||
                reserved < qty
            ) {
                throw new InventoryException(
                    'Inventory quantities are inconsistent.'
                );
            }

            Decimal newStock = stock - qty;

            // Deduct committed inventory.
            product.Stock_Quantity__c = newStock;
            product.Reserved_Quantity__c =
                reserved - qty;

            Database.update(
                product,
                true,
                AccessLevel.SYSTEM_MODE
            );

            // Mark reservation committed.
            reservation.Reservation_Status__c =
                'Committed';

            Database.update(
                reservation,
                true,
                AccessLevel.SYSTEM_MODE
            );

            // Record inventory movement.
            Inventory_Movement__c movement =
                new Inventory_Movement__c(
                    Jewellery_Product__c =
                        product.Id,
                    Jewellery_Order__c =
                        reservation.Jewellery_Order__c,
                    Movement_Type__c = 'Sale',
                    Quantity__c = qty,
                    Stock_Before__c = stock,
                    Stock_After__c = newStock,
                    Movement_Date__c = System.now(),
                    Reason__c =
                        'Stock committed for reservation '
                        + String.valueOf(reservation.Id)
                );

            Database.insert(
                movement,
                true,
                AccessLevel.SYSTEM_MODE
            );

        } catch (Exception e) {
            Database.rollback(sp);
            throw e;
        }
    }


    // ==================================================
    // 3. RELEASE RESERVATION
    // ==================================================
    // Called when payment fails, checkout is
    // cancelled, or reservation expires.
    //
    // Physical stock remains unchanged.
    // Reserved quantity is released.
    // Prevents duplicate releases.
    // ==================================================

    public static void releaseReservation(
        Id reservationId
    ) {
        if (reservationId == null) {
            throw new InventoryException(
                'Reservation ID is required.'
            );
        }

        Savepoint sp = Database.setSavepoint();

        try {
            List<Stock_Reservation__c> reservations = [
                SELECT
                    Id,
                    Jewellery_Product__c,
                    Reserved_Quantity__c,
                    Reservation_Status__c,
                    Expires_At__c
                FROM Stock_Reservation__c
                WHERE Id = :reservationId
                WITH SYSTEM_MODE
                FOR UPDATE
            ];

            if (reservations.isEmpty()) {
                throw new InventoryException(
                    'Reservation not found.'
                );
            }

            Stock_Reservation__c reservation =
                reservations[0];

            // Already released or expired.
            if (
                reservation.Reservation_Status__c ==
                    'Released' ||
                reservation.Reservation_Status__c ==
                    'Expired'
            ) {
                return;
            }

            // Committed reservations must not be released.
            if (
                reservation.Reservation_Status__c !=
                'Active'
            ) {
                throw new InventoryException(
                    'Only active reservations can be released.'
                );
            }

            Decimal qty =
                reservation.Reserved_Quantity__c;

            if (
                qty == null ||
                qty <= 0 ||
                qty != qty.setScale(0)
            ) {
                throw new InventoryException(
                    'Invalid reserved quantity.'
                );
            }

            List<Jewellery_Product__c> products = [
                SELECT
                    Id,
                    Reserved_Quantity__c
                FROM Jewellery_Product__c
                WHERE Id =
                    :reservation.Jewellery_Product__c
                FOR UPDATE
            ];

            if (products.isEmpty()) {
                throw new InventoryException(
                    'Product not found.'
                );
            }

            Jewellery_Product__c product = products[0];

            Decimal reserved =
                product.Reserved_Quantity__c == null
                ? 0
                : product.Reserved_Quantity__c;

            if (reserved < qty) {
                throw new InventoryException(
                    'Reserved stock is inconsistent.'
                );
            }

            // Release held quantity.
            product.Reserved_Quantity__c =
                reserved - qty;

            Database.update(
                product,
                true,
                AccessLevel.SYSTEM_MODE
            );

            Boolean expired =
                reservation.Expires_At__c != null &&
                reservation.Expires_At__c <= System.now();

            reservation.Reservation_Status__c =
                expired ? 'Expired' : 'Released';

            reservation.Released_At__c = System.now();

            Database.update(
                reservation,
                true,
                AccessLevel.SYSTEM_MODE
            );

        } catch (Exception e) {
            Database.rollback(sp);
            throw e;
        }
    }
}