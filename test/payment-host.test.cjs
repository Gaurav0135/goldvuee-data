const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const page=fs.readFileSync('force-app/main/default/pages/GVRazorpayHost.page','utf8');
const source=page.match(/<script>\s*\/\/<!\[CDATA\[([\s\S]*?)\/\/\]\]>/)[1]
  .replace("{!JSENCODE($Label.GoldVuee_Experience_Origin)}",'https://shop.example.my.site.com');
function host(){
  const nonce='1234567890abcdef1234567890abcdef',origin='https://shop.example.my.site.com';
  const listeners={},messages=[],nodes={},instances=[];
  const opener={postMessage:(payload,target)=>messages.push({payload,target})};
  const window={opener,location:{search:'?origin='+encodeURIComponent(origin)+'&nonce='+nonce},addEventListener:(type,fn)=>{listeners[type]=fn;}};
  window.Razorpay=function(options){this.options=options;this.opened=false;this.on=()=>{};this.open=()=>{this.opened=true;};instances.push(this);};
  const document={getElementById:id=>(nodes[id]??={style:{},textContent:'',addEventListener(){}})};
  vm.runInNewContext(source,{window,document,URL,URLSearchParams,Number,JSON});
  const send=(data,overrides={})=>listeners.message({source:opener,origin,data,...overrides});
  const start={source:'GOLDVUEE_CHECKOUT',type:'START_PAYMENT',nonce,data:{key:'rzp_test_fixture',orderId:'order_fixture',amount:90000}};
  return {nonce,origin,listeners,messages,instances,nodes,opener,send,start};
}
test('actual Visualforce script opens Razorpay from a JSON string and serializes callbacks',()=>{
  const h=host();h.listeners.load();assert.equal(typeof h.messages[0].payload,'string');assert.equal(JSON.parse(h.messages[0].payload).type,'READY');
  h.send(JSON.stringify(h.start));assert.equal(h.instances.length,1);assert.equal(h.instances[0].opened,true);assert.equal(h.instances[0].options.order_id,'order_fixture');
  h.instances[0].options.handler({razorpay_payment_id:'pay_fixture',razorpay_order_id:'order_fixture',razorpay_signature:'a'.repeat(64)});
  const callback=h.messages.at(-1);assert.equal(typeof callback.payload,'string');assert.equal(callback.target,h.origin);assert.equal(JSON.parse(callback.payload).type,'PAYMENT_SUCCESS');
});
test('rejects wrong origin, source and nonce before opening payment',()=>{
  const h=host();h.send(JSON.stringify(h.start),{origin:'https://attacker.example'});h.send(JSON.stringify(h.start),{source:{}});h.send(JSON.stringify({...h.start,nonce:'wrong'}));assert.equal(h.instances.length,0);
});
test('ignores malformed and oversized JSON and rejects invalid amounts',()=>{
  const h=host();h.send('{invalid');h.send('x'.repeat(16385));assert.equal(h.instances.length,0);
  h.send(JSON.stringify({...h.start,data:{...h.start.data,amount:0}}));assert.equal(h.instances.length,0);assert.equal(JSON.parse(h.messages.at(-1).payload).type,'ERROR');
});
test('does not open duplicate Razorpay windows for repeated initialization messages',()=>{
  const h=host();h.send(JSON.stringify(h.start));h.send(JSON.stringify(h.start));assert.equal(h.instances.length,1);
});
