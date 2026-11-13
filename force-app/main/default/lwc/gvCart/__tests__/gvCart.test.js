
import { createElement } from 'lwc';
import Cart from 'c/gvCart';
import getCart from '@salesforce/apex/GVCartController.getCart';
import update from '@salesforce/apex/GVCartController.updateCartItem';
import remove from '@salesforce/apex/GVCartController.removeCartItem';
jest.mock('@salesforce/apex/GVCartController.getCart',()=>({default:jest.fn()}),{virtual:true});
jest.mock('@salesforce/apex/GVCartController.updateCartItem',()=>({default:jest.fn()}),{virtual:true});
jest.mock('@salesforce/apex/GVCartController.removeCartItem',()=>({default:jest.fn()}),{virtual:true});
jest.mock('@salesforce/user/isGuest',()=>({__esModule:true,default:false}),{virtual:true});
jest.mock('@salesforce/community/basePath',()=>({__esModule:true,default:'/shop/s'}),{virtual:true});
const flush=()=>Promise.resolve().then(()=>Promise.resolve()).then(()=>Promise.resolve());
const cart={itemCount:2,totalAmount:200,items:[{Id:'line1',Quantity__c:2,Unit_Price__c:100,Line_Total__c:200,Jewellery_Product__r:{Name:'Gold ring',Main_Image_URL__c:'https://example.com/ring.jpg'}}]};
afterEach(()=>{document.body.innerHTML='';jest.clearAllMocks();});
async function mount(){const el=createElement('c-gv-cart',{is:Cart});document.body.appendChild(el);await flush();return el;}
it('loads the persisted cart, displays products and maintains community checkout navigation',async()=>{getCart.mockResolvedValue(cart);const el=await mount();expect(el.shadowRoot.textContent).toContain('Gold ring');expect(el.shadowRoot.querySelector('a').getAttribute('href')).toBe('/shop/s/checkout');});
it('updates only the selected line and publishes the server count',async()=>{getCart.mockResolvedValue(cart);update.mockResolvedValue({...cart,itemCount:3});const handler=jest.fn();window.addEventListener('goldvueecartchange',handler);const el=await mount();el.shadowRoot.querySelector('[data-action="plus"]').click();await flush();expect(update).toHaveBeenCalledWith({cartItemId:'line1',quantity:3});expect(handler.mock.calls.at(-1)[0].detail.count).toBe(3);window.removeEventListener('goldvueecartchange',handler);});
it('removes items and shows the empty state',async()=>{getCart.mockResolvedValue(cart);remove.mockResolvedValue({items:[],itemCount:0,totalAmount:0});const el=await mount();el.shadowRoot.querySelector('[data-action="remove"]').click();await flush();expect(el.shadowRoot.textContent).toContain('Your bag awaits');});
it('shows a server rejection without mutating the displayed quantity',async()=>{getCart.mockResolvedValue(cart);update.mockRejectedValue({body:{message:'Insufficient available stock.'}});const el=await mount();el.shadowRoot.querySelector('[data-action="plus"]').click();await flush();expect(el.shadowRoot.querySelector('[role="alert"]').textContent).toContain('Insufficient available stock.');});
