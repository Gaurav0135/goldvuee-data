
import { LightningElement, api } from 'lwc';

import razorpayKey from
    '@salesforce/label/c.GoldVuee_Razorpay_Test_Key_ID';

import prepareOnlineOrder from
    '@salesforce/apex/GVOnlineCheckoutController.prepareOnlineOrder';

import initiatePayment from
    '@salesforce/apex/GVPaymentController.initiatePayment';

import verifyPayment from
    '@salesforce/apex/GVPaymentVerificationController.verifyPayment';

const RAZORPAY_HOST_URL =
    'https://goldvuee-dev-ed--c.develop.vf.force.com/apex/GVRazorpayHost';

export default class GoldvueeRazorpayCheckout
    extends LightningElement {

    @api amount = 0;

    @api shippingAddress = '';
    @api shippingCity = '';
    @api shippingState = '';
    @api shippingPostalCode = '';
    @api shippingCountry = 'India';

    isWorking = false;
    completed = false;

    errorMessage = '';
    statusMessage = '';

    pendingOrder = null;
    gatewayOrder = null;

    paymentWindow = null;
    sessionNonce = null;

    awaitingConfirmation = false;
    hostReady = false;
    paymentSent = false;

    connectedCallback() {
        window.addEventListener(
            'message',
            this.handleHostMessage
        );
    }

    disconnectedCallback() {
        window.removeEventListener(
            'message',
            this.handleHostMessage
        );
    }

    get isButtonDisabled() {
        return this.isWorking || this.completed;
    }

    get buttonLabel() {
        if (this.completed) {
            return 'Payment Confirmation Pending';
        }

        if (this.isWorking) {
            return 'Processing Secure Payment...';
        }

        return 'Pay Securely with Razorpay';
    }

    get hostOrigin() {
        return new URL(RAZORPAY_HOST_URL).origin;
    }

    createNonce() {
        const bytes = new Uint8Array(16);

        window.crypto.getRandomValues(bytes);

        return Array.from(bytes)
            .map(value =>
                value.toString(16).padStart(2, '0')
            )
            .join('');
    }

    validateShipping() {
        const fields = [
            this.shippingAddress,
            this.shippingCity,
            this.shippingState,
            this.shippingPostalCode,
            this.shippingCountry
        ];

        if (
            fields.some(
                value => !String(value || '').trim()
            )
        ) {
            throw new Error(
                'Please complete all delivery information.'
            );
        }

        if (
            String(this.shippingCountry)
                .trim()
                .toLowerCase() !== 'india' ||
            !/^[1-9][0-9]{5}$/.test(
                String(this.shippingPostalCode).trim()
            )
        ) {
            throw new Error(
                'Enter a valid Indian delivery address and PIN code.'
            );
        }
    }

    handlePay = async () => {
        if (this.isButtonDisabled) {
            return;
        }

        this.errorMessage = '';
        this.statusMessage = '';

        try {
            this.validateShipping();

            if (
                !razorpayKey ||
                !/^rzp_test_[A-Za-z0-9]+$/.test(
                    razorpayKey
                )
            ) {
                throw new Error(
                    'Razorpay Test Key ID is not configured.'
                );
            }

            // Opening the window synchronously from the
            // user's click helps avoid popup blocking.
            this.sessionNonce = this.createNonce();

            const url = new URL(
                RAZORPAY_HOST_URL
            );

            url.searchParams.set(
                'origin',
                window.location.origin
            );

            url.searchParams.set(
                'nonce',
                this.sessionNonce
            );

            this.hostReady = false;
            this.paymentSent = false;

            this.paymentWindow = window.open(
                url.toString(),
                '_blank',
                'width=520,height=760'
            );

            if (!this.paymentWindow) {
                throw new Error(
                    'Please allow popups for GoldVuee checkout.'
                );
            }

            this.isWorking = true;

            // All trusted order creation remains in Apex.
            if (!this.pendingOrder) {
                this.statusMessage =
                    'Preparing your GoldVuee order...';

                this.pendingOrder =
                    await prepareOnlineOrder({
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
            }

            if (!this.pendingOrder?.paymentId) {
                throw new Error(
                    'Unable to prepare your Salesforce payment.'
                );
            }

            if (!this.gatewayOrder) {
                this.statusMessage =
                    'Creating your Razorpay Test order...';

                this.gatewayOrder =
                    await initiatePayment({
                        paymentId:
                            this.pendingOrder.paymentId
                    });
            }

            if (
                !this.gatewayOrder?.razorpayOrderId ||
                !/^order_[A-Za-z0-9]+$/.test(
                    this.gatewayOrder.razorpayOrderId
                ) ||
                !Number.isSafeInteger(
                    Number(
                        this.gatewayOrder.amountPaise
                    )
                ) ||
                Number(
                    this.gatewayOrder.amountPaise
                ) < 100 ||
                this.gatewayOrder.currencyCode !== 'INR'
            ) {
                throw new Error(
                    'Salesforce returned invalid Razorpay order details.'
                );
            }

            this.statusMessage =
                'Waiting for Razorpay payment window...';

            this.sendPaymentToHost();

        } catch (error) {
            this.errorMessage = this.readError(error);
            this.statusMessage = '';
            this.isWorking = false;

            if (
                this.paymentWindow &&
                !this.paymentWindow.closed
            ) {
                this.paymentWindow.close();
            }
        }
    };

    sendPaymentToHost() {
        if (
            !this.hostReady ||
            !this.gatewayOrder ||
            !this.paymentWindow ||
            this.paymentWindow.closed ||
            this.paymentSent
        ) {
            return;
        }

        this.paymentSent = true;

        this.paymentWindow.postMessage(
            {
                source: 'GOLDVUEE_CHECKOUT',
                type: 'START_PAYMENT',
                nonce: this.sessionNonce,
                data: {
                    key: razorpayKey,
                    orderId:
                        this.gatewayOrder.razorpayOrderId,
                    amount: Number(
                        this.gatewayOrder.amountPaise
                    )
                }
            },
            this.hostOrigin
        );

        this.statusMessage =
            'Complete the payment in the Razorpay window.';
    }

    handleHostMessage = async event => {
        if (
            !this.paymentWindow ||
            event.source !== this.paymentWindow ||
            event.origin !== this.hostOrigin
        ) {
            return;
        }

        const message = event.data;

        if (
            !message ||
            message.source !==
                'GOLDVUEE_RAZORPAY_HOST' ||
            message.nonce !== this.sessionNonce
        ) {
            return;
        }

        if (message.type === 'READY') {
            this.hostReady = true;
            this.sendPaymentToHost();
            return;
        }

        if (message.type === 'PAYMENT_SUCCESS') {
            if (
                this.awaitingConfirmation ||
                this.completed
            ) {
                return;
            }

            this.awaitingConfirmation = true;

            await this.handlePaymentSuccess(
                message.data
            );

            return;
        }

        if (
            message.type === 'PAYMENT_DISMISSED' ||
            message.type === 'PAYMENT_FAILED'
        ) {
            if (!this.awaitingConfirmation) {
                this.isWorking = false;
                this.statusMessage =
                    'Payment was not completed. You can retry.';

                this.errorMessage =
                    message.type === 'PAYMENT_FAILED'
                        ? 'Razorpay reported a failed payment.'
                        : '';
            }

            return;
        }

        if (message.type === 'ERROR') {
            this.errorMessage =
                message.data?.message ||
                'Unable to open Razorpay.';

            this.statusMessage = '';
            this.isWorking = false;
        }
    };

    async handlePaymentSuccess(data) {
        this.statusMessage =
            'Verifying captured payment with Salesforce...';

        this.errorMessage = '';

        try {
            if (
                !this.pendingOrder?.paymentId ||
                !this.gatewayOrder ||
                !/^pay_[A-Za-z0-9]+$/.test(
                    data?.paymentId || ''
                ) ||
                data?.orderId !==
                    this.gatewayOrder.razorpayOrderId ||
                !/^[a-fA-F0-9]{64}$/.test(
                    data?.signature || ''
                )
            ) {
                throw new Error(
                    'Invalid Razorpay checkout response.'
                );
            }

            const result = await verifyPayment({
                paymentId: this.pendingOrder.paymentId,
                razorpayPaymentId: data.paymentId
            });

            if (
                !result?.success ||
                result.orderStatus !== 'Confirmed' ||
                result.paymentStatus !== 'Paid'
            ) {
                throw new Error(
                    'Salesforce did not confirm the payment.'
                );
            }

            this.completed = true;
            this.statusMessage =
                'Razorpay payment verified successfully.';

            this.dispatchEvent(
                new CustomEvent('paymentsuccess', {
                    detail: {
                        ...result,
                        grandTotal:
                            this.pendingOrder.grandTotal ||
                            this.amount
                    }
                })
            );

            if (
                this.paymentWindow &&
                !this.paymentWindow.closed
            ) {
                this.paymentWindow.close();
            }

        } catch (error) {
            this.errorMessage =
                'Payment verification is incomplete. ' +
                'Check your order before attempting another payment. ' +
                this.readError(error);

            this.completed = true;
            this.statusMessage = '';

        } finally {
            this.awaitingConfirmation = false;
            this.isWorking = false;
        }
    }

    readError(error) {
        return (
            error?.body?.message ||
            error?.message ||
            'Unable to complete Razorpay checkout.'
        );
    }
}
