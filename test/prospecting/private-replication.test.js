import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm, readFile } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { tmpdir } from 'node:os';
import { createRequire } from 'node:module';
import { createRetentionPeer } from '../../../influence-server/src/private-data/peer.mjs';
import { createPrivateDataTransport } from '../../../influence-client/src/lib/privateData/transport.mjs';
const { Encryption, PrivateData } = createRequire(resolve('../influence-client/package.json'))('@influenceth/sdk');
const seed = n => new Uint8Array(32).fill(n);
const pause = () => new Promise(resolve => setTimeout(resolve, 50));
async function eventually(fn) {
  for (let i=0;i<120;i++) { const result=await fn(); if(result)return result; await pause(); }
  throw new Error('Replication did not converge');
}

test('actual client authorizes stack replication, retains partial acknowledgments and recovers from the surviving stack', { timeout: 45000 }, async () => {
  const directory = await mkdtemp(join(tmpdir(),'influence-client-replication-'));
  let first, second, transport;
  try {
    const key = await Encryption.generatePrivateKeyFromSeed('client-stack-replication');
    const publicKey = Encryption.getPublicKeyFromPrivateKey(key), scope='campaign-123';
    second=await createRetentionPeer({directory:join(directory,'b'),seed:seed(82),listen:['/ip4/127.0.0.1/tcp/0/ws']});
    const address=second.getMultiaddrs()[0].toString(), listen=address.split('/p2p/')[0];
    await second.stop();second=null;
    first=await createRetentionPeer({directory:join(directory,'a'),seed:seed(81),listen:['/ip4/127.0.0.1/tcp/0/ws'],replicationPeers:[address],replicationIntervalMs:50});
    transport=await createPrivateDataTransport({privateKey:key,peers:[first.getMultiaddrs()[0].toString(),address]});
    const envelope=async revision=>({scope,revision,updatedAt:revision,remoteRevision:0,
      ciphertext:await PrivateData.encryptRecord(publicKey,{privateVein:revision})});
    await assert.rejects(transport.put(await envelope(1)));
    // The global backup base is still zero, but the healthy peer's receipt must
    // let the next revision advance without losing its first successful write.
    await assert.rejects(transport.put(await envelope(2)));
    const id=await PrivateData.recordId(key,scope);
    const stored=JSON.parse(await readFile(join(directory,'a',`${id}.json`),'utf8'));
    assert.equal(stored.record.revision,2);
    assert(stored.replication.peers.includes(first.peerId.toString()));
    second=await createRetentionPeer({directory:join(directory,'b'),seed:seed(82),listen:[listen]});
    await eventually(async()=>{
      try{return JSON.parse(await readFile(join(directory,'b',`${id}.json`),'utf8')).record.revision===2;}
      catch(error){if(error.code==='ENOENT')return false;throw error;}
    });
    // B reached revision 2 via A, without acknowledging it to this browser.
    // Discovering that exact known signed head permits a safe CAS retry.
    await transport.put(await envelope(3));
    await transport.stop();transport=null;
    await first.stop();first=null;
    transport=await createPrivateDataTransport({privateKey:key,peers:[address]});
    const restored=await transport.get(scope,publicKey);
    assert.equal(restored.revision,3);
    assert.deepEqual(await PrivateData.decryptRecord(key,scope,restored),{privateVein:3});
    const anotherDevice=await createPrivateDataTransport({privateKey:key,peers:[address]});
    try {
      await anotherDevice.get(scope,publicKey);
      await anotherDevice.put(await envelope(4));
      await assert.rejects(transport.put(await envelope(5)),/revision conflict/);
      assert.equal((await anotherDevice.get(scope,publicKey)).revision,4);
    }finally{await anotherDevice.stop();}
  }finally{
    await transport?.stop();await first?.stop();await second?.stop();await rm(directory,{recursive:true,force:true});
  }
});
