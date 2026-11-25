module.exports=(a)=>{
a('<div class="tc" id="tab-networks">\n');
a('<div class="card"><div class="ct">Docker Network Subnets</div>\n');
[['#3b82f6','SBI','10.33.33.0/24','Service-Based Interface (HTTP/2)'],['#8b5cf6','N2','10.33.34.0/24','gNB-AMF control (NGAP/SCTP)'],['#10b981','N3','10.33.35.0/24','gNB-UPF user plane (GTP-U)'],['#f59e0b','N4','10.33.36.0/24','SMF-UPF session mgmt (PFCP)'],['#10b981','N6','10.33.37.0/24','UPF-Data Network / BIG-IP'],['#5a6a85','MGMT','10.33.38.0/24','Management, monitoring'],['#f97316','Transit','10.1.10.0/24','Docker host-BIG-IP bridge'],['#06b6d4','UE Pool','10.45.0.0/16','UE IPs (assigned by SMF)']].forEach(([c,n,cidr,d])=>a(`<div class="nr"><span class="nl"><span class="ld" style="background:${c}"></span> ${n}</span><span class="m">${cidr}</span><span style="color:var(--muted)">${d}</span></div>\n`));
a('</div>\n');
a(`<div class="card"><div class="ct">5G Core IP Assignments</div>
<table class="t"><thead><tr><th>Container</th><th>SBI</th><th>N2</th><th>N3</th><th>N4</th><th>N6</th><th>MGMT</th></tr></thead><tbody>
<tr><td>mongodb</td><td class="m">.33.2</td><td>-</td><td>-</td><td>-</td><td>-</td><td>-</td></tr>
<tr><td>nrf</td><td class="m">.33.10</td><td>-</td><td>-</td><td>-</td><td>-</td><td class="m">.38.10</td></tr>
<tr><td>scp</td><td class="m">.33.11</td><td>-</td><td>-</td><td>-</td><td>-</td><td>-</td></tr>
<tr><td>amf</td><td class="m">.33.12</td><td class="m">.34.12</td><td>-</td><td>-</td><td>-</td><td class="m">.38.12</td></tr>
<tr><td>smf</td><td class="m">.33.13</td><td>-</td><td>-</td><td class="m">.36.13</td><td>-</td><td class="m">.38.13</td></tr>
<tr><td><b>upf</b></td><td>-</td><td>-</td><td class="m">.35.14</td><td class="m">.36.14</td><td class="m" style="color:#10b981"><b>.37.14</b></td><td class="m">.38.14</td></tr>
<tr><td>ausf</td><td class="m">.33.15</td><td>-</td><td>-</td><td>-</td><td>-</td><td>-</td></tr>
<tr><td>udm</td><td class="m">.33.16</td><td>-</td><td>-</td><td>-</td><td>-</td><td>-</td></tr>
<tr><td>udr</td><td class="m">.33.17</td><td>-</td><td>-</td><td>-</td><td>-</td><td>-</td></tr>
<tr><td>pcf</td><td class="m">.33.18</td><td>-</td><td>-</td><td>-</td><td>-</td><td>-</td></tr>
<tr><td>nssf</td><td class="m">.33.19</td><td>-</td><td>-</td><td>-</td><td>-</td><td>-</td></tr>
<tr><td>bsf</td><td class="m">.33.20</td><td>-</td><td>-</td><td>-</td><td>-</td><td>-</td></tr>
<tr><td>webui</td><td class="m">.33.21</td><td>-</td><td>-</td><td>-</td><td>-</td><td class="m">.38.21</td></tr>
</tbody></table></div>
`);
a(`<div class="card"><div class="ct">UERANSIM &amp; Monitoring</div>
<table class="t"><thead><tr><th>Container</th><th>N2</th><th>N3</th><th>MGMT</th><th>Role</th></tr></thead><tbody>
<tr><td>gnb</td><td class="m">.34.100</td><td class="m">.35.100</td><td class="m">.38.100</td><td>5G Base Station</td></tr>
<tr><td>ue</td><td>-</td><td>-</td><td class="m">.38.101</td><td>Basic UEs (x5)</td></tr>
<tr><td>prometheus</td><td>-</td><td>-</td><td class="m">.38.200</td><td>Metrics (:9090)</td></tr>
<tr><td>grafana</td><td>-</td><td>-</td><td class="m">.38.201</td><td>Dashboards (:3000)</td></tr>
<tr><td>node-exporter</td><td>-</td><td>-</td><td class="m">.38.202</td><td>Host metrics</td></tr>
</tbody></table></div>
`);
a(`<div class="card"><div class="ct">BIG-IP Reserved IPs</div>
<table class="t"><thead><tr><th>Network</th><th>IP</th><th>Interface</th><th>Purpose</th></tr></thead><tbody>
<tr><td>Transit</td><td class="m" style="color:#ef4444"><b>10.1.10.200</b></td><td>Internal</td><td>Primary N6 insertion</td></tr>
<tr><td>sp-labs-n6</td><td class="m">10.33.37.200</td><td>Internal</td><td>Direct N6 (alt)</td></tr>
<tr><td>sp-labs-mgmt</td><td class="m">10.33.38.250</td><td>Management</td><td>GUI, SSH, iControl</td></tr>
</tbody></table></div></div>
`);
};
