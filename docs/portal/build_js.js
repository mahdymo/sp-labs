module.exports=(a)=>{
a(`<div class="tip" id="tooltip"></div>
<script>
// Tab switching
document.querySelectorAll('.tb').forEach(b=>b.addEventListener('click',()=>{
  document.querySelectorAll('.tb').forEach(t=>t.classList.remove('active'));
  document.querySelectorAll('.tc').forEach(t=>t.classList.remove('active'));
  b.classList.add('active');
  document.getElementById('tab-'+b.dataset.tab).classList.add('active');
}));

// Tooltip data
const meta={
  nrf:{name:'NRF',ip:'10.33.33.10',desc:'Network Repository Function — NF discovery & registration'},
  scp:{name:'SCP',ip:'10.33.33.11',desc:'Service Communication Proxy — SBI message routing'},
  amf:{name:'AMF',ip:'10.33.33.12 / 10.33.34.12',desc:'Access & Mobility Management — registration, handover, N2 signaling'},
  smf:{name:'SMF',ip:'10.33.33.13 / 10.33.36.13',desc:'Session Management — PDU sessions, QoS, PFCP to UPF'},
  ausf:{name:'AUSF',ip:'10.33.33.15',desc:'Authentication Server Function — 5G-AKA'},
  udm:{name:'UDM',ip:'10.33.33.16',desc:'Unified Data Management — subscriber profiles'},
  udr:{name:'UDR',ip:'10.33.33.17',desc:'Unified Data Repository — subscription data store'},
  pcf:{name:'PCF',ip:'10.33.33.18',desc:'Policy Control Function — QoS, charging rules'},
  nssf:{name:'NSSF',ip:'10.33.33.19',desc:'Network Slice Selection Function'},
  bsf:{name:'BSF',ip:'10.33.33.20',desc:'Binding Support Function — session binding'},
  mongodb:{name:'MongoDB',ip:'10.33.33.2',desc:'Database — subscriber data, NF profiles'},
  webui:{name:'WebUI',ip:'10.33.33.21',desc:'Open5GS management UI (:9999)'},
  upf:{name:'UPF',ip:'10.33.35.14 / 10.33.36.14 / 10.33.37.14',desc:'User Plane Function — GTP-U decap, N6 forwarding, ogstun TUN'},
  gnb:{name:'gNodeB',ip:'10.33.34.100 / 10.33.35.100',desc:'UERANSIM base station — N2/N3 termination'},
  ue:{name:'UE Devices',ip:'10.45.0.x (assigned)',desc:'UERANSIM UEs — multiple subscriber profiles'},
  cgnat:{name:'CGNAT',ip:'198.51.100.10-13',desc:'Carrier-Grade NAT — translates 10.45.0.0/16 to public pool'},
  afm:{name:'AFM Firewall',ip:'N/A',desc:'Advanced Firewall Manager — Gi-LAN policy enforcement'},
  dns:{name:'DNS Proxy',ip:'10.1.10.200:53',desc:'Transparent DNS — logging, analytics, filtering'},
  telemetry:{name:'Telemetry Streaming',ip:':443',desc:'Exports BIG-IP stats to Prometheus'},
  prometheus:{name:'Prometheus',ip:'10.33.38.200:9090',desc:'Metrics collection & alerting'},
  grafana:{name:'Grafana',ip:'10.33.38.201:3000',desc:'Dashboards & visualization'},
};
const tip=document.getElementById('tooltip');
let pinned=false;
document.querySelectorAll('[data-nf]').forEach(el=>{
  el.style.cursor='pointer';
  el.addEventListener('mouseenter',e=>{
    if(pinned)return;
    const d=meta[el.dataset.nf];if(!d)return;
    tip.innerHTML='<h4>'+d.name+'</h4><div class="ip">'+d.ip+'</div><div class="desc">'+d.desc+'</div>';
    tip.classList.add('show');
    pos(e);
  });
  el.addEventListener('mousemove',e=>{if(!pinned)pos(e)});
  el.addEventListener('mouseleave',()=>{if(!pinned){tip.classList.remove('show')}});
  el.addEventListener('click',e=>{
    const d=meta[el.dataset.nf];if(!d)return;
    pinned=!pinned;
    if(pinned){
      tip.innerHTML='<h4>'+d.name+'</h4><div class="ip">'+d.ip+'</div><div class="desc">'+d.desc+'</div>';
      tip.classList.add('show');pos(e);
    }else{tip.classList.remove('show')}
  });
});
document.addEventListener('click',e=>{
  if(!e.target.closest('[data-nf]')&&pinned){pinned=false;tip.classList.remove('show')}
});
function pos(e){tip.style.left=Math.min(e.clientX+14,window.innerWidth-360)+'px';tip.style.top=(e.clientY+14)+'px'}
</script>
`);
};
