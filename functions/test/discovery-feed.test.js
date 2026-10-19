const test = require("node:test");
const assert = require("node:assert/strict");
const {Timestamp} = require("firebase-admin/firestore");
const {discoveryFeed, exactDistance} = require("../discovery/feed");
const {activePublicEvent, eventDto, applyV2Filters} = require("../discovery/marketplace");
const helpers = {activePublicEvent, eventDto, applyV2Filters,
  validateCenter: d => ({latitude:d.latitude, longitude:d.longitude}),
  includesQuery: (e,q) => e.title.toLowerCase().includes(q)};
const base = {latitude: 40, longitude: -75, distanceMode:"auto"};
function event(id, fields={}) {return {id:String(id).padStart(5,"0"), data:()=>({
  private:false, status:"active", title:"Music", countryCode:"US",
  selectedDateTime:Timestamp.fromMillis(Date.now()+86400000), latitude:40, longitude:-75,
  ...fields})};}
function database(docs) {
  // Model Firestore's timestamp/document-id ordering and keyset continuation.
  const rows = docs.map(d => ({id:d.id, value:d.data()})).sort((a,b) =>
    a.value.selectedDateTime.valueOf().localeCompare(b.value.selectedDateTime.valueOf()) || a.id.localeCompare(b.id));
  return {collection:()=>{
    let after = null; let count = 200;
    const q = {where:()=>q, orderBy:()=>q, limit:n=>(count=n,q),
      startAfter:(date,id)=>(after=[date.valueOf(),id],q),
      get:async()=>({docs:rows.filter(r=>!after || r.value.selectedDateTime.valueOf()>after[0] ||
        (r.value.selectedDateTime.valueOf()===after[0] && r.id>after[1])).slice(0,count)
        .map(r=>({id:r.id,data:()=>r.value}))})}; return q;
  }};
}
async function page(db, filters, cursor) {
  let result; const events=[];
  do {result=await discoveryFeed(db,{...filters,cursor,limit:20-events.length},helpers);
    events.push(...result.events); cursor=result.nextCursor;
  } while(cursor && events.length<20);
  return {...result,events};
}
test("pagination passes old caps with stable ties and no duplicate IDs",async()=>{
  const when=Timestamp.fromMillis(Date.now()+86400000);
  const db=database(Array.from({length:1105},(_,i)=>event(i,{selectedDateTime:when})));
  const seen=[];let cursor;
  do {const result=await page(db,{...base,distanceMode:"fixed",radiusMiles:25},cursor);
    seen.push(...result.events.map(e=>e.id));cursor=result.nextCursor;
  }while(cursor);
  assert.equal(seen.length,1105);assert.equal(new Set(seen).size,1105);
  assert.deepEqual(seen,[...seen].sort());
});
test("auto expands to each band and then nationwide; online does not count",async()=>{
  for(const [miles,expected] of [[10,25],[35,50],[70,100],[150,250],[300,500],[700,1000],[1200,null]]) {
    const latitude=40+miles/69.0934;
    const db=database([...Array.from({length:6},(_,i)=>event(i,{latitude})),
      ...Array.from({length:8},(_,i)=>event(100+i,{locationType:"online"}))]);
    const result=await page(db,base);
    assert.equal(result.radiusMiles,expected);assert.equal(result.events.length,14);
  }
  const result=await page(database([event(1),event(2,{locationType:"online"})]),base);
  assert.equal(result.radiusMiles,null);
});
test("fixed distance includes online, rejects no-pin text and exact boundary overflow",async()=>{
  const far={latitude:40.1,longitude:-75};
  const db=database([event(1),event(2,far),event(3,{locationType:"online"}),
    event(4,{locationInputMode:"text"}),event(5,{locationInputMode:"text",locationCoordinatesEnabled:true})]);
  const result=await page(db,{...base,distanceMode:"fixed",radiusMiles:5});
  assert.deepEqual(result.events.map(e=>e.id),["00001","00003","00005"]);
  assert.ok(exactDistance(far,helpers.validateCenter(base))>5);
  const nationwide=await page(db,{...base,nationwide:true});assert.equal(nationwide.events.length,5);
  await assert.rejects(()=>page(db,{...base,nationwide:true,distanceMode:"fixed",radiusMiles:25}),/location/);
});
test("cursor cannot be reused with changed filters or distance",async()=>{
  const db=database(Array.from({length:30},(_,i)=>event(i)));
  const result=await page(db,base);
  await assert.rejects(()=>page(db,{...base,freeOnly:true},result.nextCursor),/cursor/);
});
test("sparse matching events beyond scan window remain reachable and auto freezes scope",async()=>{
  const db=database([...Array.from({length:1200},(_,i)=>event(i,{title:"Other"})),
    ...Array.from({length:26},(_,i)=>event(i+1200))]);
  const first=await page(db,{...base,query:"music"});
  assert.equal(first.events.length,20);assert.equal(first.radiusMiles,25);
  const second=await page(db,{...base,query:"music"},first.nextCursor);
  assert.equal(second.events.length,6);assert.equal(second.radiusMiles,25);
});

test("sub-millisecond timestamps remain distinct across page boundaries",async()=>{
  const seconds=Math.floor(Date.now()/1000)+86400;
  const db=database(Array.from({length:21},(_,i)=>event(i,{selectedDateTime:new Timestamp(seconds,i)})));
  const first=await page(db,{...base,distanceMode:"fixed",radiusMiles:25});
  const second=await page(db,{...base,distanceMode:"fixed",radiusMiles:25},first.nextCursor);
  assert.equal(first.events.length,20);assert.equal(second.events.length,1);
  assert.equal(second.events[0].id,"00020");assert.equal(second.nextCursor,null);
});
test("Online and price filters apply before automatic radius resolution",async()=>{
  const db=database([event(1,{locationType:"online",countryCode:"CA"}),
    event(2,{locationType:"online",ticketsEnabled:true,ticketPrice:10}),event(3)]);
  const result=await page(db,{...base,onlineOnly:true,freeOnly:true});
  assert.deepEqual(result.events.map(e=>e.id),["00001"]);
  assert.equal(result.radiusMiles,null);
});

test("fixed boundary uses full precision rather than rounded display miles",async()=>{
  let low=40;let high=41;
  for(let i=0;i<60;i++) {
    const middle=(low+high)/2;
    if(exactDistance({latitude:middle,longitude:-75},helpers.validateCenter(base))<5) low=middle;
    else high=middle;
  }
  const db=database([event(1,{latitude:low-0.000001}),event(2,{latitude:high+0.000001})]);
  const result=await page(db,{...base,distanceMode:"fixed",radiusMiles:5});
  assert.deepEqual(result.events.map(e=>e.id),["00001"]);
});
