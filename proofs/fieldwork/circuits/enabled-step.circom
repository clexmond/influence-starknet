pragma circom 2.2.0;
include "poseidon2.circom";
include "../node_modules/circomlib/circuits/bitify.circom";
include "../node_modules/circomlib/circuits/comparators.circom";

template Div(B,D) {
 signal input in; signal output q; signal output r;
 q <-- in\D; r <-- in%D;
 component qb=Num2Bits(B); qb.in <== q;
 component rb=Num2Bits(B); rb.in <== r;
 component bound=LessThan(B); bound.in[0]<==r; bound.in[1]<==D; bound.out===1;
 in===q*D+r;
}
template Pick(N,W) {
 signal input index; signal input rows[N][W]; signal output out[W];
 signal output matches[N]; signal terms[W][N]; var count=0;
 for(var i=0;i<N;i++){matches[i]<==IsEqual()([index,i]);count+=matches[i];}
 count===1;
 for(var j=0;j<W;j++){var sum=0;for(var i=0;i<N;i++){terms[j][i]<==matches[i]*rows[i][j];sum+=terms[j][i];}out[j]<==sum;}
}
template Meta() {
 signal input in; signal output lot; signal output x; signal output z; signal output abundance;
 component bits=Num2Bits(81);bits.in<==in;
 var l=0;var xx=0;var zz=0;var a=0;
 for(var i=0;i<21;i++)l+=bits.out[i]*(2**i);
 for(var i=0;i<20;i++){xx+=bits.out[21+i]*(2**i);zz+=bits.out[41+i]*(2**i);a+=bits.out[61+i]*(2**i);}
 lot<==l;x<==xx;z<==zz;abundance<==a;
 signal valid <== LessThan(21)([abundance,1000001]);valid===1;
}
template EnabledStep(N,I) {
 signal input enabled; signal input context; signal input origin; signal input quality; signal input meta; signal input blockedApproaches;
 signal input commitment; signal input randomness;
 signal input method; signal input target; signal input source; signal input depth; signal input salt;
 signal input prev[N][15]; signal input history[N][5];
 signal output next[N][15]; signal output event; signal output edge[5];
 component m=Meta();m.in<==meta;
 signal f <== IsEqual()([method,0]);signal c <== IsEqual()([method,1]);signal a <== IsEqual()([method,2]);
 signal follow <== enabled*f;signal cross <== enabled*c;signal assay <== enabled*a;
 follow+cross+assay===enabled;
 component depthBits=Num2Bits(3);depthBits.in<==depth;
 signal depthOK <== LessThan(3)([depth,5]);depthOK===1;
 component src=Pick(N,15);src.index<==source;src.rows<==prev;
 component dst=Pick(N,15);dst.index<==target;dst.rows<==prev;
 // One authenticated far/near bit per earlier core replaces full distances.
 component db=Num2Bits(N);db.in<==blockedApproaches;
 signal distanceRows[N][1];
 for(var j=0;j<N;j++){distanceRows[j][0]<==db.out[j];}
 component selectedDistance=Pick(N,1);selectedDistance.index<==source;selectedDistance.rows<==distanceRows;
 var knownSum=0;for(var j=0;j<N;j++)knownSum+=prev[j][0];
 signal none <== IsZero()(knownSum); signal any <== 1-none;
 signal initial <== follow*(1-any);
 initial*(m.lot-origin)===0;
 follow*(target-I)===0;
 signal later <== follow*any;later*(1-src.out[0])===0;
 signal near <== 1-selectedDistance.out[0];later*(1-near)===0;
 signal depthNearLow <== LessThan(4)([depth+1,src.out[2]]);
 signal depthNearHigh <== LessThan(4)([src.out[2]+1,depth]);
 later*depthNearLow===0;later*depthNearHigh===0;
 signal duplicateLot[N];signal duplicateDepth[N];signal duplicate[N];signal duplicateKnown[N];
 signal edgeA[N][4];signal edgeB[N][4];signal ea[N][3];signal eb[N][3];signal blocked[N];
 for(var j=0;j<N;j++){
  duplicateLot[j]<==IsEqual()([prev[j][1],m.lot]);duplicateDepth[j]<==IsEqual()([prev[j][2],depth]);
  duplicate[j]<==duplicateLot[j]*duplicateDepth[j];duplicateKnown[j]<==duplicate[j]*prev[j][0];follow*duplicateKnown[j]===0;
  edgeA[j][0]<==IsEqual()([history[j][1],src.out[1]]);edgeA[j][1]<==IsEqual()([history[j][2],src.out[2]]);
  edgeA[j][2]<==IsEqual()([history[j][3],m.lot]);edgeA[j][3]<==IsEqual()([history[j][4],depth]);
  edgeB[j][0]<==IsEqual()([history[j][1],m.lot]);edgeB[j][1]<==IsEqual()([history[j][2],depth]);
  edgeB[j][2]<==IsEqual()([history[j][3],src.out[1]]);edgeB[j][3]<==IsEqual()([history[j][4],src.out[2]]);
  ea[j][0]<==edgeA[j][0]*edgeA[j][1];ea[j][1]<==edgeA[j][2]*edgeA[j][3];ea[j][2]<==ea[j][0]*ea[j][1];
  eb[j][0]<==edgeB[j][0]*edgeB[j][1];eb[j][1]<==edgeB[j][2]*edgeB[j][3];eb[j][2]<==eb[j][0]*eb[j][1];
  blocked[j]<==history[j][0]*(ea[j][2]+eb[j][2]);later*blocked[j]===0;
 }
 signal measurement <== cross+assay;
 measurement*(1-dst.out[0])===0;
 signal barren <== IsZero()(dst.out[3]);measurement*barren===0;
 measurement*(dst.out[1]-m.lot)===0;measurement*(dst.out[2]-depth)===0;
 cross*dst.out[7]===0;assay*dst.out[8]===0;
 component action=Hash(8);action.in[0]<==7001;action.in[1]<==context;action.in[2]<==I;action.in[3]<==method;
 action.in[4]<==target;action.in[5]<==source;action.in[6]<==depth;action.in[7]<==salt;enabled*(action.out-commitment)===0;
 component rb=Num2Bits(64);rb.in<==randomness;
 component entropy=Hash(6);entropy.in[0]<==7002;entropy.in[1]<==context;entropy.in[2]<==I;entropy.in[3]<==commitment;entropy.in[4]<==randomness;entropy.in[5]<==salt;
 component bits=Num2Bits_strict();bits.in<==entropy.out;
 signal words[7];component rolls[7];
 for(var k=0;k<7;k++){var word=0;for(var j=0;j<32;j++)word+=bits.out[32*k+j]*(2**j);words[k]<==word;rolls[k]=Div(39,4294967296);rolls[k].in<==word*100;}
 signal sourceZero <== IsZero()(src.out[3]);signal sourceNonzero <== 1-sourceZero;signal productive <== sourceNonzero*src.out[0];
 signal stuck <== LessThan(7)([rolls[0].q,5]);signal collapseRoll <== LessThan(7)([rolls[0].q,10]);
 signal followProductive <== follow*productive;
 signal collapseCandidate <== followProductive*collapseRoll;
 signal collapse <== collapseCandidate*(1-stuck);
 signal caveRoll <== LessThan(7)([rolls[0].q,13]);signal caveCandidate <== cross*caveRoll;
 signal cave <== caveCandidate*(1-stuck);
 event<==enabled*(stuck+2*collapse+3*cave);
 edge[0]<==collapse;edge[1]<==src.out[1];edge[2]<==src.out[2];edge[3]<==m.lot;edge[4]<==depth;
 signal success <== 1-stuck-collapse;
 signal newCell <== follow*success;
 var dirs[16][2]=[[1000,0],[1000,414],[707,707],[414,1000],[0,1000],[-414,1000],[-707,707],[-1000,414],[-1000,0],[-1000,-414],[-707,-707],[-414,-1000],[0,-1000],[414,-1000],[707,-707],[1000,-414]];
 component heading=Pick(16,2);heading.index<==src.out[5];
 for(var j=0;j<16;j++)for(var k=0;k<2;k++)heading.rows[j][k]<==dirs[j][k];
 signal dx<==m.x-src.out[13];signal dz<==m.z-src.out[14];
 signal dotX<==dx*heading.out[0];signal dotZ<==dz*heading.out[1];signal dot<==dotX+dotZ;
 signal dxx<==dx*dx;signal dzz<==dz*dz;signal hxx<==heading.out[0]*heading.out[0];signal hzz<==heading.out[1]*heading.out[1];
 signal normProduct<==(dxx+dzz)*(hxx+hzz);signal fourDotSquared<==4*dot*dot;
 signal negative<==LessThan(33)([dot+4294967296,4294967296]);signal positive<==1-negative;
 signal outsideCone<==LessThan(85)([fourDotSquared,normProduct]);signal inCone<==1-outsideCone;signal cone<==positive*inCone;
 signal sameLot<==IsEqual()([m.lot,src.out[1]]);signal aligned<==sameLot+(1-sameLot)*cone;
 signal sameDepth<==IsEqual()([depth,src.out[6]]);signal informed<==400000+aligned*(150000+200000*sameDepth);
 component fraction=Div(22,5);fraction.in<==2*m.abundance;
 signal chance<==200000+fraction.q+productive*(informed-200000-fraction.q);
 signal hit<==LessThan(53)([words[1]*1000000,chance*4294967296]);
 signal lowGrade<==LessThan(7)([rolls[2].q,50]);signal middleGrade<==LessThan(7)([rolls[2].q,85]);
 signal stay<==LessThan(7)([rolls[2].q,70]);signal improve<==middleGrade-stay;
 signal maxGrade<==IsEqual()([src.out[3],3]);signal minGrade<==IsEqual()([src.out[3],1]);
 signal up<==improve*(1-maxGrade);signal down<==(1-middleGrade)*(1-minGrade);
 signal inherited<==src.out[3]+up-down;
 signal fresh<==3-lowGrade-middleGrade;
 signal gradeIfHit<==fresh+productive*(inherited-fresh);signal grade<==hit*gradeIfHit;
 signal clueLow<==LessThan(7)([rolls[3].q,40]);signal clueMid<==LessThan(7)([rolls[3].q,70]);signal clue<==2-clueLow-clueMid;
 component bearing=Div(32,16);bearing.in<==words[5];component drift=Div(32,3);drift.in<==words[6];
 signal depthUnclamped<==depth+drift.r;signal bottom<==IsEqual()([depthUnclamped,0]);signal top<==IsEqual()([depthUnclamped,6]);
 signal nextDepth<==depthUnclamped-1+bottom-top;
 var table[3][10]=[[15,60,100,200,350,65,95,0,15,35],[60,95,100,150,200,15,60,0,55,110],[35,85,100,180,250,35,85,0,30,60]];
 component distribution=Pick(3,10);distribution.index<==dst.out[4];for(var j=0;j<3;j++)for(var k=0;k<10;k++)distribution.rows[j][k]<==table[j][k];
 signal wl<==LessThan(7)([rolls[4].q,distribution.out[0]]);signal wm<==LessThan(7)([rolls[4].q,distribution.out[1]]);
 signal wlow<==wl*(distribution.out[2]-distribution.out[3]);signal wmid<==wm*(distribution.out[3]-distribution.out[4]);
 signal width<==distribution.out[4]+wlow+wmid;
 signal hl<==LessThan(7)([rolls[4].q,distribution.out[5]]);signal hm<==LessThan(7)([rolls[4].q,distribution.out[6]]);
 signal hlow<==hl*(distribution.out[7]-distribution.out[8]);signal hmid<==hm*(distribution.out[8]-distribution.out[9]);
 signal bonus<==distribution.out[9]+hlow+hmid;
 signal crossOK<==cross*success;signal assayOK<==assay*success;
 signal widthResult<==width+cave*(100-width);
 signal newRow[15];newRow[0]<==1;newRow[1]<==m.lot;newRow[2]<==depth;newRow[3]<==grade;newRow[4]<==clue;newRow[5]<==bearing.r;newRow[6]<==nextDepth;
 newRow[7]<==0;newRow[8]<==0;newRow[9]<==100;newRow[10]<==0;newRow[11]<==100;newRow[12]<==quality;newRow[13]<==m.x;newRow[14]<==m.z;
 signal crossAt[N];signal assayAt[N];signal caveAt[N];signal afterMeasure[N][15];
 for(var j=0;j<N;j++){
  crossAt[j]<==dst.matches[j]*crossOK;assayAt[j]<==dst.matches[j]*assayOK;caveAt[j]<==dst.matches[j]*cave;
  for(var k=0;k<15;k++){
   if(k==7)afterMeasure[j][k]<==prev[j][k]+crossAt[j];
   else if(k==8)afterMeasure[j][k]<==prev[j][k]+assayAt[j];
   else if(k==9)afterMeasure[j][k]<==prev[j][k]+crossAt[j]*(widthResult-prev[j][k]);
   else if(k==10)afterMeasure[j][k]<==prev[j][k]+assayAt[j]*(bonus-prev[j][k]);
   else if(k==11)afterMeasure[j][k]<==prev[j][k]-20*caveAt[j];
   else afterMeasure[j][k]<==prev[j][k];
   if(j==I)next[j][k]<==afterMeasure[j][k]+newCell*(newRow[k]-afterMeasure[j][k]);
   else next[j][k]<==afterMeasure[j][k];
  }
 }
}
