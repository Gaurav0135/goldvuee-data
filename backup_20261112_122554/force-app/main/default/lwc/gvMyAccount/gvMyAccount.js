
import { LightningElement } from 'lwc';
import getMyAccount from '@salesforce/apex/GVMyAccountController.getMyAccount';
import basePath from '@salesforce/community/basePath';

export default class GvMyAccount extends LightningElement {
    account = null;
    loading = true;
    errorMessage = '';

    connectedCallback() {
        this.loadAccount();
    }

    get siteRoot() {
        return '/' + basePath.split('/').filter(Boolean)
            .filter(segment => segment !== 's')
            .join('/');
    }

    get ordersUrl() {
        return `${this.siteRoot}/my-orders`;
    }

    get collectionsUrl() {
        return `${this.siteRoot}/collections`;
    }

    get cartUrl() {
        return `${this.siteRoot}/shopping-cart`;
    }

    get loginUrl() {
        return `${this.siteRoot}/login`;
    }

    get isLoggedIn() {
        return this.account && this.account.loggedIn;
    }

    get showGuest() {
        return !this.loading && !this.errorMessage
            && !this.isLoggedIn;
    }

    get customerName() {
        return this.account?.firstName || 'Customer';
    }

    get fullName() {
        return this.account?.fullName || 'Not provided';
    }

    get customerEmail() {
        return this.account?.email || 'Not provided';
    }

    get customerInitial() {
        return this.customerName.charAt(0).toUpperCase();
    }

    async loadAccount() {
        this.loading = true;
        this.errorMessage = '';

        try {
            this.account = await getMyAccount();
        } catch (error) {
            this.errorMessage = error?.body?.message ||
                'Unable to load your account details.';
        } finally {
            this.loading = false;
        }
    }

    handleRefresh() {
        this.loadAccount();
    }
}
