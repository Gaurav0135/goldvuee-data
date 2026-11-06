(() => {
  const routes = { home: '/', collections: '/collections', newArrivals: '/new-arrivals', story: '/our-story', contact: '/contact', wishlist: '/wishlist', bag: '/bag', account: '/my-account', orders: '/my-orders', login: '/login', register: '/register' };
  const collections = ['Rings', 'Necklaces', 'Earrings', 'Bracelets', 'Bangles', 'All Jewellery'];
  const state = { mobile: false, collections: false, account: false, guest: true, wishlist: 0, bag: 0, query: '', message: '' };
  const app = document.querySelector('#app');
  const icon = (value) => `<span class="gv-action-icon" aria-hidden="true">${value}</span>`;
  const link = (label, route) => `<a href="${routes[route]}" data-nav>${label}</a>`;
  function render() {
    app.innerHTML = `<header class="gv-header">
      <div class="gv-shell">
        <a class="gv-brand" href="${routes.home}" data-nav aria-label="GoldVuee home"><span class="gv-mark" aria-hidden="true">GV</span><span class="gv-brand-text"><span class="gv-brand-name">GoldVuee</span><span class="gv-brand-subtitle">Fine Jewellery</span></span></a>
        <form class="gv-search" role="search"><label class="gv-visually-hidden" for="gv-search-input">Search jewellery</label><span class="gv-search-icon" aria-hidden="true">⌕</span><input id="gv-search-input" type="search" placeholder="Search jewellery" autocomplete="off" value="${escapeHtml(state.query)}"><button class="gv-search-submit" type="submit">Search</button></form>
        <nav class="gv-desktop-nav" aria-label="Main navigation">${link('Home', 'home')}<div class="gv-dropdown"><button class="gv-nav-button" type="button" aria-expanded="${state.collections}">Collections⌄</button>${state.collections ? collectionMenu() : ''}</div>${link('New Arrivals', 'newArrivals')}${link('Our Story', 'story')}${link('Contact', 'contact')}</nav>
        <div class="gv-actions"><a class="gv-action" href="${routes.wishlist}" data-nav>${icon('♡')}<span class="gv-action-label">Wishlist</span><span class="gv-count">${state.wishlist}</span></a><a class="gv-action" href="${routes.bag}" data-nav>${icon('□')}<span class="gv-action-label">Bag</span><span class="gv-count">${state.bag}</span></a><div class="gv-account"><button class="gv-account-button" type="button" aria-expanded="${state.account}">${icon('◎')}<span class="gv-action-label">My Account</span></button>${state.account ? accountMenu() : ''}</div><button class="gv-menu-button" type="button" aria-label="Open menu" aria-expanded="${state.mobile}">☰</button></div>
      </div>${state.message ? `<p class="gv-search-message" role="status">${escapeHtml(state.message)}</p>` : ''}${state.mobile ? mobileMenu() : ''}</header>`;
    bind();
  }
  function collectionMenu() { return `<div class="gv-dropdown-menu" role="menu">${collections.map((item) => `<a href="${routes.collections}/${item.toLowerCase().replaceAll(' ', '-')}" data-nav role="menuitem">${item}</a>`).join('')}</div>`; }
  function accountMenu() { return `<div class="gv-account-menu" role="menu">${state.guest ? `${link('Sign In', 'login')}${link('Create Account', 'register')}` : `${link('Profile', 'account')}${link('My Orders', 'orders')}<button type="button" data-logout>Logout</button>`}</div>`; }
  function mobileMenu() { return `<div class="gv-mobile-menu"><div class="gv-mobile-links">${link('Home', 'home')}<button type="button" data-collections>Collections⌄</button>${state.collections ? `<div class="gv-mobile-collections">${collections.map((item) => `<a href="${routes.collections}/${item.toLowerCase().replaceAll(' ', '-')}" data-nav>${item}</a>`).join('')}</div>` : ''}${link('New Arrivals', 'newArrivals')}${link('Our Story', 'story')}${link('Contact', 'contact')}</div><div class="gv-mobile-actions"><a href="${routes.wishlist}" data-nav>♡ Wishlist <span>${state.wishlist}</span></a><a href="${routes.bag}" data-nav>□ Shopping Bag <span>${state.bag}</span></a>${state.guest ? `${link('◎ Sign In', 'login')}${link('Create Account', 'register')}` : `${link('◎ Profile', 'account')}${link('My Orders', 'orders')}<button type="button" data-logout>Logout</button>`}</div></div>`; }
  function escapeHtml(value) { return value.replace(/[&<>"']/g, (char) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#039;' }[char])); }
  function closeMenus() { state.mobile = false; state.collections = false; state.account = false; render(); }
  function bind() {
    app.querySelectorAll('[data-nav]').forEach((element) => element.addEventListener('click', (event) => { event.preventDefault(); closeMenus(); state.message = `Demo navigation: ${element.textContent.trim()}. Connect this route to your live storefront.`; render(); }));
    app.querySelector('.gv-menu-button')?.addEventListener('click', (event) => { event.stopPropagation(); state.mobile = !state.mobile; state.account = false; render(); });
    app.querySelectorAll('[data-collections]').forEach((element) => element.addEventListener('click', (event) => { event.stopPropagation(); state.collections = !state.collections; render(); }));
    app.querySelector('.gv-nav-button')?.addEventListener('click', (event) => { event.stopPropagation(); state.collections = !state.collections; render(); });
    app.querySelector('.gv-account-button')?.addEventListener('click', (event) => { event.stopPropagation(); state.account = !state.account; state.collections = false; render(); });
    app.querySelectorAll('[data-logout]').forEach((element) => element.addEventListener('click', () => { state.message = 'Demo only: Salesforce authentication handles sign-out in the live component.'; closeMenus(); }));
    app.querySelector('.gv-search input').addEventListener('input', (event) => { state.query = event.target.value; });
    app.querySelector('.gv-search').addEventListener('submit', (event) => { event.preventDefault(); const query = state.query.trim(); state.message = query ? `Demo search submitted for “${query}”.` : 'Enter a jewellery style or collection to search.'; render(); });
  }
  document.addEventListener('click', (event) => { if (!app.contains(event.target) && (state.mobile || state.collections || state.account)) closeMenus(); });
  document.addEventListener('keydown', (event) => { if (event.key === 'Escape' && (state.mobile || state.collections || state.account)) closeMenus(); });
  document.querySelectorAll('[data-action]').forEach((element) => element.addEventListener('click', () => { if (element.dataset.action === 'wishlist') state.wishlist += 1; if (element.dataset.action === 'bag') state.bag += 1; if (element.dataset.action === 'guest') state.guest = !state.guest; render(); }));
  render();
})();
