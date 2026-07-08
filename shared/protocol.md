# PetOS WebSocket protocol

Transport: JSON objects over a single WebSocket at `ws://127.0.0.1:8765/ws?token=<TOKEN>`.
The token lives in `~/.petos/token` (0600). The Python sidecar prints a
`PETOS_READY ws://... token=...` line on stdout at startup; the macOS app parses it.

Every message is a JSON object with a `type` field.

## App -> sidecar (commands)

| type | fields | meaning |
|---|---|---|
| `subscribe` | - | request a fresh `snapshot` |
| `list_agents` | - | request `agents` |
| `create_agent` | `agent{name,role,type,rank,config?}` | create an agent |
| `delete_agent` | `id` | delete an agent |
| `update_agent` | `id`, `patch{name?,status?,visible?,rank?,config?}` | mutate an agent (pause/resume, hide/show, rename) |
| `add_skill` | `agentId`, `skill{name,trigger,tools[],prompt}` | attach a skill |
| `remove_skill` | `skillId` | remove a skill |
| `chat` | `text` | message the manager |
| `suggestion_action` | `id`, `action` = `approve`\|`dismiss` | approve starts a managed read-only work item; dismiss closes it |
| `get_settings` | - | request `settings` |
| `update_settings` | `patch{provider?,model?,...}` | change settings |
| `set_api_key` | `provider`, `key` | store a key in the Keychain |
| `list_ollama_models` | - | request `ollama_models` |
| `frontmost` | `app`, `bundleId` | app reports the focused application |
| `system` | `state` = `sleep`\|`wake` | pause/resume agents on laptop sleep/wake |

## Sidecar -> app (events)

| type | fields | meaning |
|---|---|---|
| `snapshot` | `agents[],suggestions[],workItems[],agentMemory[],messages[],settings,safeMode,tools[]` | full initial state |
| `agents` | `agents[]` | full agent list |
| `agent_update` | `agent` | one agent changed (status/visibility) |
| `agent_activity` | `activity` | live per-agent activity for overlays and dashboards |
| `agent_memory` | `memory` | compact local handoff shared between agents |
| `work_item` | `workItem` | approved suggestion created a work item |
| `work_item_update` | `workItem` | work item status/result changed |
| `suggestion` | `suggestion` | a new suggestion |
| `suggestion_update` | `suggestion` | a suggestion changed status |
| `chat` | `message{sender,text,createdAt}` | manager reply |
| `settings` | `settings` | current settings (`keys` shows which providers have a key; never the key itself) |
| `ollama_models` | `models[]` | local model names |
| `log` | `level`, `text` | diagnostic |
| `error` | `text` | command error |

## Objects

- Agent: `{id,name,role[manager|worker],type[files|news|editor|custom],rank[newbie|senior],status[alive|sleeping|working|paused],visible,config,skills[],createdAt}`
- Skill: `{id,agentId,name,trigger[schedule|appFocus|manual],tools[],prompt}`
- Suggestion: `{id,agentId,title,body,proposedAction,score,status[new|approved|dismissed],createdAt}`
- WorkItem: `{id,suggestionId,agentId,title,objective,status[queued|working|completed|failed],result,createdAt,updatedAt}`
- AgentMemory: `{id,sourceAgentId,targetAgentId,topic,title,summary,kind[suggestion|approved_work|handoff],tokenEstimate,createdAt}`
- AgentActivity: `{agentId,phase[observing|reading_files|checking_editor|researching_web|thinking|sharing_context|suggestion_found|work_started|work_complete|waiting|error],title,detail,createdAt}`

## Read-only guarantee (phase 1)

`safeMode` is `readonly`. `tools[]` lists the only callable tools:
`list_dir, read_file, stat, frontmost_app, web_fetch`. No write/move/delete/exec
tool exists in the sidecar, and the tool registry refuses any unlisted name.

Approving a suggestion starts manager-coordinated read-only work. The result is
saved as a compact `AgentMemory` handoff so other agents can reuse that local
summary instead of replaying full conversations into future prompts.
