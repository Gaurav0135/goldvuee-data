import getCart from '@salesforce/apex/GVCartController.getCart';
jest.mock('@salesforce/apex/GVCartController.getCart',()=>({default:jest.fn()}),{virtual:true});

import { createElement } from 'lwc';
import Checkout from 'c/gvCheckout';
import loadDelivery from '@salesforce/apex/GVCheckoutController.loadDelivery';
import prepare from '@salesforce/apex/GVCheckoutController.prepareOrder';
import status from '@salesforce/apex/GVRazorpayController.paymentStatus';
jest.mock('@salesforce/apex/GVCheckoutController.loadDelivery',()=>({default:jest.fn()}),{virtual:true});
jest.mock('@salesforce/apex/GVCheckoutController.prepareOrder',()=>({default:jest.fn()}),{virtual:true});
jest.mock('@salesforce/apex/GVCheckoutController.loadOrder',()=>({default:jest.fn()}),{virtual:true});
jest.mock('@salesforce/apex/GVRazorpayController.startPayment',()=>({default:jest.fn()}),{virtual:true});
jest.mock('@salesforce/apex/GVRazorpayController.paymentStatus',()=>({default:jest.fn()}),{virtual:true});
jest.mock('@salesforce/apex/GVRazorpayController.refreshPayment',()=>({default:jest.fn()}),{virtual:true});
jest.mock('@salesforce/apex/GVRazorpayController.cancelPayment',()=>({default:jest.fn()}),{virtual:true});
jest.mock('@salesforce/user/isGuest',()=>({__esModule:true,default:false}),{virtual:true});
jest.mock('@salesforce/community/basePath',()=>({__esModule:true,default:'/shop/s'}),{virtual:true});
const flush=()=>Promise.resolve().then(()=>Promise.resolve()).then(()=>Promise.resolve());
const delivery={fullName:'A Customer',phone:'9876543210',street:'1 Gold Road',city:'Indore',state:'MP',postalCode:'452001',country:'India'};
afterEach(()=>{document.body.innerHTML='';sessionStorage.clear();jest.clearAllMocks();});
async function mount(){loadDelivery.mockResolvedValue(delivery);const el=createElement('c-gv-checkout',{is:Checkout});document.body.appendChild(el);await flush();return el;}
it('loads the saved address and reviews a server-created order',async()=>{prepare.mockResolvedValue({orderId:'o1',paymentId:'p1',total:200,delivery:{street:'A Customer\n9876543210\n1 Gold Road',city:'Indore',state:'MP',postalCode:'452001',country:'India'},items:[]});const el=await mount();expect(el.shadowRoot.querySelector('textarea').value).toBe('1 Gold Road');el.shadowRoot.querySelector('button').click();await flush();expect(prepare).toHaveBeenCalledWith({delivery});expect(el.shadowRoot.textContent).toContain('Your jewellery selection');});
it('keeps the address step after a server validation failure',async()=>{prepare.mockRejectedValue({body:{message:'Invalid address'}});const el=await mount();el.shadowRoot.querySelector('button').click();await flush();expect(el.shadowRoot.textContent).toContain('Invalid address');expect(el.shadowRoot.querySelector('input[name="postalCode"]')).not.toBeNull();});
it('does not infer success from browser return parameters',async()=>{const el=await mount();expect(status).not.toHaveBeenCalled();expect(el.shadowRoot.querySelector('c-gv-payment-result')).toBeNull();});

it('starts a new checkout when a previous payment is paid and the current bag has products',async()=>{sessionStorage.setItem('gvHostedPayment','paid-old');status.mockResolvedValue({paymentStatus:'Success',orderId:'old-order'});getCart.mockResolvedValue({itemCount:1});const el=await mount();await flush();expect(sessionStorage.getItem('gvHostedPayment')).toBeNull();expect(el.shadowRoot.querySelector('input[name="postalCode"]')).not.toBeNull();});

it.each(['9691184503', '+919691184503', '+91 9691184503'])('accepts %s in HTML and JavaScript and submits ten digits', async (phone) => {
  prepare.mockResolvedValue({orderId:'o1',paymentId:'p1',total:200,delivery:{...delivery,phone:'9691184503'},items:[]});
  const el = await mount();
  const input = el.shadowRoot.querySelector('input[name="phone"]');
  expect(new RegExp(`^(?:${input.pattern})$`).test(phone)).toBe(true);
  input.value = phone;
  input.dispatchEvent(new Event('input'));
  await flush();
  el.shadowRoot.querySelector('button').click();
  await flush();
  expect(prepare).toHaveBeenCalledWith({delivery:{...delivery,phone:'9691184503'}});
  expect(el.shadowRoot.textContent).toContain('Your jewellery selection');
  expect(el.shadowRoot.querySelector('.address').textContent).toContain('9691184503');
});

it.each(['12345', '+449691184503', '96911abc4503', '+919691184503abc', '919691184503'])('rejects %s consistently with a clear mobile message', async (phone) => {
  const el = await mount();
  const input = el.shadowRoot.querySelector('input[name="phone"]');
  expect(new RegExp(`^(?:${input.pattern})$`).test(phone)).toBe(false);
  input.value = phone;
  input.dispatchEvent(new Event('input'));
  await flush();
  el.shadowRoot.querySelector('button').click();
  await flush();
  expect(prepare).not.toHaveBeenCalled();
  expect(el.shadowRoot.querySelector('[role="alert"]').textContent).toContain('Enter a valid Indian mobile number');
});

it('keeps Contact phone separate from street and leaves invalid prefill empty', async () => {
  loadDelivery.mockResolvedValue({fullName:'A Customer',phone:'+91 9691184503',street:'+91 9691184503',city:null,state:'undefined',postalCode:'invalid',country:null});
  const el = createElement('c-gv-checkout',{is:Checkout});document.body.appendChild(el);await flush();
  expect(el.shadowRoot.querySelector('input[name="phone"]').value).toBe('9691184503');
  expect(el.shadowRoot.querySelector('textarea[name="street"]').value).toBe('');
  expect(el.shadowRoot.querySelector('input[name="city"]').value).toBe('');
  const state = el.shadowRoot.querySelector('input[name="state"]');
  expect(state.value).toBe('');expect(state.type).toBe('text');expect(state.readOnly).toBe(false);
  expect(el.shadowRoot.querySelector('input[name="postalCode"]').value).toBe('');
  expect(el.shadowRoot.querySelector('input[name="country"]').value).toBe('India');
  expect(el.shadowRoot.textContent).not.toMatch(/undefined|null/);
});

it('reads the latest browser-autofilled values before navigating to summary', async () => {
  prepare.mockResolvedValue({orderId:'o1',paymentId:'p1',total:200,delivery:{...delivery,phone:'9691184503',street:'42 Jewellery Lane'},items:[]});
  const el = await mount();
  // Browser autofill can update native values without dispatching an input event.
  el.shadowRoot.querySelector('input[name="phone"]').value = '+91 9691184503';
  el.shadowRoot.querySelector('textarea[name="street"]').value = '42 Jewellery Lane';
  el.shadowRoot.querySelector('button').click();await flush();
  expect(prepare).toHaveBeenCalledWith({delivery:{...delivery,phone:'9691184503',street:'42 Jewellery Lane'}});
  expect(el.shadowRoot.textContent).toContain('Your jewellery selection');
});

it('requires a valid country rather than silently accepting a null placeholder', async () => {
  const el = await mount();
  const country = el.shadowRoot.querySelector('input[name="country"]');
  country.value = 'null';country.dispatchEvent(new Event('input'));await flush();
  el.shadowRoot.querySelector('button').click();await flush();
  expect(prepare).not.toHaveBeenCalled();
  expect(el.shadowRoot.querySelector('[role="alert"]').textContent).toContain('Complete every delivery field');
});
