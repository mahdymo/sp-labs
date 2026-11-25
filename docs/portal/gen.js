const fs=require('fs'),P=require('path'),O=P.join(__dirname,'index.html');
fs.writeFileSync(O,'','utf8');
const a=s=>fs.appendFileSync(O,s,'utf8');
const nf=(id,x,y,w,h,l,s,f,z)=>{z=z||10.5;return`<g data-nf="${id}"><rect x="${x}" y="${y}" width="${w}" height="${h}" rx="6" fill="#1e293b" stroke="${s}" stroke-width="1.3"/><text x="${x+w/2|0}" y="${y+h/2+4|0}" text-anchor="middle" fill="${f}" font-size="${z}" font-weight="700">${l}</text></g>\n`};
const ln=(a1,b,c,d,col,sw,cls,me)=>`<line x1="${a1}" y1="${b}" x2="${c}" y2="${d}" stroke="${col}" stroke-width="${sw||1.5}"${cls?` class="${cls}"`:''}${me?` marker-end="url(#${me})"`:''}/>\n`;
const tx=(x,y,t,c,z,fw,an)=>`<text x="${x}" y="${y}" fill="${c}" font-size="${z||8.5}" font-weight="${fw||600}" text-anchor="${an||'middle'}">${t}</text>\n`;
module.exports={a,nf,ln,tx,O};
