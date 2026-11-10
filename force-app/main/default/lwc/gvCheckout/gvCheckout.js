
import { LightningElement } from 'lwc';

import getCart from '@salesforce/apex/GVCartController.getCart';
import placeOrder from '@salesforce/apex/GVCheckoutController.placeOrder';

import communityBasePath from '@salesforce/community/basePath';

export default class GvCheckout extends LightningElement {

    // CART
    cartId = null;
    cartItems = [];
    itemCount = 0;
    subtotal = 0;

    // STATES
    isLoading = true;
    isPlacingOrder = false;
    orderPlaced = false;

    // MESSAGES
    errorMessage = '';
    successMessage = '';

    // ORDER CONFIRMATION
    orderNumber = '';
    orderGrandTotal = 0;
    orderStatus = '';
    paymentStatus = '';

    // SHIPPING
    shippingAddress = '';
    shippingCity = '';
    shippingState = '';
    shippingPostalCode = '';
    shippingCountry = 'India';

    // ==========================================
    // INITIALIZE
    // ==========================================

    connectedCallback() {
        this.loadCheckout();
    }

    // ==========================================
    // LOAD CUSTOMER CART
    // ==========================================

    async loadCheckout() {

        this.isLoading = true;
        this.errorMessage = '';

        try {

            const response = await getCart();

            this.cartId =
                response?.cartId || null;

            this.itemCount =
                Number(response?.itemCount || 0);

            this.subtotal =
                Number(response?.totalAmount || 0);

            this.cartItems = (
                response?.items || []
            ).map(item => ({
                id: item.Id,

                name:
                    item.Jewellery_Product__r?.Name ||
                    'GoldVuee Jewellery',

                quantity:
                    Number(item.Quantity__c || 0),

                formattedLineTotal:
                    this.formatCurrency(
                        item.Line_Total__c || 0
                    )
            }));

        } catch (error) {

            this.errorMessage =
                this.getErrorMessage(error);

            console.error(
                '[GoldVuee] Cart loading failed',
                error
            );

        } finally {
            this.isLoading = false;
        }
    }

    // ==========================================
    // HANDLE INPUT
    // ==========================================

    handleInputChange(event) {

        if (
            this.isPlacingOrder ||
            this.orderPlaced
        ) {
            return;
        }

        const field = event.target.name;

        const allowed = [
            'shippingAddress',
            'shippingCity',
            'shippingState',
            'shippingPostalCode',
            'shippingCountry'
        ];

        if (allowed.includes(field)) {
            this[field] = event.target.value;
        }

        this.errorMessage = '';
    }

    // ==========================================
    // VALIDATE SHIPPING
    // ==========================================

    validateShipping() {

        const values = [
            this.shippingAddress,
            this.shippingCity,
            this.shippingState,
            this.shippingPostalCode,
            this.shippingCountry
        ];

        if (
            values.some(
                value => !String(value || '').trim()
            )
        ) {
            this.errorMessage =
                'Please complete all delivery fields.';

            return false;
        }

        if (
            this.shippingCountry.trim().toLowerCase()
                !== 'india' ||
            !/^[1-9][0-9]{5}$/.test(
                this.shippingPostalCode.trim()
            )
        ) {
            this.errorMessage =
                'Please enter a valid Indian address and six-digit PIN code.';

            return false;
        }

        return true;
    }

    // ==========================================
    // PLACE CASH ON DELIVERY ORDER
    // ==========================================

    async handlePlaceOrder() {

        if (
            this.isLoading ||
            this.isPlacingOrder ||
            this.orderPlaced
        ) {
            return;
        }

        this.errorMessage = '';

        if (
            !this.cartId ||
            !this.hasItems
        ) {
            this.errorMessage =
                'Your shopping bag is empty.';

            return;
        }

        if (!this.validateShipping()) {
            return;
        }

        this.isPlacingOrder = true;

        try {

            const result = await placeOrder({
                shippingAddress:
                    this.shippingAddress.trim(),

                shippingCity:
                    this.shippingCity.trim(),

                shippingState:
                    this.shippingState.trim(),

                shippingPostalCode:
                    this.shippingPostalCode.trim(),

                shippingCountry:
                    this.shippingCountry.trim()
            });

            if (
                !result?.orderId ||
                result.orderStatus !== 'Confirmed'
            ) {
                throw new Error(
                    'Salesforce did not confirm the COD order.'
                );
            }

            this.orderPlaced = true;

            this.orderNumber =
                result.orderNumber || '';

            this.orderGrandTotal =
                Number(result.grandTotal || 0);

            this.orderStatus =
                result.orderStatus;

            this.paymentStatus =
                result.paymentStatus || 'Pending';

            this.successMessage =
                result.message ||
                'Your Cash on Delivery order is confirmed.';

            // CLEAR LOCAL CART AFTER SUCCESS
            this.cartId = null;
            this.cartItems = [];
            this.itemCount = 0;
            this.subtotal = 0;

        } catch (error) {

            this.errorMessage =
                this.getErrorMessage(error);

            console.error(
                '[GoldVuee] COD checkout error',
                error
            );

        } finally {

            this.isPlacingOrder = false;
        }
    }

    // ==========================================
    // BACK TO CART
    // ==========================================

    handleBackToCart() {

        window.location.assign(
            `${communityBasePath}/shopping-cart`
        );
    }

    // ==========================================
    // GETTERS
    // ==========================================

    get hasItems() {
        return this.cartItems.length > 0;
    }

    get formattedSubtotal() {
        return this.formatCurrency(
            this.subtotal
        );
    }

    get formattedOrderGrandTotal() {
        return this.formatCurrency(
            this.orderGrandTotal
        );
    }

    get isCheckoutDisabled() {
        return (
            this.isLoading ||
            this.isPlacingOrder ||
            this.orderPlaced ||
            !this.hasItems
        );
    }

    get placeOrderButtonLabel() {

        return this.isPlacingOrder
            ? 'Confirming COD Order...'
            : 'Place Order - Cash on Delivery';
    }

    // ==========================================
    // CURRENCY HELPER
    // ==========================================

    formatCurrency(value) {

        return new Intl.NumberFormat(
            'en-IN',
            {
                style: 'currency',
                currency: 'INR',
                minimumFractionDigits: 2,
                maximumFractionDigits: 2
            }
        ).format(Number(value || 0));
    }

    // ==========================================
    // ERROR HELPER
    // ==========================================

    getErrorMessage(error) {

        if (Array.isArray(error?.body)) {

            return error.body
                .map(item => item?.message)
                .filter(Boolean)
                .join(', ') || 'Checkout failed.';
        }

        return (
            error?.body?.message ||
            error?.message ||
            'Unable to complete checkout.'
        );
    }
}
