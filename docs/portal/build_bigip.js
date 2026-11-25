module.exports=(a,nf,ln,tx)=>{
a(`<div class="tc" id="tab-bigip"><div class="card"><div class="ct">BIG-IP N6 / Gi-LAN Insertion Point</div><div class="dw"><svg viewBox="0 0 1000 300" width="100%" style="display:block">
<defs><marker id="b1" markerWidth="7" markerHeight="5" refX="6" refY="2.5" orient="auto"><polygon points="0 0,7 2.5,0 5" fill="#10b981"/></marker><marker id="b2" markerWidth="7" markerHeight="5" refX="6" refY="2.5" orient="auto"><polygon points="0 0,7 2.5,0 5" fill="#f97316"/></marker></defs>
<rect width="1000" height="300" fill="#0a0e17"/>
<rect x="30" y="100" width="90" height="100" rx="8" fill="#1e293b" stroke="#06b6d4" stroke-width="1.5"/>
`);
a(tx(75,130,'UEs','#06b6d4',11,700));a(tx(75,150,'10.45.0.0/16','#5a6a85',8));a(tx(75,168,'Basic · Power · IoT · Ent.','#5a6a85',7.5));
a(`<rect x="170" y="120" width="80" height="60" rx="8" fill="#1e293b" stroke="#10b981" stroke-width="1.5"/>\n`);
a(tx(210,150,'gNB','#10b981',11,700));a(tx(210,168,'10.33.35.100','#5a6a85',8));
a(ln(120,150,170,150,'#06b6d4',1.5,'fl','b1'));
a(`<rect x="300" y="110" width="110" height="80" rx="10" fill="#1e293b" stroke="#10b981" stroke-width="2"/>\n`);
a(tx(355,140,'UPF','#10b981',13,700));a(tx(355,158,'N6: 10.33.37.14','#5a6a85',8.5));a(tx(355,172,'ogstun + TUN','#5a6a85',7.5));
a(ln(250,150,300,150,'#10b981',2,'fl','b1'));a(tx(275,142,'N3','#10b981',8));
a(`<rect x="460" y="125" width="80" height="50" rx="6" fill="rgba(16,185,129,.06)" stroke="#10b981" stroke-width="1.2" stroke-dasharray="4 2"/>\n`);
a(tx(500,148,'Bridge','#10b981',9,600));a(tx(500,163,'10.33.37.1','#5a6a85',7.5));
a(ln(410,150,460,150,'#10b981',2,'fl','b1'));a(tx(435,142,'N6','#10b981',8));
a(ln(540,150,615,150,'#f97316',2.5,'fl'));a(tx(577,140,'10.1.10.0/24','#f97316',8.5,700));a(tx(577,170,'Transit Network','#5a6a85',7));
a(`<rect x="615" y="40" width="230" height="230" rx="12" fill="rgba(239,68,68,.04)" stroke="#ef4444" stroke-width="2"/>\n`);
a(tx(635,68,'BIG-IP','#ef4444',12,700,'start'));a(tx(635,84,'self_internal: 10.1.10.200','#5a6a85',8,400,'start'));
[['CGNAT snatpool_cgnat','#10b981',96],['AFM policy_gi_lan','#ef4444',132],['DNS vs_dns :53','#8b5cf6',168],['Telemetry Prometheus','#f59e0b',204]].forEach(([l,c,y])=>{
  a(`<rect x="635" y="${y}" width="190" height="28" rx="5" fill="rgba(0,0,0,.1)" stroke="${c}" stroke-width="1"/>\n`);a(tx(730,y+19,l,c,9,600));
});
a(tx(730,258,'External: 198.51.100.200','#f97316',8,600));
a(ln(845,150,905,150,'#f97316',2.5,'fl','b2'));
a(`<rect x="905" y="125" width="80" height="50" rx="8" fill="rgba(249,115,22,.08)" stroke="#f97316" stroke-width="1.5"/>\n`);
a(tx(945,155,'Internet','#f97316',11,700));
a(tx(577,210,'Return: 10.45.0.0/16 via 10.33.37.1','#5a6a85',7.5));
a(`<line x1="615" y1="195" x2="540" y2="195" stroke="#5a6a85" stroke-width="1" stroke-dasharray="3 2" class="flr"/>\n`);
a('</svg></div></div>\n');
// Service cards
a(`<div class="card"><div class="ct">BIG-IP Services at N6</div><div class="sg">
<div class="sc c1"><h3>CGNAT</h3><p>Translates UE addresses (<code>10.45.0.0/16</code>) to public IPs via SNAT pool.</p>
<table class="t"><tr><td>VS</td><td class="m">vs_cgnat (0.0.0.0:0)</td></tr><tr><td>Profile</td><td class="m">fastl4_cgnat</td></tr><tr><td>SNAT Pool</td><td class="m">198.51.100.10-13</td></tr><tr><td>Source</td><td class="m">10.45.0.0/16</td></tr></table></div>
<div class="sc c2"><h3>AFM Firewall</h3><p>Gi-LAN firewall policy for subscriber traffic.</p>
<table class="t"><tr><td style="color:#10b981">&#10003; allow_dns</td><td>TCP/UDP :53</td></tr><tr><td style="color:#10b981">&#10003; allow_web</td><td>TCP :80,:443</td></tr><tr><td style="color:#10b981">&#10003; allow_icmp</td><td>ICMP</td></tr><tr><td style="color:#10b981">&#10003; allow_ntp</td><td>UDP :123</td></tr><tr><td style="color:#ef4444">&#10007; deny_all</td><td>Drop+log</td></tr></table></div>
<div class="sc c3"><h3>DNS Proxy</h3><p>Transparent DNS proxy — logging, filtering, analytics.</p>
<table class="t"><tr><td>UDP</td><td class="m">vs_dns_udp 10.1.10.200:53</td></tr><tr><td>TCP</td><td class="m">vs_dns_tcp 10.1.10.200:53</td></tr><tr><td>Upstream</td><td class="m">8.8.8.8, 8.8.4.4</td></tr><tr><td>SMF</td><td>Change dns[0] in <code>smf.yaml</code></td></tr></table></div>
<div class="sc c4"><h3>Telemetry Streaming</h3><p>Exports BIG-IP metrics to Prometheus.</p>
<table class="t"><tr><td>Method</td><td>Prometheus Pull</td></tr><tr><td>Endpoint</td><td class="m">:443/mgmt/shared/telemetry/...</td></tr><tr><td>Job</td><td class="m">bigip-gi-lan</td></tr><tr><td>Status</td><td>Commented out</td></tr></table></div>
</div></div></div>
`);
};
