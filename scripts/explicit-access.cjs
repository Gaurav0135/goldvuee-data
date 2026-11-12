const fs=require('fs');
const names=['GVCheckoutEngine','GVCartController','GVInventoryService','GVPaymentController','GVOnlineCheckoutController','GVPaymentVerificationService','GVGatewayWorker','GVReconciliationScheduler','GVRazorpayWebhook','GVCheckoutRebuildTest','GVWebhookTest'];
for(const name of names){const file=`force-app/main/default/classes/${name}.cls`;let s=fs.readFileSync(file,'utf8');s=s.replace(/\[SELECT\b[^\]]*\]/gi,q=>{
 if(/WITH (SYSTEM|USER)_MODE/i.test(q))return q;
 // Find the first outer ordering/limit/lock clause, ignoring semi-join parentheses.
 let depth=0,quote=false,pos=q.length-1;
 for(let i=1;i<q.length-1;i++){if(q[i]==="'" && q[i-1]!=='\\')quote=!quote;if(quote)continue;if(q[i]==='(')depth++;if(q[i]===')')depth--;if(depth===0 && /^(ORDER BY|LIMIT|FOR UPDATE)\b/i.test(q.slice(i))){pos=i;break;}}
 return q.slice(0,pos)+' WITH SYSTEM_MODE '+q.slice(pos);
});s=s.replace(/\b(insert|update|delete) (?!as\s)(?=(?:new\s|[a-zA-Z_]\w*(?:\[|\.|\s*;)))/g,'$1 as system ');fs.writeFileSync(file,s);}
