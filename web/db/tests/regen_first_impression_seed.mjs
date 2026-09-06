// demo_teams.sql 을 첫인상 케미 방(mode = first_impression)으로 다시 만든다.
//
// - teams insert 에 mode 컬럼·값을 넣는다.
// - completed 방은 chemistry_snapshot + roster 로 runTeam(first_impression) 을
//   돌려 result_payload 를 다시 계산한다 (조화도+보완도+닮은 정도, 사분위 등급).
// - 베스트 쌍이 바뀌면 team_matches 의 두 사용자와 team_messages 의 발신자를
//   새 쌍으로 맞춘다 (대화 본문은 그대로).
// - 방 제목은 인자 없이 두면 그대로, `--retitle` 을 주면 아래 표로 바꾼다
//   (iOS 화면에 '궁합' 단어가 뜨지 않게).
//
// 실행: cd web && pnpm build:shared && node db/tests/regen_first_impression_seed.mjs [--retitle]
// 입력·출력 모두 db/tests/demo_teams.sql (제자리 갱신).

import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

globalThis.self = globalThis;
globalThis.window = globalThis;
const here = dirname(fileURLToPath(import.meta.url));
await import(join(here, "../../app/lib/shared/face_engine.js"));

const RETITLE = process.argv.includes("--retitle");
const TITLES = {
  "천생연분 궁합이면 커피 한잔 같이해요.": "첫인상 케미 맞으면 커피 한잔 같이해요.",
  "천생연분 궁합이면 전시회 한번 같이 가요.": "첫인상 케미 맞으면 전시회 한번 같이 가요.",
};

const path = join(here, "demo_teams.sql");
const original = readFileSync(path, "utf8");
let sql = original;

// ── 1) teams insert 블록 ──
const teamRe =
  /insert into public\.teams \(id, owner_id, title, password, room_kind, max_players,\n\s+age_min, age_max, status, views,\n\s+started_at, closed_at, created_at, updated_at,\n\s+chemistry_snapshot, result_payload\) values \(\n([\s\S]*?)\);\n/g;

const summary = [];
const matchRewrites = [];
function rewriteMatch(teamId, userA, userB) {
  matchRewrites.push({ teamId, userA, userB });
}
sql = sql.replace(teamRe, (block, body) => {
  const lines = body.split("\n");
  // line0: id, owner, title, password
  // line1: room_kind, max_players, age_min, age_max, status, views,
  const idm = lines[0].match(/^\s*'([0-9a-f-]{36})', '([0-9a-f-]{36})', '([^']*)', (null|'[^']*'),$/);
  if (!idm) throw new Error("teams 첫 줄 파싱 실패: " + lines[0]);
  const [, teamId, ownerId, title] = idm;
  const newTitle = RETITLE ? (TITLES[title] ?? title) : title;
  lines[0] = lines[0].replace(`'${title}'`, `'${newTitle}'`);
  const km = lines[1].match(/^\s*'(all|match)', (\d+), (\d+), (\d+), '(\w+)', (\d+),$/);
  if (!km) throw new Error("teams 둘째 줄 파싱 실패: " + lines[1]);
  const roomKind = km[1];
  const status = km[5];
  lines[1] = lines[1].replace(`'${roomKind}', `, `'${roomKind}', 'first_impression', `);

  // snapshot / payload — 마지막 두 줄 ($j$…$j$::jsonb 또는 null)
  const snapLine = lines[3];
  const payLine = lines[4];
  let newPayLine = payLine;
  let best = null;
  if (status === "completed" && snapLine.includes("$j$")) {
    const snapshot = JSON.parse(snapLine.trim().replace(/^\$j\$/, "").replace(/\$j\$::jsonb,?$/, ""));
    const roster = rosterOf(teamId);
    const players = roster
      .filter((r) => snapshot[r.userId])
      .map((r) => ({ slot: r.slot, name: r.alias, gender: r.gender, body: snapshot[r.userId] }));
    const blocked = Array.isArray(snapshot.blocked) ? snapshot.blocked : [];
    const chatted = Array.isArray(snapshot.chatted) ? snapshot.chatted : [];
    const payload = JSON.parse(
      globalThis.runTeam(JSON.stringify({ roomKind, mode: "first_impression", players, blocked, chatted })),
    );
    newPayLine = `  $j$${JSON.stringify(payload)}$j$::jsonb`;
    const first = payload.pairs.find((p) => !p.bypass) ?? payload.pairs[0];
    const ua = roster.find((r) => r.slot === first.a);
    const ub = roster.find((r) => r.slot === first.b);
    best = { a: ua, b: ub, score: first.score, pairs: payload.pairs.length };
    rewriteMatch(teamId, ua.userId, ub.userId);
  }
  lines[4] = newPayLine;
  summary.push({ title: newTitle, status, roomKind, best });
  const headerCols =
    "insert into public.teams (id, owner_id, title, password, room_kind, mode, max_players,\n" +
    "                          age_min, age_max, status, views,\n" +
    "                          started_at, closed_at, created_at, updated_at,\n" +
    "                          chemistry_snapshot, result_payload) values (\n";
  return headerCols + lines.join("\n") + ");\n";
});

// ── roster / match 헬퍼 (원본 sql 텍스트 기준) ──
function rosterOf(teamId) {
  const re = new RegExp(
    `\\('${teamId}', '([0-9a-f-]{36})', (\\d+), '(male|female)', '([^']*)', (true|false), now\\(\\)`,
    "g",
  );
  const out = [];
  let m;
  while ((m = re.exec(original))) {
    out.push({ userId: m[1], slot: Number(m[2]), gender: m[3], alias: m[4] });
  }
  return out;
}

for (const { teamId, userA, userB } of matchRewrites) {
  const re = new RegExp(`\\('${teamId}', '([0-9a-f-]{36})', '([0-9a-f-]{36})', (null|true|false), (null|true|false), `);
  const m = sql.match(re);
  if (!m) continue;
  const [oldA, oldB] = [m[1], m[2]];
  if ((oldA === userA && oldB === userB) || (oldA === userB && oldB === userA)) continue;
  // team_matches 두 사용자 교체
  sql = sql.replace(re, `('${teamId}', '${userA}', '${userB}', ${m[3]}, ${m[4]}, `);
  // team_messages 발신자 — 옛 쌍 → 새 쌍 (순서 보존)
  const msgRe = new RegExp(`\\('([0-9a-f-]{36})', '${teamId}', '(${oldA}|${oldB})', `, "g");
  sql = sql.replace(msgRe, (s, id, sender) => `('${id}', '${teamId}', '${sender === oldA ? userA : userB}', `);
  console.log(`match rewritten: ${teamId} ${oldA}×${oldB} → ${userA}×${userB}`);
}

// ── 헤더 주석 갱신 ──
const aliasOf = (r) => (r ? r.alias : "?");
const DEMO_UID = "09434d9c-7aa6-4e38-a687-369fedd6dc48"; // 데모 계정(홍청)
const star = (b) => (b && (b.a.userId === DEMO_UID || b.b.userId === DEMO_UID) ? "  ⭐ 데모 계정(홍청)이 당사자" : "");
sql = sql.replace(
  /-- 만드는 방:[\s\S]*?\n\n/,
  "-- 만드는 방 (mode = first_impression, payload 는 regen_first_impression_seed.mjs 로 재계산):\n" +
    summary
      .map((s) =>
        s.best
          ? `--   ${s.title} — ${s.roomKind} ${s.status}\n--       베스트 = ${aliasOf(s.best.a)} × ${aliasOf(s.best.b)} 케미 ${s.best.score}/300 / ${s.best.pairs}쌍 전부 채점${star(s.best)}\n`
          : `--   ${s.title} — ${s.roomKind} ${s.status}\n`,
      )
      .join("") +
    "\n",
);
if (RETITLE) {
  for (const [from, to] of Object.entries(TITLES)) sql = sql.split(`-- ── ${from}`).join(`-- ── ${to}`);
}

writeFileSync(path, sql);
for (const s of summary) {
  console.log(s.title, s.status, s.best ? `best ${aliasOf(s.best.a)}×${aliasOf(s.best.b)} ${s.best.score}/300` : "");
}
