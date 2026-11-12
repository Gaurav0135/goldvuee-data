const fs=require('fs');const root='force-app/main/default';fs.mkdirSync(root+'/profiles',{recursive:true});
const transactionObjects=['Shopping_Cart__c','Cart_Item__c','Jewellery_Order__c','Jewellery_Order_Item__c','Payment__c'];
const customerClasses=['GVCartController','GVOnlineCheckoutController','GVPaymentController','GVPaymentVerificationController','GVOrderHistoryController','GVMyAccountController','GVProductController','GVNewArrivalsController'];
for(const name of ['GoldVuee Customer','GoldVuee Profile']){
 const guest=name==='GoldVuee Profile';let s=fs.readFileSync(`access-complete/profiles/${name}.profile-meta.xml`,'utf8');
 s=s.replace(/<objectPermissions>[\s\S]*?<\/objectPermissions>/g,block=>{const obj=block.match(/<object>(.*?)<\/object>/)?.[1];if(!transactionObjects.includes(obj))return block;let b=block.replace(/<(allowCreate|allowDelete|allowEdit)>true<\//g,'<$1>false</');if(guest)b=b.replace('<allowRead>true</allowRead>','<allowRead>false</allowRead>');return b;});
 s=s.replace(/<fieldPermissions>[\s\S]*?<\/fieldPermissions>/g,b=>b.replace('<editable>true</editable>','<editable>false</editable>'));
 for(const cls of [...customerClasses,'GVRazorpayWebhook']){
  const enabled=guest?(cls==='GVRazorpayWebhook' || ['GVProductController','GVNewArrivalsController','GVMyAccountController'].includes(cls)):cls!=='GVRazorpayWebhook';
  const re=new RegExp(`<classAccesses>\\s*<apexClass>${cls}<\\/apexClass>\\s*<enabled>.*?<\\/enabled>\\s*<\\/classAccesses>`);
  const block=`<classAccesses><apexClass>${cls}</apexClass><enabled>${enabled}</enabled></classAccesses>`;
  if(re.test(s))s=s.replace(re,block);else s=s.replace('<custom>',block+'<custom>');
 }
 fs.writeFileSync(`${root}/profiles/${name}.profile-meta.xml`,s);
}
// Public availability is derived from available inventory, without exposing physical stock to callers.
for(const file of [`${root}/classes/GVProductController.cls`,`${root}/lwc/gvProductDetails/gvProductDetails.js`]){let s=fs.readFileSync(file,'utf8').replaceAll('Stock_Quantity__c','Available_Quantity__c');fs.writeFileSync(file,s);}
// Fix storefront routes to follow the deployed Experience base path.
for(const name of ['gvProductCatalog','gvShoppingCart']){const file=`${root}/lwc/${name}/${name}.js`;let s=fs.readFileSync(file,'utf8');if(!s.includes("from '@salesforce/community/basePath'"))s="import communityBasePath from '@salesforce/community/basePath';\n"+s;s=s.replaceAll("'/goldvuee/product-details?c__productId='","`${communityBasePath}/product-details?c__productId=`").replaceAll("'/goldvuee/collections'","`${communityBasePath}/collections`");fs.writeFileSync(file,s);}
