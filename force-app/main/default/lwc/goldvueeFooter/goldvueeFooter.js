
import { LightningElement } from 'lwc';
import isGuest from '@salesforce/user/isGuest';
import basePath from '@salesforce/community/basePath';

export default class GoldvueeFooter extends LightningElement {

    get isLoggedIn() {
        return !isGuest;
    }

    get currentYear() {
        return new Date().getFullYear();
    }

    get siteRoot() {
        return basePath.endsWith('/s')
            ? basePath.slice(0, -2)
            : basePath.replace(/\/$/, '');
    }

    get homeUrl() {
        return `${basePath}/`;
    }

    get collectionsUrl() {
        return `${basePath}/collections`;
    }

    get newArrivalsUrl() {
        return `${basePath}/new-arrivals`;
    }

    get storyUrl() {
        return `${basePath}/our-story`;
    }

    get contactUrl() {
        return `${basePath}/contact`;
    }

    get cartUrl() {
        return `${basePath}/cart`;
    }

    get accountUrl() {
        return `${basePath}/my-account`;
    }

    get loginUrl() {
        return `${this.siteRoot}/login`;
    }
}
