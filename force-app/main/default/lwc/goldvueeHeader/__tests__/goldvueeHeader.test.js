import { createElement } from '@lwc/engine-dom';
import GoldvueeHeader from 'c/goldvueeHeader';

describe('c-goldvuee-header', () => {
    afterEach(() => {
        // The jsdom instance is shared across test cases in a single file so reset the DOM
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    it('renders the compact brand, navigation and customer actions', () => {
        const element = createElement('c-goldvuee-header', {
            is: GoldvueeHeader
        });

        document.body.appendChild(element);

        expect(element.shadowRoot.querySelector('.gv-logo-name').textContent).toBe('GOLDVUEE');
        expect(element.shadowRoot.querySelectorAll('.gv-desktop-nav a')).toHaveLength(4);
        expect(element.shadowRoot.querySelector('.gv-cart')).not.toBeNull();
        expect(element.shadowRoot.querySelector('.gv-account-button').textContent).toContain('My Account');
        expect(element.shadowRoot.querySelector('.gv-count').textContent).toBe('0');
    });

    it('opens collections and closes menus with Escape', () => {
        const element = createElement('c-goldvuee-header', {
            is: GoldvueeHeader
        });
        document.body.appendChild(element);

        element.shadowRoot.querySelector('.gv-nav-button').click();
        expect(element.shadowRoot.querySelector('.gv-dropdown-menu')).not.toBeNull();

        document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }));
        return Promise.resolve().then(() => {
            expect(element.shadowRoot.querySelector('.gv-dropdown-menu')).toBeNull();
        });
    });

    it('opens the account menu for guest actions', () => {
        const element = createElement('c-goldvuee-header', {
            is: GoldvueeHeader
        });
        document.body.appendChild(element);

        element.shadowRoot.querySelector('.gv-account-button').click();
        return Promise.resolve().then(() => {
            expect(element.shadowRoot.querySelector('.gv-account-menu').textContent).toContain('Sign In');
        });
    });
});