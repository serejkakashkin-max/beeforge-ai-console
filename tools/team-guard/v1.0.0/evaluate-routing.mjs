// Optional real-model evaluation. Tools are only described; none are executed.
// node tools/team-guard/v1.0.0/evaluate-routing.mjs --base-url http://127.0.0.1:8080/v1 --model Q2
import fs from 'node:fs';
const root=new URL('../../../',import.meta.url);
const config=JSON.parse(fs.readFileSync(new URL('opencode/opencode.template.json',root),'utf8').replace(/^\uFEFF/,''));
const cases=JSON.parse(fs.readFileSync(new URL('benchmarks/team-routing-cases.json',root),'utf8'));
const arg=name=>process.argv[process.argv.indexOf(name)+1];
if(process.argv.includes('--check')) {
  if(cases.length<6 || cases.some(c=>!c.prompt || !config.agent[c.agent])) throw Error('Invalid evaluation cases');
  console.log('ROUTING_CASES_VALID');
} else {
  if(!process.argv.includes('--base-url') || !process.argv.includes('--model')) throw Error('Specify --base-url and --model; no inference is started by default.');
  const base=new URL(arg('--base-url').replace(/\/$/,'')+'/');
  if(base.username || base.password || base.search || base.hash || !['http:','https:'].includes(base.protocol)) throw Error('Invalid endpoint');
  const tools=[{type:'function',function:{name:'task',description:'Delegate a bounded task to one configured specialist.',parameters:{type:'object',properties:{subagent_type:{type:'string',enum:cases.map(c=>c.agent)},description:{type:'string'},prompt:{type:'string'}},required:['subagent_type','description','prompt']}}}];
  let passed=0;
  for(const c of cases) {
    const started=Date.now();
    try {
      const response=await fetch(new URL('chat/completions',base),{method:'POST',headers:{'Content-Type':'application/json'},signal:AbortSignal.timeout(90000),body:JSON.stringify({model:arg('--model'),messages:[{role:'system',content:config.agent['team-lead'].prompt},{role:'user',content:c.prompt}],tools,temperature:0,max_tokens:1536})});
      if(!response.ok) throw Error('HTTP '+response.status);
      const data=await response.json(), calls=data.choices?.[0]?.message?.tool_calls || [];
      const chosen=calls[0]?.function?.name==='task'?JSON.parse(calls[0].function.arguments):{};
      const ok=calls.length===1 && chosen.subagent_type===c.agent && String(chosen.prompt||'').length<=6000;
      if(ok) passed++;
      console.log(JSON.stringify({id:c.id,passed:ok,expected:c.agent,actual:chosen.subagent_type||null,wallMs:Date.now()-started,usage:data.usage||null}));
    } catch(e) {console.log(JSON.stringify({id:c.id,passed:false,error:String(e.message).slice(0,160),wallMs:Date.now()-started}));}
  }
  console.log(JSON.stringify({passed,total:cases.length,scope:'first delegation only; does not measure implementation quality'}));
  if(passed!==cases.length) process.exitCode=1;
}
