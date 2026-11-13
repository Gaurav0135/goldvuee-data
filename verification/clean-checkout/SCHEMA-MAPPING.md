# GoldVuee schema audit — 13 November 2026

Org: goldvuee / 00DjV000007hdmrUAA (Developer Edition). No records changed.

## Discovered fields

| Object | Field | Type | Required on create | Relationship / active values |
|---|---|---|---|---|
|Account|Name|string|True||
|Account|Phone|phone|False||
|Account|CustomerPriority__c|picklist|False|High, Low, Medium|
|Account|SLA__c|picklist|False|Gold, Silver, Platinum, Bronze|
|Account|Active__c|picklist|False|No, Yes|
|Account|NumberofLocations__c|double|False||
|Account|UpsellOpportunity__c|picklist|False|Maybe, No, Yes|
|Account|SLASerialNumber__c|string|False||
|Account|SLAExpirationDate__c|date|False||

Account record types: Master

|Cart_Item__c|Name|string|False||
|Cart_Item__c|Shopping_Cart__c|reference|True|Shopping_Cart__c|
|Cart_Item__c|Jewellery_Product__c|reference|True|Jewellery_Product__c|
|Cart_Item__c|Quantity__c|double|True||
|Cart_Item__c|Unit_Price__c|currency|True||
|Cart_Item__c|Line_Total__c|currency|False||

Cart_Item__c record types: Master

|Contact|AccountId|reference|False|Account|
|Contact|Name|string|False||
|Contact|MailingStreet|textarea|False||
|Contact|MailingCity|string|False||
|Contact|MailingState|string|False||
|Contact|MailingPostalCode|string|False||
|Contact|MailingCountry|string|False||
|Contact|Phone|phone|False||
|Contact|MobilePhone|phone|False||
|Contact|Level__c|picklist|False|Secondary, Tertiary, Primary|
|Contact|Languages__c|string|False||

Contact record types: Master

|GV_Payment_Config__c|Name|string|False||
|GV_Payment_Config__c|Razorpay_Test_Secret__c|encryptedstring|False||
|GV_Payment_Config__c|Webhook_Secret__c|encryptedstring|False||

GV_Payment_Config__c record types: Master

|GV_Webhook_Receipt__c|Name|string|False||

GV_Webhook_Receipt__c record types: Master

|Inventory__c| Not present in org | | | |
|Inventory_Movement__c|Name|string|False||
|Inventory_Movement__c|Jewellery_Product__c|reference|False|Jewellery_Product__c|
|Inventory_Movement__c|Jewellery_Order__c|reference|False|Jewellery_Order__c|
|Inventory_Movement__c|Movement_Type__c|picklist|False|Stock In, Sale, Return, Adjustment, Damage|
|Inventory_Movement__c|Quantity__c|double|False||
|Inventory_Movement__c|Stock_Before__c|double|False||
|Inventory_Movement__c|Stock_After__c|double|False||
|Inventory_Movement__c|Reason__c|textarea|False||
|Inventory_Movement__c|Movement_Date__c|datetime|False||

Inventory_Movement__c record types: Master

|Jewellery_Order__c|Name|string|False||
|Jewellery_Order__c|Customer__c|reference|False|Contact|
|Jewellery_Order__c|Shopping_Cart__c|reference|False|Shopping_Cart__c|
|Jewellery_Order__c|Order_Date__c|datetime|True||
|Jewellery_Order__c|Order_Status__c|picklist|False|pending, Confirmed, Processing, Shipped, Delivered, Cancelled|
|Jewellery_Order__c|Subtotal__c|currency|False||
|Jewellery_Order__c|Discount_Amount__c|currency|False||
|Jewellery_Order__c|Tax_Amount__c|currency|False||
|Jewellery_Order__c|Shipping_Charges__c|currency|False||
|Jewellery_Order__c|Grand_Total__c|currency|False||
|Jewellery_Order__c|Shipping_Address__c|textarea|False||
|Jewellery_Order__c|Shipping_City__c|string|False||
|Jewellery_Order__c|Shipping_State__c|string|False||
|Jewellery_Order__c|Shipping_Postal_Code__c|string|False||
|Jewellery_Order__c|Shipping_Country__c|string|True||
|Jewellery_Order__c|Payment_Status__c|picklist|False|Pending, Paid, Failed, Refunded|

Jewellery_Order__c record types: Master

|Jewellery_Order_Item__c|Name|string|False||
|Jewellery_Order_Item__c|Jewellery_Order__c|reference|True|Jewellery_Order__c|
|Jewellery_Order_Item__c|Jewellery_Product__c|reference|False|Jewellery_Product__c|
|Jewellery_Order_Item__c|Quantity__c|double|True||
|Jewellery_Order_Item__c|Unit_Price__c|currency|True||
|Jewellery_Order_Item__c|Discount_Amount__c|currency|False||
|Jewellery_Order_Item__c|Line_Total__c|currency|False||

Jewellery_Order_Item__c record types: Master

|Jewellery_Product__c|Name|string|False||
|Jewellery_Product__c|Product_Code__c|string|False||
|Jewellery_Product__c|Description__c|textarea|False||
|Jewellery_Product__c|Price__c|currency|True||
|Jewellery_Product__c|Discount_Price__c|currency|False||
|Jewellery_Product__c|Metal_Type__c|picklist|False|Gold, Silver, Platinum, Diamond, Rose Gold|
|Jewellery_Product__c|Purity__c|picklist|False|20k, 24K, 22K, 18K, 14K, 925 Silver, Platinum 950, N/A|
|Jewellery_Product__c|Weight__c|double|True||
|Jewellery_Product__c|Stone_Type__c|picklist|False|Sapphire, Emerald, Diamond, Ruby, Pearl, None|
|Jewellery_Product__c|Gender__c|picklist|False|Men, women, Kid|
|Jewellery_Product__c|Stock_Quantity__c|double|True||
|Jewellery_Product__c|Featured_Product__c|boolean|False||
|Jewellery_Product__c|Bestseller__c|boolean|False||
|Jewellery_Product__c|New_Arrival__c|boolean|False||
|Jewellery_Product__c|Active__c|boolean|False||
|Jewellery_Product__c|Main_Image_URL__c|url|False||
|Jewellery_Product__c|SKU__c|string|True||
|Jewellery_Product__c|Availability_Status__c|string|False||
|Jewellery_Product__c|Category__c|reference|True|Jewellery_Category__c|
|Jewellery_Product__c|Low_Stock_Threshold__c|double|False||
|Jewellery_Product__c|Reserved_Quantity__c|double|False||
|Jewellery_Product__c|Available_Quantity__c|double|False||

Jewellery_Product__c record types: Master

|Order|Id|id|False||
|Order|OwnerId|reference|False|Group, User|
|Order|ContractId|reference|False|Contract|
|Order|AccountId|reference|False|Account|
|Order|Pricebook2Id|reference|False|Pricebook2|
|Order|OriginalOrderId|reference|False|Order|
|Order|EffectiveDate|date|True||
|Order|EndDate|date|False||
|Order|IsReductionOrder|boolean|False||
|Order|Status|picklist|True|Draft, Activated|
|Order|Description|textarea|False||
|Order|CustomerAuthorizedById|reference|False|Contact|
|Order|CustomerAuthorizedDate|date|False||
|Order|CompanyAuthorizedById|reference|False|User|
|Order|CompanyAuthorizedDate|date|False||
|Order|Type|picklist|False||
|Order|BillingStreet|textarea|False||
|Order|BillingCity|string|False||
|Order|BillingState|string|False||
|Order|BillingPostalCode|string|False||
|Order|BillingCountry|string|False||
|Order|BillingStateCode|picklist|False|AC, AG, AG, 05, 02, AL, AL, AK, AB, AL, AP, AM, AN, AN, AP, 34, 23, AO, AR, AZ, AR, AR, AP, AS, AT, ACT, AV, BA, BC, BS, BA, BT, 11, BL, BN, BG, BI, BR, BO, BZ, BS, BR, BC, CA, CA, CL, CM, CB, CI, CW, CE, CT, CZ, CN, CE, CH, CT, CS, 12, CH, CH, 50, CE, CO, CL, CO, CO, CT, CO, CS, CR, KR, CN, DN, DD, DE, DL, DC, DF, DL, D, DG, 38, EN, ES, DF, FM, FE, FI, FL, FG, FC, FR, 35, 18, 40, 07, G, 62, GE, GA, 21, GA, GO, GO, GR, GT, 44, 45, GR, 52, GJ, 10, 46, HR, HI, 13, 23, 41, HG, HP, 34, 01, 91, 42, 43, 28, 08, ID, IL, IM, IN, IA, IS, 17, 03, JA, JK, JH, 32, 36, 22, 37, 46, 14, KS, KA, KY, KL, KY, KE, KK, 39, 43, 26, AQ, LD, LS, SP, LT, LE, LC, LM, 21, LK, LI, LO, LD, LA, LH, LU, 92, MC, MP, MH, ME, MN, MB, MN, MA, MD, MS, MA, MT, MT, MS, MO, MH, VS, ML, ME, ME, MI, MI, 24, MI, MG, MN, MS, MO, 04, 45, MZ, MO, MN, MT, MB, MO, NL, 20, 42, NA, 29, NA, NE, 15, NV, NB, NL, NH, NJ, NM, NSW, NY, 15, 64, NC, ND, NT, NT, NO, NS, NL, NU, NU, OA, OR, OY, OG, OH, 44, 33, 47, OK, OT, ON, OR, OR, 27, PD, PA, PA, PB, PR, PR, PV, PA, PE, PG, PU, PE, PC, PI, PI, PT, PN, PZ, PO, PE, PY, PB, PB, 63, QC, QLD, QE, QR, RG, RJ, RA, RC, RE, RI, RI, RN, RJ, RN, RS, RM, RO, RR, RN, RO, 41, 11, SA, SL, SC, SP, SK, SS, SV, SE, 61, 37, 31, 14, 25, 32, 22, 51, SI, SK, SI, SO, SO, SO, SA, SC, SD, SR, TB, 71, TM, TN, TA, TAS, TG, TN, TE, TR, TX, 12, TA, TL, TO, 09, 36, 13, 31, 16, TP, TN, TV, TS, TR, TO, UD, UT, UT, UP, VA, VE, VE, VB, VC, VT, VR, VV, VI, VIC, VA, VT, 30, WA, WD, WB, WA, WH, WV, WX, WW, WI, WY, 65, 54, 06, 35, 19, YU, YT, 53, ZA, 33|
|Order|BillingCountryCode|picklist|False|AF, AX, AL, DZ, AD, AO, AI, AQ, AG, AR, AM, AW, AU, AT, AZ, BS, BH, BD, BB, BY, BE, BZ, BJ, BM, BT, BO, BQ, BA, BW, BV, BR, IO, BN, BG, BF, BI, KH, CM, CA, CV, KY, CF, TD, CL, CN, CX, CC, CO, KM, CG, CD, CK, CR, CI, HR, CW, CY, CZ, DK, DJ, DM, DO, EC, EG, SV, GQ, ER, EE, SZ, ET, FK, FO, FJ, FI, FR, GF, PF, TF, GA, GM, GE, DE, GH, GI, GR, GL, GD, GP, GT, GG, GN, GW, GY, HT, HM, VA, HN, HU, IS, IN, ID, IQ, IE, IM, IL, IT, JM, JP, JE, JO, KZ, KE, KI, KR, XK, KW, KG, LA, LV, LB, LS, LR, LY, LI, LT, LU, MO, MG, MW, MY, MV, ML, MT, MQ, MR, MU, YT, MX, MD, MC, MN, ME, MS, MA, MZ, MM, NA, NR, NP, NL, NC, NZ, NI, NE, NG, NU, NF, MK, NO, OM, PK, PS, PA, PG, PY, PE, PH, PN, PL, PT, QA, RE, RO, RU, RW, BL, SH, KN, LC, MF, PM, VC, WS, SM, ST, SA, SN, RS, SC, SL, SG, SX, SK, SI, SB, SO, ZA, GS, SS, ES, LK, SR, SJ, SE, CH, TW, TJ, TZ, TH, TL, TG, TK, TO, TT, TN, TR, TM, TC, TV, UG, UA, AE, GB, US, UY, UZ, VU, VE, VN, VG, WF, EH, YE, ZM, ZW|
|Order|BillingLatitude|double|False||
|Order|BillingLongitude|double|False||
|Order|BillingGeocodeAccuracy|picklist|False|Address, NearAddress, Block, Street, ExtendedZip, Zip, Neighborhood, City, County, State, Unknown|
|Order|BillingAddress|address|False||
|Order|ShippingStreet|textarea|False||
|Order|ShippingCity|string|False||
|Order|ShippingState|string|False||
|Order|ShippingPostalCode|string|False||
|Order|ShippingCountry|string|False||
|Order|ShippingStateCode|picklist|False|AC, AG, AG, 05, 02, AL, AL, AK, AB, AL, AP, AM, AN, AN, AP, 34, 23, AO, AR, AZ, AR, AR, AP, AS, AT, ACT, AV, BA, BC, BS, BA, BT, 11, BL, BN, BG, BI, BR, BO, BZ, BS, BR, BC, CA, CA, CL, CM, CB, CI, CW, CE, CT, CZ, CN, CE, CH, CT, CS, 12, CH, CH, 50, CE, CO, CL, CO, CO, CT, CO, CS, CR, KR, CN, DN, DD, DE, DL, DC, DF, DL, D, DG, 38, EN, ES, DF, FM, FE, FI, FL, FG, FC, FR, 35, 18, 40, 07, G, 62, GE, GA, 21, GA, GO, GO, GR, GT, 44, 45, GR, 52, GJ, 10, 46, HR, HI, 13, 23, 41, HG, HP, 34, 01, 91, 42, 43, 28, 08, ID, IL, IM, IN, IA, IS, 17, 03, JA, JK, JH, 32, 36, 22, 37, 46, 14, KS, KA, KY, KL, KY, KE, KK, 39, 43, 26, AQ, LD, LS, SP, LT, LE, LC, LM, 21, LK, LI, LO, LD, LA, LH, LU, 92, MC, MP, MH, ME, MN, MB, MN, MA, MD, MS, MA, MT, MT, MS, MO, MH, VS, ML, ME, ME, MI, MI, 24, MI, MG, MN, MS, MO, 04, 45, MZ, MO, MN, MT, MB, MO, NL, 20, 42, NA, 29, NA, NE, 15, NV, NB, NL, NH, NJ, NM, NSW, NY, 15, 64, NC, ND, NT, NT, NO, NS, NL, NU, NU, OA, OR, OY, OG, OH, 44, 33, 47, OK, OT, ON, OR, OR, 27, PD, PA, PA, PB, PR, PR, PV, PA, PE, PG, PU, PE, PC, PI, PI, PT, PN, PZ, PO, PE, PY, PB, PB, 63, QC, QLD, QE, QR, RG, RJ, RA, RC, RE, RI, RI, RN, RJ, RN, RS, RM, RO, RR, RN, RO, 41, 11, SA, SL, SC, SP, SK, SS, SV, SE, 61, 37, 31, 14, 25, 32, 22, 51, SI, SK, SI, SO, SO, SO, SA, SC, SD, SR, TB, 71, TM, TN, TA, TAS, TG, TN, TE, TR, TX, 12, TA, TL, TO, 09, 36, 13, 31, 16, TP, TN, TV, TS, TR, TO, UD, UT, UT, UP, VA, VE, VE, VB, VC, VT, VR, VV, VI, VIC, VA, VT, 30, WA, WD, WB, WA, WH, WV, WX, WW, WI, WY, 65, 54, 06, 35, 19, YU, YT, 53, ZA, 33|
|Order|ShippingCountryCode|picklist|False|AF, AX, AL, DZ, AD, AO, AI, AQ, AG, AR, AM, AW, AU, AT, AZ, BS, BH, BD, BB, BY, BE, BZ, BJ, BM, BT, BO, BQ, BA, BW, BV, BR, IO, BN, BG, BF, BI, KH, CM, CA, CV, KY, CF, TD, CL, CN, CX, CC, CO, KM, CG, CD, CK, CR, CI, HR, CW, CY, CZ, DK, DJ, DM, DO, EC, EG, SV, GQ, ER, EE, SZ, ET, FK, FO, FJ, FI, FR, GF, PF, TF, GA, GM, GE, DE, GH, GI, GR, GL, GD, GP, GT, GG, GN, GW, GY, HT, HM, VA, HN, HU, IS, IN, ID, IQ, IE, IM, IL, IT, JM, JP, JE, JO, KZ, KE, KI, KR, XK, KW, KG, LA, LV, LB, LS, LR, LY, LI, LT, LU, MO, MG, MW, MY, MV, ML, MT, MQ, MR, MU, YT, MX, MD, MC, MN, ME, MS, MA, MZ, MM, NA, NR, NP, NL, NC, NZ, NI, NE, NG, NU, NF, MK, NO, OM, PK, PS, PA, PG, PY, PE, PH, PN, PL, PT, QA, RE, RO, RU, RW, BL, SH, KN, LC, MF, PM, VC, WS, SM, ST, SA, SN, RS, SC, SL, SG, SX, SK, SI, SB, SO, ZA, GS, SS, ES, LK, SR, SJ, SE, CH, TW, TJ, TZ, TH, TL, TG, TK, TO, TT, TN, TR, TM, TC, TV, UG, UA, AE, GB, US, UY, UZ, VU, VE, VN, VG, WF, EH, YE, ZM, ZW|
|Order|ShippingLatitude|double|False||
|Order|ShippingLongitude|double|False||
|Order|ShippingGeocodeAccuracy|picklist|False|Address, NearAddress, Block, Street, ExtendedZip, Zip, Neighborhood, City, County, State, Unknown|
|Order|ShippingAddress|address|False||
|Order|Name|string|False||
|Order|PoDate|date|False||
|Order|PoNumber|string|False||
|Order|OrderReferenceNumber|string|False||
|Order|BillToContactId|reference|False|Contact|
|Order|ShipToContactId|reference|False|Contact|
|Order|ActivatedDate|datetime|False||
|Order|ActivatedById|reference|False|User|
|Order|StatusCode|picklist|False|Draft, Activated, Canceled, Expired, Superseded|
|Order|OrderNumber|string|False||
|Order|TotalAmount|currency|False||
|Order|CreatedDate|datetime|False||
|Order|CreatedById|reference|False|User|
|Order|LastModifiedDate|datetime|False||
|Order|LastModifiedById|reference|False|User|
|Order|IsDeleted|boolean|False||
|Order|SystemModstamp|datetime|False||
|Order|LastViewedDate|datetime|False||
|Order|LastReferencedDate|datetime|False||

Order record types: Master

|OrderItem|Id|id|False||
|OrderItem|Product2Id|reference|False|Product2|
|OrderItem|IsDeleted|boolean|False||
|OrderItem|OrderId|reference|True|Order|
|OrderItem|PricebookEntryId|reference|True|PricebookEntry|
|OrderItem|OriginalOrderItemId|reference|False|OrderItem|
|OrderItem|AvailableQuantity|double|False||
|OrderItem|Quantity|double|True||
|OrderItem|UnitPrice|currency|False||
|OrderItem|ListPrice|currency|False||
|OrderItem|TotalPrice|currency|False||
|OrderItem|ServiceDate|date|False||
|OrderItem|EndDate|date|False||
|OrderItem|Description|string|False||
|OrderItem|CreatedDate|datetime|False||
|OrderItem|CreatedById|reference|False|User|
|OrderItem|LastModifiedDate|datetime|False||
|OrderItem|LastModifiedById|reference|False|User|
|OrderItem|SystemModstamp|datetime|False||
|OrderItem|OrderItemNumber|string|False||

OrderItem record types: 

|Payment__c|Name|string|False||
|Payment__c|Jewellery_Order__c|reference|False|Jewellery_Order__c|
|Payment__c|Payment_Amount__c|currency|True||
|Payment__c|Payment_Method__c|picklist|False|UPI, Card, Net Banking, Wallet, COD|
|Payment__c|Payment_Status__c|picklist|False|Pending, Success, Failed, Refunded|
|Payment__c|Transaction_ID__c|string|False||
|Payment__c|Razorpay_Order_ID__c|string|False||
|Payment__c|Payment_Date__c|datetime|False||
|Payment__c|Failure_Reason__c|textarea|False||
|Payment__c|Gateway_Response__c|textarea|False||

Payment__c record types: Master

|Pricebook2|Id|id|False||
|Pricebook2|IsDeleted|boolean|False||
|Pricebook2|Name|string|True||
|Pricebook2|CreatedDate|datetime|False||
|Pricebook2|CreatedById|reference|False|User|
|Pricebook2|LastModifiedDate|datetime|False||
|Pricebook2|LastModifiedById|reference|False|User|
|Pricebook2|SystemModstamp|datetime|False||
|Pricebook2|LastViewedDate|datetime|False||
|Pricebook2|LastReferencedDate|datetime|False||
|Pricebook2|IsActive|boolean|False||
|Pricebook2|IsArchived|boolean|False||
|Pricebook2|Description|string|False||
|Pricebook2|IsStandard|boolean|False||

Pricebook2 record types: Master

|PricebookEntry|Id|id|False||
|PricebookEntry|Name|string|False||
|PricebookEntry|Pricebook2Id|reference|True|Pricebook2|
|PricebookEntry|Product2Id|reference|True|Product2|
|PricebookEntry|UnitPrice|currency|True||
|PricebookEntry|IsActive|boolean|False||
|PricebookEntry|UseStandardPrice|boolean|False||
|PricebookEntry|CreatedDate|datetime|False||
|PricebookEntry|CreatedById|reference|False|User|
|PricebookEntry|LastModifiedDate|datetime|False||
|PricebookEntry|LastModifiedById|reference|False|User|
|PricebookEntry|SystemModstamp|datetime|False||
|PricebookEntry|ProductCode|string|False||
|PricebookEntry|IsDeleted|boolean|False||
|PricebookEntry|IsArchived|boolean|False||

PricebookEntry record types: 

|Product2|Id|id|False||
|Product2|Name|string|True||
|Product2|ProductCode|string|False||
|Product2|Description|textarea|False||
|Product2|IsActive|boolean|False||
|Product2|CreatedDate|datetime|False||
|Product2|CreatedById|reference|False|User|
|Product2|LastModifiedDate|datetime|False||
|Product2|LastModifiedById|reference|False|User|
|Product2|SystemModstamp|datetime|False||
|Product2|Family|picklist|False|None|
|Product2|ExternalDataSourceId|reference|False|ExternalDataSource|
|Product2|ExternalId|string|False||
|Product2|DisplayUrl|url|False||
|Product2|QuantityUnitOfMeasure|picklist|False|Each|
|Product2|IsDeleted|boolean|False||
|Product2|IsArchived|boolean|False||
|Product2|LastViewedDate|datetime|False||
|Product2|LastReferencedDate|datetime|False||
|Product2|StockKeepingUnit|string|False||
|Product2|Type|picklist|False|Base, Bundle, Set|
|Product2|ProductClass|picklist|False|Simple, VariationParent, Variation, Bundle, Set|

Product2 record types: Master

|Reservation__c| Not present in org | | | |
|Shopping_Cart__c|Name|string|False||
|Shopping_Cart__c|Customer__c|reference|False|Contact|
|Shopping_Cart__c|Session_ID__c|string|False||
|Shopping_Cart__c|Cart_Status__c|picklist|False|Active, Converted, Abandoned|
|Shopping_Cart__c|Total_Amount__c|currency|False||

Shopping_Cart__c record types: Master

|Stock_Reservation__c|Name|string|False||
|Stock_Reservation__c|Jewellery_Product__c|reference|False|Jewellery_Product__c|
|Stock_Reservation__c|Jewellery_Order__c|reference|False|Jewellery_Order__c|
|Stock_Reservation__c|Reserved_Quantity__c|double|False||
|Stock_Reservation__c|Reservation_Status__c|picklist|False|Active, Committed, Release, Expired, Released|
|Stock_Reservation__c|Reserved_At__c|datetime|False||
|Stock_Reservation__c|Expires_At__c|datetime|False||
|Stock_Reservation__c|Released_At__c|datetime|False||
|Stock_Reservation__c|Reservation_Reason__c|string|False||

Stock_Reservation__c record types: Master

|User|Name|string|False||
|User|Phone|phone|False||
|User|MobilePhone|phone|False||
|User|ContactId|reference|False|Contact|
|User|AccountId|reference|False|Account|

User record types: 

## Local / deployed differences

- Differs: `classes\GVAbandonedCheckoutService.cls`
- Differs: `classes\GVCartController.cls`
- Differs: `classes\GVCheckoutEngine.cls`
- Differs: `classes\GVCheckoutJourneyTest.cls`
- Differs: `classes\GVGatewayWorker.cls`
- Differs: `classes\GVInventoryService.cls`
- Differs: `classes\GVMyAccountController.cls`
- Differs: `classes\GVNewArrivalsController.cls`
- Differs: `classes\GVOnlineCheckoutController.cls`
- Differs: `classes\GVOrderHistoryController.cls`
- Differs: `classes\GVOrderHistoryController.cls-meta.xml`
- Differs: `classes\GVPaymentController.cls`
- Differs: `classes\GVProductController.cls`
- Differs: `classes\GVRazorpayService.cls`
- Differs: `pages\GVRazorpayHost.page`
- Differs: `pages\GVRazorpayPopupDemo.page`
- Differs: `pages\GVRazorpayPopupDemo.page-meta.xml`

## Validation rules (deployed)

- objects\Cart_Item__c\validationRules\GV_Cart_Item_Validation.validationRule-meta.xml: true; OR(
    ISBLANK(Quantity__c),
    Quantity__c < 1,
    ISBLANK(Unit_Price__c),
    Unit_Price__c < 0,
    AND(
        NOT(ISBLANK(Line_Total__c)),
        Line_Total__c < 0
    )
)
- objects\Jewellery_Category__c\validationRules\GV_Category_Validation.validationRule-meta.xml: true; AND(
    NOT(ISBLANK(Display_Order__c)),
    Display_Order__c < 0
)
- objects\Jewellery_Order__c\validationRules\GV_Order_Validation.validationRule-meta.xml: true; OR(
    Grand_Total__c < 0,
    Discount_Amount__c < 0,
    Shipping_Charges__c < 0,
    AND(
        ISPICKVAL(Order_Status__c, "Confirmed"),
        ISBLANK(Shipping_Address__c)
    ),
    AND(
        OR(
            ISPICKVAL(Order_Status__c, "Confirmed"),
            NOT(ISBLANK(Shipping_Address__c)),
            NOT(ISBLANK(Shipping_City__c)),
            NOT(ISBLANK(Shipping_State__c)),
            NOT(ISBLANK(Shipping_Postal_Code__c))
        ),
        OR(
            ISBLANK(Shipping_City__c),
            ISBLANK(Shipping_State__c),
            ISBLANK(Shipping_Postal_Code__c)
        )
    )
)
- objects\Jewellery_Order_Item__c\validationRules\GV_Order_Item_Validation.validationRule-meta.xml: true; OR(
    ISBLANK(Quantity__c),
    Quantity__c < 1,
    ISBLANK(Unit_Price__c),
    Unit_Price__c < 0
)
- objects\Jewellery_Product__c\validationRules\GV_Prevent_Negative_Inventory.validationRule-meta.xml: true; OR(
    Stock_Quantity__c < 0,
    Reserved_Quantity__c < 0,
    BLANKVALUE(Reserved_Quantity__c, 0) >
    BLANKVALUE(Stock_Quantity__c, 0)
)
- objects\Jewellery_Product__c\validationRules\GV_Product_Business_Validation.validationRule-meta.xml: true; AND(
    Active__c,
    ISBLANK(Product_Code__c)
)
- objects\Jewellery_Product__c\validationRules\GV_Product_Price_Validation.validationRule-meta.xml: true; OR(
    Price__c <= 0,
    AND(
        NOT(ISBLANK(Discount_Price__c)),
        OR(
            Discount_Price__c <= 0,
            Discount_Price__c >= Price__c
        )
    )
)
- objects\Jewellery_Product__c\validationRules\GV_Stock_Invariants.validationRule-meta.xml: true; OR(Stock_Quantity__c < 0,Reserved_Quantity__c < 0,Reserved_Quantity__c > Stock_Quantity__c,MOD(Stock_Quantity__c,1) <> 0,MOD(Reserved_Quantity__c,1) <> 0)
- objects\Jewellery_Product_Image__c\validationRules\GV_Product_Image_Validation.validationRule-meta.xml: true; AND(
    NOT(ISBLANK(Display_Order__c)),
    Display_Order__c < 0
)
- objects\Payment__c\validationRules\GV_No_New_COD.validationRule-meta.xml: true; AND(ISPICKVAL(Payment_Method__c,"COD"),OR(ISNEW(),ISCHANGED(Payment_Method__c)))
- objects\Payment__c\validationRules\GV_Payment_Validation.validationRule-meta.xml: true; OR(
    ISBLANK(Payment_Amount__c),
    Payment_Amount__c <= 0,
    AND(
        ISPICKVAL(Payment_Status__c, "Success"),
        ISBLANK(Transaction_ID__c)
    )
)
- objects\Product_Review__c\validationRules\GV_Product_Review_Validation.validationRule-meta.xml: true; OR(
    ISBLANK(Rating__c),
    Rating__c < 1,
    Rating__c > 5,
    ISBLANK(Review_Title__c)
)
- objects\Shopping_Cart__c\validationRules\GV_Shopping_Cart_Validation.validationRule-meta.xml: true; AND(
    NOT(ISBLANK(Total_Amount__c)),
    Total_Amount__c < 0
)
- objects\Stock_Reservation__c\validationRules\GV_Valid_Reservation_Quantity.validationRule-meta.xml: true; OR(
    ISBLANK(Reserved_Quantity__c),
    Reserved_Quantity__c <= 0,
    ISBLANK(Jewellery_Product__c)
)