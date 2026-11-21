#!/usr/bin/env node
'use strict';
const fs = require('fs');
const path = require('path');
const root = process.argv[2] || '/workspace';
const snapRoot = path.join(root, 'diagnostico/D01-clientes-pedidos/comparacao-cache-o2-o3');
const runs = [
  ['o2-1','O2','20261120-215930-diag-cache-o2'],
  ['o3-1','O3','20261120-220316-diag-cache-o3'],
  ['o2-2','O2','20261120-220651-diag-cache-o2'],
  ['o3-2','O3','20261120-221021-diag-cache-o3'],
  ['o2-3','O2','20261120-221343-diag-cache-o2'],
  ['o3-3','O3','20261120-221707-diag-cache-o3'],
];
const sum = xs => xs.reduce((a,x) => a + (x ?? 0), 0);
const median = xs => {
  xs = xs.filter(Number.isFinite).sort((a,b) => a-b);
  return xs.length % 2 ? xs[(xs.length-1)/2] : (xs[xs.length/2-1]+xs[xs.length/2])/2;
};
const pct = (a,b) => a === 0 ? null : (b/a-1)*100;
const read = file => JSON.parse(fs.readFileSync(file,'utf8'));
const index = (xs,key) => new Map(xs.map(x => [key(x),x]));
function diff(before,after,key,fields) {
  const a=index(before,key), b=index(after,key);
  return new Map([...new Set([...a.keys(),...b.keys()])].map(k => [k,
    Object.fromEntries(fields.map(f => [f,(b.get(k)?.[f]??0)-(a.get(k)?.[f]??0)]))
  ]));
}
function summary(text) {
  const take = re => Number(text.match(re)?.[1]);
  const overall=text.match(/^Tempo de resposta:\s+mediana ([\d.]+) ms \| p95 ([\d.]+) ms \| p99 ([\d.]+) ms/m);
  const routes={};
  for (const line of text.split('\n')) {
    const m=line.match(/^(cliente|cliente-por-email|pedidos-do-cliente|pedidos-por-status|busca-produtos|vendas-por-dia|top-produtos)\s+(\d+)\s+([\d.]+) ms\s+([\d.]+) ms\s+([\d.]+) ms\s+([\d.]+)%/);
    if(m) routes[m[1]]={requests:+m[2],median_ms:+m[3],p95_ms:+m[4],p99_ms:+m[5],errors_pct:+m[6]};
  }
  return {requests:take(/^Requisições:\s+(\d+)/m),rps:take(/^Requisições\/s:\s+([\d.]+)/m),
    median_ms:+overall[1],p95_ms:+overall[2],p99_ms:+overall[3],
    errors_pct:take(/^Erros:\s+([\d.]+)%/m),routes};
}
function resources(text) {
  const x={api:[],db:[]};
  for(const line of text.trim().split('\n').slice(1)){
    const p=line.split(','), service=p[1].includes('-api-')?'api':p[1].includes('-banco-')?'db':null;
    if(service)x[service].push({cpu:+p[2].replace('%',''),mem:+p[3].split('MiB')[0]});
  }
  const avg=(s,k)=>sum(x[s].map(v=>v[k]))/x[s].length;
  return {api_cpu:avg('api','cpu'),api_mem:avg('api','mem'),db_cpu:avg('db','cpu'),db_mem:avg('db','mem')};
}
function analyze([id,config,result]) {
  const dir=path.join(snapRoot,id), out=path.join(root,'resultados',result);
  const a=read(path.join(dir,'antes.json')), b=read(path.join(dir,'depois.json'));
  if(a.pg_stat_database.stats_reset!==b.pg_stat_database.stats_reset)throw Error(`stats_reset changed: ${id}`);
  if(a.servidor_iniciado_em_utc!==b.servidor_iniciado_em_utc)throw Error(`server restarted: ${id}`);
  const ioResetA=[...new Set(a.pg_stat_io.map(x=>x.stats_reset))];
  const ioResetB=[...new Set(b.pg_stat_io.map(x=>x.stats_reset))];
  if(ioResetA.length!==1 || ioResetB.length!==1 || ioResetA[0]!==ioResetB[0])
    throw Error(`pg_stat_io.stats_reset changed: ${id}`);
  const s=summary(fs.readFileSync(path.join(out,'resumo.txt'),'utf8'));
  const r=resources(fs.readFileSync(path.join(out,'recursos.csv'),'utf8'));
  const io=diff(a.pg_stat_io,b.pg_stat_io,x=>[x.backend_type,x.object,x.context].join('|'),
    ['reads','hits','evictions','reuses']);
  const tables=diff(a.pg_statio_user_tables,b.pg_statio_user_tables,x=>x.relname,
    ['heap_blks_read','heap_blks_hit','idx_blks_read','idx_blks_hit']);
  const indexes=diff(a.pg_statio_user_indexes,b.pg_statio_user_indexes,x=>x.indexrelname,
    ['idx_blks_read','idx_blks_hit']);
  const usage=diff(a.pg_stat_user_indexes,b.pg_stat_user_indexes,x=>x.indexrelname,
    ['idx_scan','idx_tup_read','idx_tup_fetch']);
  const get=(m,k)=>m.get(k)||{};
  const cn=get(io,'client backend|relation|normal'), cb=get(io,'client backend|relation|bulkread');
  const wn=get(io,'background worker|relation|normal'), wb=get(io,'background worker|relation|bulkread');
  const normal={reads:sum([cn.reads,wn.reads]),hits:sum([cn.hits,wn.hits]),
    evictions:sum([cn.evictions,wn.evictions])};
  normal.hit_rate=normal.hits/(normal.hits+normal.reads);
  const bulk={reads:sum([cb.reads,wb.reads]),hits:sum([cb.hits,wb.hits]),
    evictions:sum([cb.evictions,wb.evictions]),reuses:sum([cb.reuses,wb.reuses])};
  const pedidos=get(tables,'pedidos'), itens=get(tables,'itens_pedido');
  const newIndex={...get(indexes,'idx_itens_pedido_pedido_id'),...get(usage,'idx_itens_pedido_pedido_id')};
  const perReq=Object.fromEntries([
    ['normal_reads',normal.reads],['normal_hits',normal.hits],['normal_evictions',normal.evictions],
    ['bulk_reads',bulk.reads],['bulk_reuses',bulk.reuses],
    ['pedidos_heap_read',pedidos.heap_blks_read],['pedidos_heap_hit',pedidos.heap_blks_hit],
    ['itens_heap_read',itens.heap_blks_read],['itens_heap_hit',itens.heap_blks_hit],
    ['index_read',newIndex.idx_blks_read||0],['index_hit',newIndex.idx_blks_hit||0],
  ].map(([k,v])=>[k,v/s.requests]));
  return {id,config,result,before:a.coletado_em_utc,after:b.coletado_em_utc,
    stats_reset:ioResetA[0],shared_buffers:a.shared_buffers,
    track_io_timing:a.track_io_timing,summary:s,resources:r,normal,bulk,
    tables:{pedidos,itens_pedido:itens},new_index:newIndex,per_request:perReq};
}
const analyzed=runs.map(analyze);
const metrics={
  requests:x=>x.summary.requests,rps:x=>x.summary.rps,p95_general_ms:x=>x.summary.p95_ms,
  p95_d01_ms:x=>x.summary.routes['pedidos-do-cliente'].p95_ms,
  api_cpu_avg_pct:x=>x.resources.api_cpu,api_mem_avg_mib:x=>x.resources.api_mem,
  db_cpu_avg_pct:x=>x.resources.db_cpu,db_mem_avg_mib:x=>x.resources.db_mem,
  normal_reads:x=>x.normal.reads,normal_hits:x=>x.normal.hits,
  normal_evictions:x=>x.normal.evictions,normal_hit_rate:x=>x.normal.hit_rate,
  bulk_reads:x=>x.bulk.reads,bulk_hits:x=>x.bulk.hits,
  bulk_evictions:x=>x.bulk.evictions,bulk_reuses:x=>x.bulk.reuses,
  normal_reads_per_req:x=>x.per_request.normal_reads,
  normal_hits_per_req:x=>x.per_request.normal_hits,
  normal_evictions_per_req:x=>x.per_request.normal_evictions,
  bulk_reads_per_req:x=>x.per_request.bulk_reads,
  bulk_reuses_per_req:x=>x.per_request.bulk_reuses,
  pedidos_heap_read:x=>x.tables.pedidos.heap_blks_read,
  pedidos_heap_hit:x=>x.tables.pedidos.heap_blks_hit,
  itens_heap_read:x=>x.tables.itens_pedido.heap_blks_read,
  itens_heap_hit:x=>x.tables.itens_pedido.heap_blks_hit,
  new_index_read:x=>x.new_index.idx_blks_read||0,
  new_index_hit:x=>x.new_index.idx_blks_hit||0,
  new_index_scan:x=>x.new_index.idx_scan||0,
};
const medians={};
for(const config of ['O2','O3']){
  const group=analyzed.filter(x=>x.config===config);
  medians[config]=Object.fromEntries(Object.entries(metrics).map(([k,f])=>[k,median(group.map(f))]));
  medians[config].route_requests_total=Object.fromEntries(
    Object.keys(group[0].summary.routes).map(route=>[route,sum(group.map(x=>x.summary.routes[route].requests))]));
}
const changes=Object.fromEntries(Object.keys(metrics).map(k=>[k,pct(medians.O2[k],medians.O3[k])]));
process.stdout.write(JSON.stringify({runs:analyzed,medians,change_o2_to_o3_pct:changes},null,2)+'\n');
