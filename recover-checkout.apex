Id cartId = 'a03jV00000GXF77QAH';
Id contactId = '003jV00000GPEjJQAX';

Boolean recovered =
    GVAbandonedCheckoutService.recoverExpiredCheckout(
        cartId,
        contactId
    );

System.debug('GOLDVUEE_RECOVERED=' + recovered);
