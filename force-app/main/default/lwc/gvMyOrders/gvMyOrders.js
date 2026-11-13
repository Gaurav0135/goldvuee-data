
import { LightningElement } from 'lwc';
import getMyOrders from '@salesforce/apex/GVOrderHistoryController.getMyOrders';
import getMyOrderDetail from '@salesforce/apex/GVOrderHistoryController.getMyOrderDetail';

export default class GvMyOrders extends LightningElement {
    orders = [];
    selectedOrder = null;
    loading = true;
    detailLoading = false;
    errorMessage = '';
    detailError = '';

    connectedCallback() {
        this.loadOrders();
    }

    get hasOrders() {
        return this.orders.length > 0;
    }

    get showEmpty() {
        return !this.loading && !this.errorMessage && !this.hasOrders;
    }

    get showOrderList() {
        return !this.selectedOrder;
    }

    get formattedAddress() {
        if (!this.selectedOrder) return '';

        const d = this.selectedOrder;

        return [
            d.shippingAddress,
            d.shippingCity,
            d.shippingState,
            d.shippingPostalCode,
            d.shippingCountry
        ].filter(Boolean).join(', ');
    }

    formatMoney(value) {
        return new Intl.NumberFormat('en-IN', {
            style: 'currency',
            currency: 'INR',
            minimumFractionDigits: 2
        }).format(Number(value) || 0);
    }

    formatDate(value) {
        if (!value) return 'Date unavailable';

        const date = new Date(value);

        if (Number.isNaN(date.getTime())) {
            return 'Date unavailable';
        }

        return new Intl.DateTimeFormat('en-IN', {
            day: '2-digit',
            month: 'short',
            year: 'numeric',
            timeZone: 'Asia/Kolkata'
        }).format(date);
    }

    decorateOrder(order) {
        return {
            ...order,
            displayTotal: this.formatMoney(order.grandTotal),
            displayDate: this.formatDate(order.orderDate),
            displayStatus: order.orderStatus === 'pending' || !order.orderStatus
                ? 'Processing' : order.orderStatus,
            displayPayment: order.paymentStatus === 'Paid' ? 'Confirmed' :
                order.paymentStatus === 'Failed' ? 'Failed' :
                order.paymentStatus === 'Refunded' ? 'Refunded' : 'Processing'
        };
    }

    getErrorMessage(error) {
        return error?.body?.message ||
            error?.message ||
            'Something went wrong. Please try again.';
    }

    async loadOrders() {
        this.loading = true;
        this.errorMessage = '';

        try {
            const results = await getMyOrders();
            this.orders = (results || []).map(
                order => this.decorateOrder(order)
            );
        } catch (error) {
            this.errorMessage = this.getErrorMessage(error);
            this.orders = [];
        } finally {
            this.loading = false;
        }
    }

    async handleViewDetails(event) {
        const orderId = event.currentTarget.dataset.id;

        if (!orderId || this.detailLoading) return;

        this.detailLoading = true;
        this.detailError = '';

        try {
            const detail = await getMyOrderDetail({ orderId });

            const items = (detail.items || []).map((item, index) => {
                const quantity = Number(item.quantity) || 0;
                const price = Number(item.unitPrice) || 0;
                const discount = Number(item.discountAmount) || 0;

                return {
                    ...item,
                    key: index,
                    displayPrice: this.formatMoney(price),
                    displayTotal: this.formatMoney(
                        quantity * price - discount
                    )
                };
            });

            this.selectedOrder = {
                ...detail,
                order: this.decorateOrder(detail.order),
                items
            };
        } catch (error) {
            this.detailError = this.getErrorMessage(error);
        } finally {
            this.detailLoading = false;
        }
    }

    handleBack() {
        this.selectedOrder = null;
        this.detailError = '';
    }

    handleRefresh() {
        this.selectedOrder = null;
        this.loadOrders();
    }
}
