
import { createElement } from 'lwc';
import Header from 'c/goldvueeHeader';
import getCart from '@salesforce/apex/GVCartController.getCart';
jest.mock('@salesforce/apex/GVCartController.getCart',()=>({default:jest.fn().mockResolvedValue({itemCount:2})}),{virtual:true});
jest.mock('@salesforce/user/isGuest',()=>({__esModule:true,default:false}),{virtual:true});
afterEach(()=>{document.body.innerHTML='';jest.clearAllMocks();});
const flush=()=>Promise.resolve().then(()=>Promise.resolve());
it('preserves collections, arrivals, cart and account navigation',async()=>{const el=createElement('c-goldvuee-header',{is:Header});document.body.appendChild(el);await flush();const links=[...el.shadowRoot.querySelectorAll('a')].map(a=>a.getAttribute('href'));expect(links.some(x=>x.endsWith('/collections'))).toBe(true);expect(links.some(x=>x.endsWith('/new-arrivals'))).toBe(true);expect(links.some(x=>x.endsWith('/shopping-cart'))).toBe(true);expect(links.some(x=>x.endsWith('/my-account'))).toBe(true);expect(getCart).toHaveBeenCalledTimes(1);});
it('shows the server cart badge and follows cart updates',async()=>{const el=createElement('c-goldvuee-header',{is:Header});document.body.appendChild(el);await flush();expect(el.shadowRoot.textContent).toContain('Cart (2)');window.dispatchEvent(new CustomEvent('goldvueecartchange',{detail:{count:4}}));await flush();expect(el.shadowRoot.textContent).toContain('Cart (4)');});
