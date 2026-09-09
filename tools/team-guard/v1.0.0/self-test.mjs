import { BeeForgeTeamGuard } from "./plugin.mjs";

const hooks = await BeeForgeTeamGuard();
const before = (sessionID, callID, agent) => hooks["tool.execute.before"]({ tool: "task", sessionID, callID }, { args: { agent } });
const after = (sessionID, callID, agent, output) => hooks["tool.execute.after"]({ tool: "task", sessionID, callID, args: { agent } }, { output });

let oversizedPromptBlocked = false;
try {
  await hooks["tool.execute.before"](
    { tool: "task", sessionID: "oversized", callID: "oversized-1" },
    { args: { agent: "systems-engineer", prompt: "x".repeat(6001) } },
  );
} catch (error) {
  oversizedPromptBlocked = String(error?.message || error).includes("BEEFORGE_DELEGATION_CONTEXT_TOO_LARGE");
}
if (!oversizedPromptBlocked) throw new Error("Oversized delegation context was not blocked");

await hooks.event({ event: { type: "message.updated", properties: { info: { id: "user-1", role: "user", sessionID: "ordinary" } } } });
await before("ordinary", "dev-1", "software-engineer");
await after("ordinary", "dev-1", "software-engineer", '<task state="completed"><task_result>HANDOFF complete</task_result></task>');

let duplicateBlocked = false;
try { await before("ordinary", "dev-2", "software-engineer"); }
catch (error) { duplicateBlocked = String(error?.message || error).includes("BEEFORGE_DUPLICATE_DELEGATION_BLOCKED"); }
if (!duplicateBlocked) throw new Error("Completed same-role delegation was not blocked");

await before("ordinary", "qa-1", "qa-engineer");
await after("ordinary", "qa-1", "qa-engineer", '<task state="completed"><task_result>QA HANDOFF</task_result></task>');

await before("rollover", "architect-1", "solution-architect");
await after("rollover", "architect-1", "solution-architect", '<task state="completed"><task_result>Checkpoint\nCONTEXT_ROLLOVER_REQUIRED\n</task_result></task>');
await before("rollover", "architect-2", "solution-architect");
await after("rollover", "architect-2", "solution-architect", '<task state="completed"><task_result>Done\nCONTEXT_ROLLOVER_REQUIRED\n</task_result></task>');

let secondRolloverBlocked = false;
try { await before("rollover", "architect-3", "solution-architect"); }
catch (error) { secondRolloverBlocked = String(error?.message || error).includes("BEEFORGE_DUPLICATE_DELEGATION_BLOCKED"); }
if (!secondRolloverBlocked) throw new Error("A second same-role rollover was not blocked");

await before("active", "dev-active", "software-engineer");
let parallelBlocked = false;
try { await before("active", "qa-early", "qa-engineer"); }
catch (error) { parallelBlocked = String(error?.message || error).includes("BEEFORGE_ACTIVE_DELEGATION_BLOCKED"); }
if (!parallelBlocked) throw new Error("A second unfinished delegation was not blocked");
await after("active", "dev-active", "software-engineer", '<task state="completed"><task_result>Done</task_result></task>');

await hooks.event({ event: { type: "message.updated", properties: { info: { id: "user-2", role: "user", sessionID: "ordinary" } } } });
await before("ordinary", "dev-new-turn", "software-engineer");


const packet = (status, defects=[]) => '<task state="completed"><task_result>' +
  '\x60\x60\x60beeforge-handoff\n' + JSON.stringify({goal:"fix",scope:"test",status,defects,checks:["test passed"],doNotRepeat:["baseline"]}) +
  '\n\x60\x60\x60\n</task_result></task>';
await before("qa-cycle","d1","software-engineer"); await after("qa-cycle","d1","software-engineer",packet("DONE"));
await before("qa-cycle","q1","qa-engineer"); await after("qa-cycle","q1","qa-engineer",packet("QA_FAILED",[{id:"D1",actual:"broken",expected:"works",reproduce:"click"}]));
const repairArgs={args:{subagent_type:"software-engineer",prompt:"Repair D1"}};
await hooks["tool.execute.before"]({tool:"task",sessionID:"qa-cycle",callID:"d2"},repairArgs);
if(!repairArgs.args.prompt.includes("BEEFORGE_PREVIOUS_HANDOFF_DATA") || !repairArgs.args.prompt.includes("D1")) throw Error("QA evidence not forwarded");
await after("qa-cycle","d2","software-engineer",packet("DONE"));
await before("qa-cycle","q2","qa-engineer"); await after("qa-cycle","q2","qa-engineer",packet("QA_FAILED",[{id:"D2",reproduce:"click",expected:"works",actual:"broken"}]));
try{await before("qa-cycle","d3","software-engineer");throw Error("second repair allowed");}
catch(e){if(!e.message.includes("BEEFORGE_DUPLICATE")) throw e;}

await hooks.event({event:{type:"message.updated",properties:{info:{id:"u1",role:"user",sessionID:"idempotent"}}}});
await before("idempotent","a","software-engineer");await after("idempotent","a","software-engineer",packet("DONE"));
await hooks.event({event:{type:"message.updated",properties:{info:{id:"u1",role:"user",sessionID:"idempotent"}}}});
try{await before("idempotent","b","software-engineer");throw Error("same message resets history");}
catch(e){if(!e.message.includes("BEEFORGE_DUPLICATE")) throw e;}

// Parent tool events complete asynchronous calls; idle alone must not release a task.
await before("async","a","software-engineer");await after("async","a","software-engineer",'<task id="child" state="running"></task>');
await hooks.event({event:{type:"session.idle",properties:{sessionID:"child"}}});
try{await before("async","b","qa-engineer");throw Error("idle released task");}
catch(e){if(!e.message.includes("BEEFORGE_ACTIVE")) throw e;}
await hooks.event({event:{type:"message.part.updated",properties:{part:{sessionID:"async",type:"tool",tool:"task",callID:"a",state:{status:"completed",input:{subagent_type:"software-engineer"},output:packet("DONE")}}}}});
await before("async","b","qa-engineer");

await before("unknown","a","software-engineer");await after("unknown","a","software-engineer","");
try{await before("unknown","b","qa-engineer");throw Error("empty result treated as success");}
catch(e){if(!e.message.includes("BEEFORGE_ACTIVE")) throw e;}

// Restart: hydrate real OpenCode message/part shapes and retain repair budgets.
let rows=[{info:{id:"u",role:"user"},parts:[]},{info:{id:"a",role:"assistant"},parts:[
 {type:"tool",tool:"task",callID:"dev",state:{status:"completed",input:{subagent_type:"software-engineer"},output:packet("DONE")}},
 {type:"tool",tool:"task",callID:"qa",state:{status:"completed",input:{subagent_type:"qa-engineer"},output:packet("QA_FAILED",[{id:"D1",reproduce:"click",expected:"works",actual:"broken"}])}}
]}];
const client={session:{messages:async()=>({data:rows})}};
let restarted=await BeeForgeTeamGuard({client,directory:"test"});
await restarted["tool.execute.before"]({tool:"task",sessionID:"restart",callID:"repair"},{args:{subagent_type:"software-engineer",prompt:"fix D1"}});
rows[1].parts.push({type:"tool",tool:"task",callID:"repair",state:{status:"completed",input:{subagent_type:"software-engineer"},output:packet("DONE")}});
restarted=await BeeForgeTeamGuard({client,directory:"test"});
await restarted["tool.execute.before"]({tool:"task",sessionID:"restart",callID:"recheck"},{args:{subagent_type:"qa-engineer",prompt:"verify D1"}});
rows[1].parts.push({type:"tool",tool:"task",callID:"recheck",state:{status:"completed",input:{subagent_type:"qa-engineer"},output:packet("QA_FAILED",[{id:"D2",reproduce:"click",expected:"works",actual:"broken"}])}});
restarted=await BeeForgeTeamGuard({client,directory:"test"});
try{await restarted["tool.execute.before"]({tool:"task",sessionID:"restart",callID:"again"},{args:{subagent_type:"software-engineer",prompt:"again"}});throw Error("restart reset repair budget");}
catch(e){if(!e.message.includes("BEEFORGE_DUPLICATE")) throw e;}
// Old running work blocks a new request only until the old call actually terminates.
rows=[{info:{id:'old-u',role:'user'},parts:[]},{info:{id:'old-a',role:'assistant'},parts:[
  {type:'tool',tool:'task',callID:'old-call',state:{status:'running',input:{subagent_type:'software-engineer'}}}
]},{info:{id:'new-u',role:'user'},parts:[]}];
restarted=await BeeForgeTeamGuard({client,directory:'test'});
try{await restarted['tool.execute.before']({tool:'task',sessionID:'new-turn',callID:'new-call'},{args:{subagent_type:'software-engineer',prompt:'new task'}});throw Error('old active task ignored');}
catch(e){if(!e.message.includes('BEEFORGE_ACTIVE')) throw e;}
rows[1].parts[0].state.status='error';rows[1].parts[0].state.error='User cancelled';
await restarted['tool.execute.before']({tool:'task',sessionID:'new-turn',callID:'new-call'},{args:{subagent_type:'software-engineer',prompt:'new task'}});

// A guard rejection is not an executed specialist and must not consume its budget.
await hooks.event({event:{type:'message.part.updated',properties:{part:{sessionID:'reject',type:'tool',tool:'task',callID:'bad',state:{status:'running',input:{subagent_type:'qa-engineer'}}}}}});
await hooks.event({event:{type:'message.part.updated',properties:{part:{sessionID:'reject',type:'tool',tool:'task',callID:'bad',state:{status:'error',input:{subagent_type:'qa-engineer'},error:'BEEFORGE_ACTIVE_DELEGATION_BLOCKED'}}}}});
await before('reject','good','qa-engineer');

// SDK failure fails closed instead of interpreting unavailable history as empty history.
const unavailable=await BeeForgeTeamGuard({client:{session:{messages:async()=>({error:{message:'offline'}})}}});
try{await unavailable['tool.execute.before']({tool:'task',sessionID:'offline',callID:'a'},{args:{subagent_type:'software-engineer',prompt:'work'}});throw Error('unavailable state allowed work');}
catch(e){if(!e.message.includes('BEEFORGE_STATE_UNAVAILABLE')) throw e;}
await before('vague-qa','d','software-engineer');await after('vague-qa','d','software-engineer',packet('DONE'));
await before('vague-qa','q','qa-engineer');await after('vague-qa','q','qa-engineer',packet('QA_FAILED',[{id:'missing-evidence'}]));
try{await before('vague-qa','again','software-engineer');throw Error('Vague QA reopened implementation');}
catch(e){if(!e.message.includes('BEEFORGE_DUPLICATE')) throw e;}
await before('secret','d','software-engineer');await after('secret','d','software-engineer','<task state="completed"><task_result>{"password":"do-not-forward"}</task_result></task>');
const forwarded={args:{subagent_type:'qa-engineer',prompt:'verify'}};
await hooks['tool.execute.before']({tool:'task',sessionID:'secret',callID:'q'},forwarded);
if(forwarded.args.prompt.includes('do-not-forward')) throw Error('Credential forwarded');
console.log("TEAM_GUARD_SELF_TEST_OK");
