const{a,nf,ln,tx,O}=require('./gen');
// CSS
a(`<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1.0"><title>SP-Labs Architecture Portal</title><style>
*{margin:0;padding:0;box-sizing:border-box}:root{--bg:#0a0e17;--bg2:#111827;--card:#151d2e;--border:#1e2d45;--border2:#2a3f63;--text:#e2e8f0;--muted:#8899b4;--dim:#5a6a85;--accent:#3b82f6;--accent2:#60a5fa;--green:#10b981;--red:#ef4444;--amber:#f59e0b;--purple:#8b5cf6;--cyan:#06b6d4;--orange:#f97316;--pink:#ec4899;--radius:10px;--rr:6px;--font:'Segoe UI',system-ui,sans-serif;--mono:'Cascadia Code','Fira Code',monospace}
html{font-size:14px}body{font-family:var(--font);background:var(--bg);color:var(--text);min-height:100vh;overflow-x:hidden}
header{background:linear-gradient(135deg,#0f172a,#1e293b);border-bottom:1px solid var(--border);padding:18px 32px;display:flex;align-items:center;justify-content:space-between;position:sticky;top:0;z-index:100}header h1{font-size:1.35rem;font-weight:700}header h1 span{color:var(--accent2)}.hr{display:flex;gap:12px;align-items:center}
.badge{font-size:.7rem;padding:3px 10px;border-radius:20px;font-weight:600;text-transform:uppercase;letter-spacing:.5px}.bb{background:rgba(59,130,246,.15);color:var(--accent2);border:1px solid rgba(59,130,246,.3)}.bg{background:rgba(16,185,129,.12);color:var(--green);border:1px solid rgba(16,185,129,.25)}
.tn{display:flex;gap:2px;padding:0 32px;background:var(--bg2);border-bottom:1px solid var(--border)}.tb{padding:12px 22px;font-size:.82rem;font-weight:600;color:var(--muted);background:none;border:none;cursor:pointer;border-bottom:2px solid transparent;transition:.2s}.tb:hover{color:var(--text)}.tb.active{color:var(--accent2);border-bottom-color:var(--accent)}
.tc{display:none;padding:28px 32px;animation:fadeIn .35s}.tc.active{display:block}@keyframes fadeIn{from{opacity:0;transform:translateY(8px)}to{opacity:1;transform:none}}
.card{background:var(--card);border:1px solid var(--border);border-radius:var(--radius);padding:20px;margin-bottom:20px;transition:.2s}.card:hover{border-color:var(--border2);box-shadow:0 4px 24px rgba(0,0,0,.4)}
.ct{font-size:.95rem;font-weight:700;margin-bottom:12px}.hint{font-size:.75rem;color:var(--dim);margin-bottom:10px}.dw{background:var(--bg);border:1px solid var(--border);border-radius:var(--radius);overflow:hidden}svg text{font-family:var(--font)}
.tip{position:fixed;z-index:200;background:#1e293b;border:1px solid var(--border2);border-radius:var(--rr);padding:14px 18px;max-width:340px;font-size:.78rem;line-height:1.55;color:var(--text);box-shadow:0 8px 32px rgba(0,0,0,.55);pointer-events:none;opacity:0;transition:opacity .18s}.tip.show{opacity:1}.tip h4{font-size:.85rem;margin-bottom:6px;color:var(--accent2)}.tip .ip{color:var(--cyan);font-family:var(--mono);font-size:.75rem}.tip .desc{color:var(--muted);margin-top:4px}
.legend{display:flex;flex-wrap:wrap;gap:16px;padding:14px 20px;background:var(--bg2);border-radius:var(--rr);margin-top:16px}.li{display:flex;align-items:center;gap:6px;font-size:.75rem;color:var(--muted)}.ld{width:10px;height:10px;border-radius:50%}
table.t{width:100%;border-collapse:collapse;font-size:.8rem;margin-top:10px}table.t th{text-align:left;color:var(--muted);font-weight:600;padding:8px 12px;border-bottom:1px solid var(--border);font-size:.72rem;text-transform:uppercase;letter-spacing:.4px}table.t td{padding:8px 12px;border-bottom:1px solid rgba(30,45,69,.5)}.t tr:hover td{background:rgba(59,130,246,.04)}.m{font-family:var(--mono);font-size:.76rem;color:var(--cyan)}
.nr{display:grid;grid-template-columns:140px 150px 1fr;gap:12px;padding:10px 14px;border-radius:var(--rr);margin-bottom:4px;font-size:.8rem;align-items:center}.nr:nth-child(odd){background:rgba(255,255,255,.02)}.nl{font-weight:600;display:flex;align-items:center;gap:6px}
.sg{display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:16px}.sc{background:var(--bg2);border:1px solid var(--border);border-radius:var(--radius);padding:18px;position:relative;overflow:hidden}.sc::before{content:'';position:absolute;top:0;left:0;right:0;height:3px}.sc.c1::before{background:linear-gradient(90deg,var(--green),var(--cyan))}.sc.c2::before{background:linear-gradient(90deg,var(--red),var(--orange))}.sc.c3::before{background:linear-gradient(90deg,var(--purple),var(--pink))}.sc.c4::before{background:linear-gradient(90deg,var(--amber),var(--orange))}.sc h3{font-size:.88rem;margin-bottom:8px}.sc p{font-size:.78rem;color:var(--muted);line-height:1.5}.sc code{font-family:var(--mono);font-size:.72rem;color:var(--cyan);background:rgba(6,182,212,.08);padding:1px 5px;border-radius:3px}
@keyframes flowR{0%{stroke-dashoffset:20}100%{stroke-dashoffset:0}}.fl{stroke-dasharray:6 4;animation:flowR .8s linear infinite}@keyframes flowL{0%{stroke-dashoffset:-20}100%{stroke-dashoffset:0}}.flr{stroke-dasharray:6 4;animation:flowL .8s linear infinite}
@media(max-width:900px){.tn{overflow-x:auto;padding:0 16px}.tc{padding:16px}header{padding:14px 16px}}
</style></head><body>
`);
// Header + Nav
a(`<header><h1>&#x1F3D7;&#xFE0F; <span>SP-Labs</span> — Architecture Portal</h1><div class="hr"><span class="badge bb">5G SA</span><span class="badge bg">v1.4</span></div></header>
<nav class="tn"><button class="tb active" data-tab="overview">&#x1F5FA;&#xFE0F; Full Topology</button><button class="tb" data-tab="bigip">&#x1F6E1;&#xFE0F; BIG-IP Integration</button><button class="tb" data-tab="networks">&#x1F310; Networks &amp; IPs</button><button class="tb" data-tab="flows">&#x26A1; Traffic Flows</button><button class="tb" data-tab="commands">&#x2328;&#xFE0F; Quick Commands</button></nav>
`);

// Tab 1: Full Topology
a(`<div class="tc active" id="tab-overview"><div class="card"><div class="ct">SP-Labs 5G SA Architecture — End-to-End</div><p class="hint">Hover over any component for details · Click to pin tooltip</p><div class="dw"><svg viewBox="0 0 1200 620" width="100%" style="display:block">
<defs><marker id="a2" markerWidth="7" markerHeight="5" refX="6" refY="2.5" orient="auto"><polygon points="0 0,7 2.5,0 5" fill="#10b981"/></marker><marker id="a3" markerWidth="7" markerHeight="5" refX="6" refY="2.5" orient="auto"><polygon points="0 0,7 2.5,0 5" fill="#f97316"/></marker></defs>
<rect width="1200" height="620" fill="#0a0e17"/>
<rect x="20" y="55" width="880" height="540" rx="14" fill="none" stroke="#1e2d45" stroke-width="1.5" stroke-dasharray="8 4"/>
`);
a(tx(40,82,'DOCKER HOST (Ubuntu)','#5a6a85',11,600,'start'));
a(`<line x1="140" y1="175" x2="750" y2="175" stroke="#2a3f63" stroke-width="2" stroke-dasharray="4 3"/>\n`);
a(tx(420,168,'SBI BUS · 10.33.33.0/24','#5a6a85',9,600));
// SBI NFs
[['nrf',100],['scp',182],['amf',264],['smf',346],['ausf',428],['udm',510],['udr',592],['pcf',674]].forEach(([id,x])=>{
  const cp=['amf','smf'].includes(id);
  a(nf(id,x,186,68,34,id.toUpperCase(),cp?'#8b5cf6':'#3b82f6',cp?'#a78bfa':'#60a5fa'));
});
a(nf('nssf',264,232,68,34,'NSSF','#3b82f6','#60a5fa'));
a(nf('bsf',346,232,68,34,'BSF','#3b82f6','#60a5fa'));
a(nf('mongodb',592,232,90,34,'MongoDB','#f59e0b','#f59e0b',10));
a(nf('webui',698,232,82,34,'WebUI','#f59e0b','#f59e0b',10));
// UERANSIM
a(`<rect x="40" y="310" width="210" height="200" rx="10" fill="rgba(139,92,246,.05)" stroke="#4c1d95" stroke-width="1" stroke-dasharray="6 3"/>\n`);
a(tx(55,332,'UERANSIM','#8b5cf6',10,600,'start'));
a(nf('gnb',120,348,100,40,'gNB','#10b981','#10b981',11));
a(nf('ue',60,430,80,40,'UEs','#06b6d4','#06b6d4'));
a(`<line x1="100" y1="430" x2="150" y2="388" stroke="#06b6d4" stroke-width="1.2" opacity=".5"/>\n`);
a(ln(220,362,298,220,'#8b5cf6',1.5));
a(`<text x="250" y="288" fill="#8b5cf6" font-size="8.5" font-weight="600" transform="rotate(-55 250 288)">N2 NGAP</text>\n`);
// UPF
a(`<g data-nf="upf"><rect x="380" y="348" width="120" height="50" rx="8" fill="#1e293b" stroke="#10b981" stroke-width="2"/><text x="440" y="371" text-anchor="middle" fill="#10b981" font-size="12" font-weight="700">UPF</text><text x="440" y="386" text-anchor="middle" fill="#5a6a85" font-size="8">10.33.37.14</text></g>\n`);
a(ln(220,372,380,372,'#10b981',1.8,'fl','a2'));
a(tx(300,365,'N3 GTP-U','#10b981'));
a(`<line x1="380" y1="203" x2="420" y2="348" stroke="#f59e0b" stroke-width="1" stroke-dasharray="4 3"/>\n`);
a(tx(388,280,'N4','#f59e0b',8,600,'start'));
a(ln(500,373,590,373,'#10b981',2,'fl','a2'));a(tx(545,365,'N6','#10b981'));
a(`<rect x="590" y="352" width="90" height="42" rx="6" fill="rgba(16,185,129,.06)" stroke="#10b981" stroke-width="1.2" stroke-dasharray="4 2"/>\n`);
a(tx(635,370,'N6 Bridge','#10b981'));a(tx(635,383,'10.33.37.1','#5a6a85',7.5));
a(ln(680,373,920,373,'#f97316',2,'fl','a3'));a(tx(800,365,'Transit 10.1.10.0/24','#f97316',8));
// BIG-IP box
a(`<rect x="920" y="90" width="260" height="490" rx="14" fill="rgba(239,68,68,.03)" stroke="#ef4444" stroke-width="1.5"/>\n`);
a(tx(940,118,'F5 BIG-IP','#ef4444',12,700,'start'));a(tx(940,134,'External VM · 10.1.10.200','#5a6a85',8.5,400,'start'));
a(`<rect x="940" y="150" width="220" height="32" rx="5" fill="rgba(6,182,212,.06)" stroke="#06b6d4" stroke-width="1"/>\n`);
a(tx(1050,171,'Internal: 10.1.10.200/24','#06b6d4',9,600));
a(`<g data-nf="cgnat"><rect x="940" y="200" width="220" height="55" rx="8" fill="#1e293b" stroke="#10b981" stroke-width="1.5"/><text x="960" y="222" fill="#10b981" font-size="10.5" font-weight="700">CGNAT</text><text x="960" y="237" fill="#5a6a85" font-size="8">vs_cgnat · snatpool_cgnat</text><text x="960" y="249" fill="#5a6a85" font-size="7.5">SNAT: 198.51.100.10-13</text></g>\n`);
a(`<g data-nf="afm"><rect x="940" y="268" width="220" height="55" rx="8" fill="#1e293b" stroke="#ef4444" stroke-width="1.5"/><text x="960" y="290" fill="#ef4444" font-size="10.5" font-weight="700">AFM Firewall</text><text x="960" y="305" fill="#5a6a85" font-size="8">policy_gi_lan · 5 rules</text></g>\n`);
a(`<g data-nf="dns"><rect x="940" y="336" width="220" height="50" rx="8" fill="#1e293b" stroke="#8b5cf6" stroke-width="1.5"/><text x="960" y="358" fill="#8b5cf6" font-size="10.5" font-weight="700">DNS Proxy</text><text x="960" y="373" fill="#5a6a85" font-size="8">vs_dns · 10.1.10.200:53</text></g>\n`);
a(`<g data-nf="telemetry"><rect x="940" y="400" width="220" height="42" rx="8" fill="#1e293b" stroke="#f59e0b" stroke-width="1.2"/><text x="960" y="420" fill="#f59e0b" font-size="10" font-weight="700">Telemetry Streaming</text><text x="960" y="434" fill="#5a6a85" font-size="8">Prometheus Pull · :443</text></g>\n`);
a(`<rect x="940" y="460" width="220" height="32" rx="5" fill="rgba(249,115,22,.06)" stroke="#f97316" stroke-width="1"/>\n`);
a(tx(1050,481,'External: 198.51.100.200/24','#f97316',9,600));
a(ln(1050,492,1050,540,'#f97316',2,'fl','a3'));
a(`<rect x="990" y="540" width="120" height="34" rx="8" fill="rgba(249,115,22,.08)" stroke="#f97316" stroke-width="1.2"/>\n`);
a(tx(1050,562,'Internet','#f97316',11,700));
// Monitoring
a(`<rect x="560" y="450" width="310" height="120" rx="10" fill="rgba(249,115,22,.03)" stroke="#f59e0b" stroke-width="1" stroke-dasharray="6 3"/>\n`);
a(tx(575,472,'MONITORING','#f59e0b',9.5,600,'start'));
a(nf('prometheus',575,484,86,34,'Prometheus','#f59e0b','#f59e0b',9));
a(nf('grafana',675,484,76,34,'Grafana','#f59e0b','#f59e0b',9));
a(`<rect x="765" y="484" width="90" height="34" rx="6" fill="#1e293b" stroke="#f59e0b" stroke-width="1.2"/>\n`);
a(tx(810,506,'Node Exp.','#f59e0b',8,600));
a(`<line x1="661" y1="494" x2="940" y2="421" stroke="#f59e0b" stroke-width="1" stroke-dasharray="3 3" opacity=".4"/>\n`);
a(tx(800,452,'TS scrape','#f59e0b',7,500));
a('</svg></div>\n');
// Legend
a('<div class="legend">\n');
[['#3b82f6','SBI NFs'],['#8b5cf6','Control Plane'],['#10b981','User Plane'],['#06b6d4','UE Devices'],['#ef4444','F5 BIG-IP'],['#f59e0b','Monitoring'],['#f97316','Internet']].forEach(([c,l])=>a(`<div class="li"><div class="ld" style="background:${c}"></div> ${l}</div>\n`));
a('</div></div></div>\n');
// Tab 2: BIG-IP
require('./build_bigip')(a,nf,ln,tx);
// Tab 3: Networks
require('./build_nets')(a);
// Tab 4: Flows
require('./build_flows')(a,ln,tx);
// Tab 5: Commands
require('./build_cmds')(a);
// JavaScript
require('./build_js')(a);
a('</body></html>\n');
console.log(`Done! ${O} (${require('fs').statSync(O).size} bytes)`);
