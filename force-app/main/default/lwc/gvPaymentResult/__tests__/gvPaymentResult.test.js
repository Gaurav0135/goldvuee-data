
import { createElement } from 'lwc';
import Result from 'c/gvPaymentResult';
import status from '@salesforce/apex/GVRazorpayController.paymentStatus';
import refresh from '@salesforce/apex/GVRazorpayController.refreshPayment';
jest.mock('@salesforce/apex/GVRazorpayController.paymentStatus',()=>({default:jest.fn()}),{virtual:true});
jest.mock('@salesforce/apex/GVRazorpayController.refreshPayment',()=>({default:jest.fn()}),{virtual:true});
const flush=()=>Promise.resolve().then(()=>Promise.resolve()).then(()=>Promise.resolve());
afterEach(()=>{document.body.innerHTML='';sessionStorage.clear();jest.clearAllMocks();});
it('renders only the server-verified payment message',async()=>{status.mockResolvedValue({message:'Payment received. Stock review required.'});const el=createElement('c-gv-payment-result',{is:Result});el.paymentId='payment1';document.body.appendChild(el);await flush();expect(status).toHaveBeenCalledWith({paymentId:'payment1'});expect(el.shadowRoot.textContent).toContain('Stock review required');expect(el.paymentId).toBe('payment1');});
it('refreshes the restored customer-owned payment and handles access rejection',async()=>{sessionStorage.setItem('gvHostedPayment','payment1');status.mockRejectedValue(new Error('Denied'));refresh.mockResolvedValue({message:'Pending verification'});const el=createElement('c-gv-payment-result',{is:Result});document.body.appendChild(el);await flush();expect(el.shadowRoot.textContent).toContain('Sign in to the account');el.shadowRoot.querySelector('button').click();await flush();expect(refresh).toHaveBeenCalledWith({paymentId:'payment1'});expect(el.shadowRoot.textContent).toContain('Pending verification');});
