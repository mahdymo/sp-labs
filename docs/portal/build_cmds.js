module.exports=(a)=>{
a(`<div class="tc" id="tab-commands">
<div class="card"><div class="ct">Quick Commands Reference</div>
<table class="t"><thead><tr><th>Action</th><th>Command</th><th>Notes</th></tr></thead><tbody>
<tr><td>Start all</td><td class="m">make up</td><td>Brings up 5G core + RAN + monitoring</td></tr>
<tr><td>Stop all</td><td class="m">make down</td><td>Graceful shutdown</td></tr>
<tr><td>View logs</td><td class="m">make logs</td><td>Follow all container logs</td></tr>
<tr><td>UE status</td><td class="m">docker exec ue nr-cli imsi-999700000000001 -e status</td><td>Check registration/PDU state</td></tr>
<tr><td>Ping test</td><td class="m">docker exec ue ping -I uesimtun0 8.8.8.8 -c 4</td><td>Test data plane via UPF</td></tr>
<tr><td>DNS test</td><td class="m">docker exec ue nslookup google.com 10.1.10.200</td><td>Test DNS via BIG-IP proxy</td></tr>
<tr><td>UPF routes</td><td class="m">docker exec upf ip route</td><td>Verify N6 routing</td></tr>
<tr><td>UPF interfaces</td><td class="m">docker exec upf ip addr show ogstun</td><td>Check TUN device</td></tr>
<tr><td>Check NRF</td><td class="m">curl -s http://10.33.33.10:7777/nnrf-nfm/v1/nf-instances | jq</td><td>NF discovery status</td></tr>
<tr><td>AMF SCTP</td><td class="m">docker exec amf ss -lnp | grep 38412</td><td>NGAP listener</td></tr>
<tr><td>SMF sessions</td><td class="m">docker logs smf 2>&amp;1 | grep -i &quot;pdu session&quot;</td><td>PDU session creation</td></tr>
<tr><td>PFCP status</td><td class="m">docker logs smf 2>&amp;1 | grep -i pfcp</td><td>SMF-UPF association</td></tr>
<tr><td>BIG-IP tmsh</td><td class="m">tmsh list ltm virtual vs_cgnat</td><td>CGNAT virtual server</td></tr>
<tr><td>BIG-IP pools</td><td class="m">tmsh list ltm snatpool snatpool_cgnat</td><td>SNAT pool members</td></tr>
<tr><td>AFM rules</td><td class="m">tmsh list security firewall policy policy_gi_lan</td><td>Firewall rules</td></tr>
<tr><td>TS status</td><td class="m">curl -sku admin:admin https://localhost/mgmt/shared/telemetry/declare</td><td>Telemetry declaration</td></tr>
<tr><td>Prometheus</td><td class="m">curl http://localhost:9090/api/v1/targets</td><td>Scrape target status</td></tr>
</tbody></table></div>

<div class="card"><div class="ct">Web Interfaces</div>
<table class="t"><thead><tr><th>Service</th><th>URL</th><th>Credentials</th></tr></thead><tbody>
<tr><td>Open5GS WebUI</td><td class="m">http://&lt;host&gt;:9999</td><td class="m">admin / 1423</td></tr>
<tr><td>Grafana</td><td class="m">http://&lt;host&gt;:3000</td><td class="m">admin / grafana</td></tr>
<tr><td>Prometheus</td><td class="m">http://&lt;host&gt;:9090</td><td>No auth</td></tr>
<tr><td>BIG-IP GUI</td><td class="m">https://10.33.38.250</td><td class="m">admin / &lt;configured&gt;</td></tr>
<tr><td>BIG-IP SSH</td><td class="m">ssh admin@10.33.38.250</td><td>Key or password</td></tr>
</tbody></table></div>

<div class="card"><div class="ct">UE Subscriber Profiles</div>
<table class="t"><thead><tr><th>Profile</th><th>IMSI Range</th><th>APN/DNN</th><th>QoS</th></tr></thead><tbody>
<tr><td>Basic</td><td class="m">imsi-999700000000001 — 005</td><td class="m">internet</td><td>9 (default)</td></tr>
<tr><td>Power User</td><td class="m">imsi-999700000000010 — 012</td><td class="m">internet</td><td>7 (priority)</td></tr>
<tr><td>IoT</td><td class="m">imsi-999700000000020 — 022</td><td class="m">iot</td><td>9 (low BW)</td></tr>
<tr><td>Enterprise</td><td class="m">imsi-999700000000030 — 032</td><td class="m">enterprise</td><td>5 (guaranteed)</td></tr>
</tbody></table></div></div>
`);
};
