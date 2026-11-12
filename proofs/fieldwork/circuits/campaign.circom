pragma circom 2.2.0;
include "enabled-step.circom";

// Select the real transcript's final sponge block. This preserves the existing
// public digest and avoids sending or hashing padding in the Cairo verifier.
template PrefixHash(Max) {
 signal input in[Max]; signal input length; signal output out;
 var blocks=(Max+2)\3;
 signal state[blocks+1][4]; component perm[blocks]; component match[blocks]; signal term[blocks];
 component count=Div(5,3);count.in<==length+2;
 for(var j=0;j<3;j++)state[0][j]<==0;
 state[0][3]<==length*18446744073709551616;
 var sum=0;var matches=0;
 for(var b=0;b<blocks;b++) {
  perm[b]=Permutation();
  for(var j=0;j<4;j++) {
   if(j<3 && b*3+j<Max)perm[b].in[j]<==state[b][j]+in[b*3+j];
   else perm[b].in[j]<==state[b][j];
  }
  state[b+1]<==perm[b].out;
  match[b]=IsEqual();match[b].in[0]<==count.q;match[b].in[1]<==b+1;
  term[b]<==match[b].out*state[b+1][0];sum+=term[b];matches+=match[b].out;
 }
 matches===1;out<==sum;
}

template PaddedFieldwork(N,VolumeBps) {
 signal input context;signal input origin;signal input quality;signal input count;
 signal input meta[N];signal input blockedApproaches[N];signal input commitments[N];signal input randomness[N];
 signal input methods[N];signal input targets[N];signal input sources[N];signal input depths[N];signal input salts[N];signal input selected;
 signal output digest;
 component countBits=Num2Bits(4);countBits.in<==count;
 signal tooMany<==LessThan(4)([N,count]);tooMany===0;
 signal none<==IsZero()(count);none===0;
 component qb=Num2Bits(14);qb.in<==quality;signal qok<==LessThan(14)([quality,15001]);qok===1;
 signal state[N+1][N][15];signal history[N+1][N][5];component step[N];signal enabled[N];
 for(var j=0;j<N;j++){for(var k=0;k<15;k++)state[0][j][k]<==0;for(var k=0;k<5;k++)history[0][j][k]<==0;}
 for(var i=0;i<N;i++) {
  enabled[i]<==LessThan(4)([i,count]);
  (1-enabled[i])*meta[i]===0;(1-enabled[i])*blockedApproaches[i]===0;
  (1-enabled[i])*commitments[i]===0;(1-enabled[i])*randomness[i]===0;
  (1-enabled[i])*methods[i]===0;(1-enabled[i])*targets[i]===0;(1-enabled[i])*sources[i]===0;
  (1-enabled[i])*depths[i]===0;(1-enabled[i])*salts[i]===0;
  step[i]=EnabledStep(N,i);step[i].enabled<==enabled[i];
  step[i].context<==context;step[i].origin<==origin;step[i].quality<==quality;
  step[i].meta<==meta[i];step[i].blockedApproaches<==blockedApproaches[i];
  step[i].commitment<==commitments[i];step[i].randomness<==randomness[i];
  step[i].method<==methods[i];step[i].target<==targets[i];step[i].source<==sources[i];step[i].depth<==depths[i];step[i].salt<==salts[i];
  step[i].prev<==state[i];step[i].history<==history[i];state[i+1]<==step[i].next;
  for(var j=0;j<N;j++)for(var k=0;k<5;k++) {
   if(j==i)history[i+1][j][k]<==history[i][j][k]+enabled[i]*(step[i].edge[k]-history[i][j][k]);
   else history[i+1][j][k]<==history[i][j][k];
  }
 }
 component chosen=Pick(N,15);chosen.index<==selected;chosen.rows<==state[N];chosen.out[0]===1;
 signal validSelection<==LessThan(4)([selected,count]);validSelection===1;
 signal empty<==IsZero()(chosen.out[3]);empty===0;
 signal metaRows[N][1];for(var j=0;j<N;j++)metaRows[j][0]<==meta[j];
 component cm=Pick(N,1);cm.index<==selected;cm.rows<==metaRows;component chosenMeta=Meta();chosenMeta.in<==cm.out[0];
 signal amountA<==875*chosenMeta.abundance*(60+20*chosen.out[3]);signal amountB<==amountA*chosen.out[9];
 signal amountC<==amountB*chosen.out[11];signal amountD<==amountC*chosen.out[12];
 component quantity=Div(80,1000000000000);quantity.in<==amountD;
 component boosted=Div(48,10000);boosted.in<==quantity.q*VolumeBps;
 component ob=Num2Bits(21);ob.in<==origin;component amountBits=Num2Bits(32);amountBits.in<==boosted.q;
 component statement=PrefixHash(2+2*N);statement.length<==2+2*count;statement.in[0]<==context;
 statement.in[1]<==7003+count*(2**14)+quality*(2**18)+origin*(2**32)+chosen.out[1]*(2**53)+boosted.q*(2**74)+(90+chosen.out[10])*(2**106);
 for(var i=0;i<N;i++) {
  statement.in[2+2*i]<==meta[i]+randomness[i]*(2**81)+blockedApproaches[i]*(2**145);
  statement.in[3+2*i]<==commitments[i];
 }
 digest<==statement.out;
}
component main = PaddedFieldwork(10,15000);
