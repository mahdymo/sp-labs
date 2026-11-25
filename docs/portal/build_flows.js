module.exports=(a,ln,tx)=>{
a(`<div class="tc" id="tab-flows">
<div class="card"><div class="ct">UE Registration &amp; PDU Session Flow</div><div class="dw"><svg viewBox="0 0 1100 420" width="100%" style="display:block">
<defs><marker id="f1" markerWidth="7" markerHeight="5" refX="6" refY="2.5" orient="auto"><polygon points="0 0,7 2.5,0 5" fill="#8b5cf6"/></marker><marker id="f2" markerWidth="7" markerHeight="5" refX="6" refY="2.5" orient="auto"><polygon points="0 0,7 2.5,0 5" fill="#10b981"/></marker><marker id="f3" markerWidth="7" markerHeight="5" refX="6" refY="2.5" orient="auto"><polygon points="0 0,7 2.5,0 5" fill="#3b82f6"/></marker></defs>
<rect width="1100" height="420" fill="#0a0e17"/>
`);
// Column headers
const cols=[['UE',80,'#06b6d4'],['gNB',220,'#10b981'],['AMF',370,'#8b5cf6'],['AUSF',500,'#3b82f6'],['UDM',610,'#3b82f6'],['SMF',730,'#8b5cf6'],['UPF',860,'#10b981'],['BIG-IP',990,'#ef4444']];
cols.forEach(([n,x,c])=>{
  a(`<rect x="${x-30}" y="20" width="60" height="28" rx="6" fill="#1e293b" stroke="${c}" stroke-width="1.2"/>\n`);
  a(tx(x,39,n,c,10,700));
  a(`<line x1="${x}" y1="52" x2="${x}" y2="400" stroke="${c}" stroke-width=".6" opacity=".2"/>\n`);
});
// Registration steps
const steps=[
  [80,220,70,'1. RRC Setup','#06b6d4'],
  [220,370,90,'2. Registration Req (NAS)','#8b5cf6'],
  [370,500,110,'3. Auth Request','#3b82f6'],
  [500,610,130,'4. Get Auth Data','#3b82f6'],
  [610,500,150,'5. Auth Vector','#3b82f6'],
  [500,370,170,'6. Auth Response','#3b82f6'],
  [370,220,190,'7. Security Mode','#8b5cf6'],
  [220,80,210,'8. Security Complete','#06b6d4'],
  [370,220,230,'9. Registration Accept','#8b5cf6'],
];
steps.forEach(([x1,x2,y,label,c])=>{
  const dir=x2>x1?'f1':'f1';
  a(`<line x1="${x1}" y1="${y}" x2="${x2}" y2="${y}" stroke="${c}" stroke-width="1.3" marker-end="url(#${x2>x1?'f3':'f1'})"/>\n`);
  const mx=(x1+x2)/2;
  a(tx(mx,y-5,label,c,7.5,500));
});
// PDU Session
a(`<rect x="40" y="260" width="1040" height="4" rx="2" fill="rgba(16,185,129,.15)"/>\n`);
a(tx(550,275,'PDU Session Establishment','#10b981',9,700));
const pdu=[
  [80,220,290,'10. PDU Session Req','#10b981'],
  [220,370,310,'11. Fwd to AMF','#8b5cf6'],
  [370,730,330,'12. Create SM Context','#8b5cf6'],
  [730,860,350,'13. PFCP Session Est.','#f59e0b'],
  [860,730,370,'14. PFCP Response','#f59e0b'],
  [730,370,390,'15. PDU Accept','#8b5cf6'],
  [370,220,400,'16. RRC Reconfig','#8b5cf6'],
];
pdu.forEach(([x1,x2,y,label,c])=>{
  a(`<line x1="${x1}" y1="${y}" x2="${x2}" y2="${y}" stroke="${c}" stroke-width="1.3" marker-end="url(#f2)"/>\n`);
  a(tx((x1+x2)/2,y-5,label,c,7.5,500));
});
a('</svg></div></div>\n');

// Data flow
a(`<div class="card"><div class="ct">Data Plane — UE to Internet via BIG-IP</div><div class="dw"><svg viewBox="0 0 1100 200" width="100%" style="display:block">
<defs><marker id="d1" markerWidth="7" markerHeight="5" refX="6" refY="2.5" orient="auto"><polygon points="0 0,7 2.5,0 5" fill="#10b981"/></marker><marker id="d2" markerWidth="7" markerHeight="5" refX="6" refY="2.5" orient="auto"><polygon points="0 0,7 2.5,0 5" fill="#f97316"/></marker></defs>
<rect width="1100" height="200" fill="#0a0e17"/>
`);
// Forward path
const fwd=[['UE',50,'#06b6d4'],['gNB',200,'#10b981'],['UPF',380,'#10b981'],['Bridge',530,'#10b981'],['Transit',660,'#f97316'],['BIG-IP',820,'#ef4444'],['Internet',990,'#f97316']];
fwd.forEach(([n,x,c],i)=>{
  a(`<rect x="${x-35}" y="55" width="70" height="36" rx="6" fill="#1e293b" stroke="${c}" stroke-width="1.3"/>\n`);
  a(tx(x,78,n,c,9.5,700));
  if(i<fwd.length-1){
    const nx=fwd[i+1][1];
    a(`<line x1="${x+35}" y1="73" x2="${nx-35}" y2="73" stroke="#10b981" stroke-width="1.5" class="fl" marker-end="url(#d1)"/>\n`);
  }
});
// Labels
a(tx(140,55,'Radio','#5a6a85',7.5));a(tx(290,55,'N3 GTP-U','#10b981',7.5));a(tx(455,55,'N6','#10b981',7.5));a(tx(595,55,'L2 Bridge','#5a6a85',7.5));a(tx(740,55,'10.1.10.0/24','#f97316',7.5));a(tx(905,55,'CGNAT+AFM','#ef4444',7.5));
// Return path
a(`<rect x="30" y="130" width="1050" height="1" fill="rgba(90,106,133,.2)"/>\n`);
a(tx(550,125,'Return Path','#5a6a85',8,500));
fwd.slice().reverse().forEach(([n,x,c],i,arr)=>{
  if(i<arr.length-1){
    const nx=arr[i+1][1];
    a(`<line x1="${x-35}" y1="145" x2="${nx+35}" y2="145" stroke="#5a6a85" stroke-width="1" class="flr" stroke-dasharray="4 3"/>\n`);
  }
});
a(tx(550,165,'UE IP preserved · BIG-IP static route: 10.45.0.0/16 via 10.33.37.1','#5a6a85',8));
a('</svg></div></div>\n');

// Flow description cards
a(`<div class="card"><div class="ct">Key Protocol Summary</div>
<table class="t"><thead><tr><th>Interface</th><th>Protocol</th><th>Peers</th><th>Purpose</th></tr></thead><tbody>
<tr><td style="color:#8b5cf6">N1</td><td>NAS</td><td>UE ↔ AMF</td><td>Registration, authentication, session management</td></tr>
<tr><td style="color:#8b5cf6">N2</td><td>NGAP/SCTP</td><td>gNB ↔ AMF</td><td>Control plane signaling</td></tr>
<tr><td style="color:#10b981">N3</td><td>GTP-U/UDP</td><td>gNB ↔ UPF</td><td>User data tunneling</td></tr>
<tr><td style="color:#f59e0b">N4</td><td>PFCP/UDP</td><td>SMF ↔ UPF</td><td>Session rules, QoS, forwarding</td></tr>
<tr><td style="color:#10b981">N6</td><td>IP</td><td>UPF ↔ DN</td><td>Data Network interface (internet)</td></tr>
<tr><td style="color:#3b82f6">SBI</td><td>HTTP/2</td><td>All NFs</td><td>Service discovery, registration, subscription</td></tr>
</tbody></table></div></div>
`);
};
