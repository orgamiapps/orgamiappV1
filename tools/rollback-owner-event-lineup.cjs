"use strict";
// Dry run by default. --apply removes only this manifest's event data/media.
const fs=require("node:fs"),path=require("node:path");
const req=require("node:module").createRequire(path.resolve(__dirname,"../functions/package.json"));
const {initializeApp}=req("firebase-admin/app");
const {getFirestore}=req("firebase-admin/firestore");
const {getStorage}=req("firebase-admin/storage");
initializeApp({projectId:"orgami-66nxok",storageBucket:"orgami-66nxok.appspot.com"});
const dir=path.resolve(__dirname,"../.firebase/event-lineup-20260926");
const manifest=JSON.parse(fs.readFileSync(path.join(dir,"creation-manifest.json")));
const ids=manifest.events.map(e=>e.eventId);
const db=getFirestore();
async function main(){
  const selected=new Map();
  for(const c of await db.listCollections()){
    if(["Customers","users","subscriptions","account_entitlements","admin_audit_logs"].includes(c.id))continue;
    for(const field of ["eventId","data.eventId"]){
      for(const d of (await c.where(field,"in",ids).get()).docs)selected.set(d.ref.path,d.ref);
    }
  }
  for(const collection of ["Events","PublicWebEvents","event_analytics","check_in_event_state"]){
    for(const id of ids){const ref=db.collection(collection).doc(id);if((await ref.get()).exists)selected.set(ref.path,ref);}
  }
  for(const user of (await db.collection("users").get()).docs){
    for(const field of ["eventId","data.eventId"]){
      for(const d of (await user.ref.collection("notifications").where(field,"in",ids).get()).docs)selected.set(d.ref.path,d.ref);
    }
  }
  const batches=(await db.collection("discovery_notification_batches").get()).docs
      .filter(d=>(d.get("eventIds")||[]).some(id=>ids.includes(id)));
  const plan={project:"orgami-66nxok",batchId:manifest.batchId,documents:[...selected.keys()],
    notificationBatches:batches.map(d=>d.id),media:manifest.events.map(e=>e.object),
    entitlement:"Preserved; revoke separately if requested. Already delivered notifications cannot be recalled."};
  fs.writeFileSync(path.join(dir,"rollback-plan.json"),JSON.stringify(plan,null,2));
  console.log(JSON.stringify(plan,null,2));
  if(!process.argv.includes("--apply"))return;
  for(const id of ids){const event=await db.doc(`Events/${id}`).get();if(event.exists&&(event.get("seedBatchId")!==manifest.batchId||event.get("customerUid")!==manifest.uid))throw Error("Scope mismatch");}
  for(const batch of batches){
    await db.runTransaction(async tx=>{
      const current=await tx.get(batch.ref);
      const remaining=(current.get("eventIds")||[]).filter(id=>!ids.includes(id));
      if(!remaining.length){tx.delete(batch.ref);return;}
      const events=await tx.getAll(...remaining.map(id=>db.doc(`Events/${id}`)));
      tx.update(batch.ref,{eventIds:remaining,eventTitles:events.filter(d=>d.exists).map(d=>d.get("title"))});
    });
  }
  for(const ref of selected.values())await db.recursiveDelete(ref);
  const bucket=getStorage().bucket();
  for(const event of manifest.events){
    if(!event.object.startsWith(`events_images/${manifest.batchId}/`))throw Error("Unexpected media path");
    await bucket.file(event.object).delete({ignoreNotFound:true});
  }
  console.log("Batch removed. Re-run the dry run after triggers settle to check residual references.");
}
main().catch(e=>{console.error(e.message);process.exitCode=1;});
