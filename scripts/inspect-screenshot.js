const fs=require("fs"),zlib=require("zlib");
function decode(path){
  const data=fs.readFileSync(path);
  let pos=8,idat=[],w=0,h=0,ct=0;
  while(pos<data.length){
    const ln=data.readUInt32BE(pos);const typ=data.toString("ascii",pos+4,pos+8);
    if(typ==="IHDR"){w=data.readUInt32BE(pos+8);h=data.readUInt32BE(pos+12);ct=data[pos+17];}
    else if(typ==="IDAT")idat.push(data.subarray(pos+8,pos+8+ln));
    pos+=12+ln;
  }
  const raw=zlib.inflateSync(Buffer.concat(idat));
  const bpp=ct===6?4:3,stride=w*bpp;const out=Buffer.alloc(h*stride);
  let prev=Buffer.alloc(stride),i=0;
  for(let y=0;y<h;y++){
    const ft=raw[i++];const line=Buffer.from(raw.subarray(i,i+stride));i+=stride;
    if(ft===1){for(let x=bpp;x<stride;x++)line[x]=(line[x]+line[x-bpp])&255;}
    else if(ft===2){for(let x=0;x<stride;x++)line[x]=(line[x]+prev[x])&255;}
    else if(ft===3){for(let x=0;x<stride;x++){const a=x>=bpp?line[x-bpp]:0;line[x]=(line[x]+((a+prev[x])>>1))&255;}}
    else if(ft===4){for(let x=0;x<stride;x++){const a=x>=bpp?line[x-bpp]:0,b=prev[x],c=x>=bpp?prev[x-bpp]:0;
      const p=a+b-c,pa=Math.abs(p-a),pb=Math.abs(p-b),pc=Math.abs(p-c);
      line[x]=(line[x]+(pa<=pb&&pa<=pc?a:(pb<=pc?b:c)))&255;}}
    line.copy(out,y*stride);prev=line;
  }
  return {w,h,bpp,px:out};
}
// 逐行统计「与该行主色不同的像素比例」= 该行有多少内容
for(const f of ["home-dark.png","home-light.png","now-playing.png"]){
  const {w,h,bpp,px}=decode(f);
  console.log("=== "+f+" ===");
  const band=Math.floor(h/26);
  for(let b=0;b<26;b++){
    const y0=b*band, y1=Math.min(h,(b+1)*band);
    const counts=new Map();
    for(let y=y0;y<y1;y+=4)for(let x=0;x<w;x+=4){
      const i=(y*w+x)*bpp;
      const k=`${px[i]},${px[i+1]},${px[i+2]}`;
      counts.set(k,(counts.get(k)||0)+1);
    }
    const total=[...counts.values()].reduce((a,c)=>a+c,0);
    const sorted=[...counts.entries()].sort((a,b)=>b[1]-a[1]);
    const dom=sorted[0];
    const ink=Math.round((1-dom[1]/total)*100);
    const bar="#".repeat(Math.round(ink/2.5));
    console.log(String(y0).padStart(4)+" 内容"+String(ink).padStart(3)+"% "+bar.padEnd(40)+" 底色 rgb("+dom[0]+")");
  }
}
