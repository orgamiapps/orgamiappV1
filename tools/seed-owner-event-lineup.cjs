"use strict";
const fs=require("node:fs");
const path=require("node:path");
const crypto=require("node:crypto");
const req=require("node:module").createRequire(path.resolve(__dirname,"../functions/package.json"));
const {initializeApp}=req("firebase-admin/app");
initializeApp({projectId:"orgami-66nxok",storageBucket:"orgami-66nxok.appspot.com"});
const admin=require("../functions/firebase-admin-compat");
const {normalizeDraftForm,validatePublishable}=require("../functions/events/wizard-core");
const {eventDocument}=require("../functions/events/wizard");
const {CATEGORY_BY_ID}=require("../functions/discovery/category-catalog");
const {geohashForLocation}=req("geofire-common");
const {forms}=require("./event-lineup-20260926.cjs");
const uid=process.env.ATTENDUS_LINEUP_OWNER_UID,email=process.env.ATTENDUS_LINEUP_OWNER_EMAIL,batchId="portcity-lineup-20260926";
const out=path.resolve(__dirname,"../.firebase/event-lineup-20260926");
const db=admin.firestore();
async function main(){
  if(!uid||!email)throw Error("Explicit ATTENDUS_LINEUP_OWNER_UID and ATTENDUS_LINEUP_OWNER_EMAIL are required");
  const account=await admin.auth().getUser(uid);
  if(account.email!==email||account.disabled)throw Error("Owner mismatch");
  fs.mkdirSync(out,{recursive:true});
  const frozenForms=path.join(out,"event-forms.json");
  const specs=fs.existsSync(frozenForms)?JSON.parse(fs.readFileSync(frozenForms)):forms();
  if(!fs.existsSync(frozenForms))fs.writeFileSync(frozenForms,JSON.stringify(specs,null,2));
  if(new Set(specs.map(e=>e.category)).size!==10)throw Error("Category collision");
  const plans=specs.map(e=>{
    const asset=path.resolve(__dirname,`../images/event-lineup-20260926/${e.key}.png`);
    const bytes=fs.readFileSync(asset);
    const sha256=crypto.createHash("sha256").update(bytes).digest("hex");
    const object=`events_images/${batchId}/${e.key}-${sha256.slice(0,12)}.png`;
    const token=crypto.createHash("sha256").update(batchId+object).digest("hex");
    const imageUrl=`https://firebasestorage.googleapis.com/v0/b/orgami-66nxok.appspot.com/o/${encodeURIComponent(object)}?alt=media&token=${token}`;
    const form=normalizeDraftForm({...e.form,imageUrl});
    const errors=validatePublishable(form);
    const words=form.description.trim().split(/\s+/).length;
    if(errors.length||words<150||words>250||!CATEGORY_BY_ID.has(e.category))throw Error(JSON.stringify({key:e.key,errors,words}));
    const doc=eventDocument(admin,form,{uid,eventId:e.eventId,groupName:"Paul Reisinger",authorName:"Paul Reisinger",authorRole:"organizer",
      createdAt:admin.firestore.Timestamp.now(),status:"scheduled",eventRevision:1});
    Object.assign(doc,{seedBatchId:batchId,categories:CATEGORY_BY_ID.get(e.category).legacy,
      discoveryLocationValid:!!e.place,geohash:e.place?geohashForLocation([form.latitude,form.longitude]):null});
    return {eventId:e.eventId,asset,object,sha256,token,words,form,doc};
  });
  const preview=plans.map(p=>({eventId:p.eventId,title:p.form.title,category:p.form.primaryDiscoveryCategoryId,start:p.form.startAt,mode:p.form.registration.mode,words:p.words,object:p.object,sha256:p.sha256}));
  fs.writeFileSync(path.join(out,"creation-manifest.json"),JSON.stringify({batchId,uid,email,createdAt:new Date().toISOString(),events:preview},null,2));
  console.log(JSON.stringify(preview,null,2));
  if(!process.argv.includes("--apply"))return;
  const beforeFile=path.join(out,"publication-before.json");
  if(!fs.existsSync(beforeFile)){
    const events=await db.collection("Events").get();
    const customer=await db.doc(`Customers/${uid}`).get();
    const subscription=await db.doc(`subscriptions/${uid}`).get();
    const entitlement=await db.doc(`account_entitlements/${uid}`).get();
    fs.writeFileSync(beforeFile,JSON.stringify({events:events.docs.map(d=>({id:d.id,data:d.data()})),customer:customer.data(),subscription:subscription.data()||null,entitlement:entitlement.data()||null},null,2));
  }
  const bucket=admin.storage().bucket();
  for(const p of plans){
    const file=bucket.file(p.object);
    const [exists]=await file.exists();
    if(!exists)await bucket.upload(p.asset,{destination:p.object,preconditionOpts:{ifGenerationMatch:0},metadata:{contentType:"image/png",cacheControl:"public,max-age=31536000,immutable",metadata:{firebaseStorageDownloadTokens:p.token,seedBatchId:batchId,sha256:p.sha256}}});
    else {const [m]=await file.getMetadata();if(m.metadata?.sha256!==p.sha256)throw Error("Existing media mismatch");}
  }
  await db.runTransaction(async tx=>{
    const refs=plans.map(p=>db.doc(`Events/${p.eventId}`));
    const existing=await tx.getAll(...refs);
    const ent=await tx.get(db.doc(`account_entitlements/${uid}`));
    existing.forEach((s,i)=>{if(s.exists&&(s.get("seedBatchId")!==batchId||s.get("customerUid")!==uid))throw Error("Event ID collision: "+plans[i].eventId);});
    tx.set(ent.ref,{unlimitedEventCreation:true,grantedAt:ent.get("grantedAt")||admin.firestore.FieldValue.serverTimestamp(),grantReason:"Owner-requested permanent event creation allowance",updatedAt:admin.firestore.FieldValue.serverTimestamp()},{merge:true});
    plans.forEach((p,i)=>{if(!existing[i].exists)tx.create(refs[i],p.doc);});
  });
  const result=await db.getAll(...plans.map(p=>db.doc(`Events/${p.eventId}`)));
  if(result.length!==10||result.some(d=>!d.exists||d.get("customerUid")!==uid))throw Error("Verification mismatch");
  fs.writeFileSync(path.join(out,"publication-result.json"),JSON.stringify({batchId,uid,completedAt:new Date().toISOString(),events:result.map(d=>({id:d.id,title:d.get("title"),url:`https://attendus.app/event/${d.id}`}))},null,2));
  console.log("Published and verified all ten events and the owner entitlement.");
}
main().catch(e=>{console.error(e.message);process.exitCode=1;});
