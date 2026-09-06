// demo_teams.sql 을 첫인상 케미 방(mode = first_impression)으로 다시 만든다.
//
// - teams insert 에 mode 컬럼·값을 넣는다.
// - completed 방은 chemistry_snapshot + roster 로 runTeam(first_impression) 을
//   돌려 result_payload 를 다시 계산한다 (조화도+보완도+닮은 정도, 사분위 등급).
// - 베스트 쌍이 바뀌면 team_matches 의 두 사용자와 team_messages 의 발신자를
//   새 쌍으로 맞춘다 (대화 본문은 그대로).
// - 방 제목은 인자 없이 두면 그대로, `--retitle` 을 주면 아래 표로 바꾼다
//   (iOS 화면에 '궁합' 단어가 뜨지 않게).
// - `--schema2`: snapshot 의 인물 body 를 리포트 스키마 2 로 다시 만든다. 인물마다
//   AAF 실측 얼굴(tools/face_shape_ml/out/aaf_landmarks.f32, 성별·나이대 일치)을
//   userId 해시로 하나 골라 landmarks 로 넣고, 계측·대칭은 그 좌표에서 엔진
//   (runMetrics/runSymmetry)으로 다시 계산한다 — body 안의 값이 서로 맞는다.
//   thumbnailKey 는 그대로(사진은 인물 사진, 좌표는 AAF 얼굴 — 방 화면은 mesh 를 안 그린다).
//   인물(dddddddd-…)의 내 얼굴 카드(metrics 행)도 같은 body 로 넣는다 — 쌍 상세용.
//
// 실행: cd web && pnpm build:shared && node db/tests/regen_first_impression_seed.mjs [--retitle] [--schema2]
// 입력·출력 모두 db/tests/demo_teams.sql (제자리 갱신).

import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

globalThis.self = globalThis;
globalThis.window = globalThis;
const here = dirname(fileURLToPath(import.meta.url));
await import(join(here, "../../app/lib/shared/face_engine.js"));

const RETITLE = process.argv.includes("--retitle");
const SCHEMA2 = process.argv.includes("--schema2");

// ── AAF 좌표 풀 (--schema2) ──
const AAF_DIR = join(here, "../../../tools/face_shape_ml/out");
let aafPool = null;
function loadAaf() {
  if (aafPool) return aafPool;
  const buf = readFileSync(join(AAF_DIR, "aaf_landmarks.f32"));
  const f32 = new Float32Array(buf.buffer, buf.byteOffset, buf.byteLength / 4);
  const meta = readFileSync(join(AAF_DIR, "aaf_landmarks_meta.csv"), "utf8").trim().split("\n").slice(1);
  aafPool = meta.map((line, r) => {
    const [, gender, age] = line.split(",");
    return { gender, age: Number(age), row: r };
  });
  aafPool.f32 = f32;
  return aafPool;
}
function ageRange(ageGroup) {
  const m = /^(\d\d)s$/.exec(ageGroup);
  if (!m) return [20, 49];
  const lo = Number(m[1]);
  return [lo, lo + 9];
}
function hash32(str) {
  let h = 2166136261;
  for (const ch of str) h = Math.imul(h ^ ch.charCodeAt(0), 16777619) >>> 0;
  return h;
}
/** 인물 body → 스키마 2 body (AAF 얼굴 좌표 + 재계산 계측·대칭 + 모델 버전). */
function toSchema2(userId, body, offset = 0) {
  const pool = loadAaf();
  const [lo, hi] = ageRange(body.ageGroup);
  let cands = pool.filter((p) => p.gender === body.gender && p.age >= lo && p.age <= hi);
  if (cands.length === 0) cands = pool.filter((p) => p.gender === body.gender);
  const pick = cands[(hash32(userId) + offset) % cands.length];
  const base = pick.row * 936;
  const landmarks = [];
  for (let i = 0; i < 468; i++) {
    landmarks.push([
      Math.round(pool.f32[base + 2 * i] * 10000) / 10000,
      Math.round(pool.f32[base + 2 * i + 1] * 10000) / 10000,
    ]);
  }
  const pts = JSON.stringify(landmarks);
  const metrics = JSON.parse(globalThis.runMetrics(pts, 1));
  const symmetry = JSON.parse(globalThis.runSymmetry(pts, 1));
  // kind 는 넣었다 뺀 필드(카드는 종류가 없다) — 옛 seed 에 남아 있으면 지운다.
  const { lateralMetrics: _lm, thumbnailPath: _tp, isMyFace: _my, kind: _kind, ...rest } = body;
  return {
    ...rest,
    schemaVersion: 2,
    metrics,
    symmetry,
    modelVersion: JSON.parse(globalThis.modelVersions()),
    landmarks,
  };
}
const TITLES = {
  "천생연분 궁합이면 커피 한잔 같이해요.": "첫인상 케미 맞으면 커피 한잔 같이해요.",
  "천생연분 궁합이면 전시회 한번 같이 가요.": "첫인상 케미 맞으면 전시회 한번 같이 가요.",
};

const path = join(here, "demo_teams.sql");
const original = readFileSync(path, "utf8");
let sql = original;
const DEMO_UID = "09434d9c-7aa6-4e38-a687-369fedd6dc48"; // 데모 계정(홍청)

// ── 1) teams insert 블록 ──
const teamRe =
  /insert into public\.teams \(id, owner_id, title, password, room_kind, (?:mode, )?max_players,\n\s+age_min, age_max, status, views,\n\s+started_at, closed_at, created_at, updated_at,\n\s+chemistry_snapshot, result_payload\) values \(\n([\s\S]*?)\);\n/g;

// ── --schema2: 데모 계정의 AAF 얼굴 선택 ──
// 심사 데모는 데모 계정이 참여한 completed 방마다 베스트 쌍 당사자여야 한다
// (매칭 카드·채팅이 보이도록). 다른 인물 얼굴은 고정하고 데모 계정 얼굴만
// 후보를 차례로 바꿔 가며 그 조건을 처음 만족하는 얼굴을 쓴다.
let demoOffset = 0;
function parseSnap(line) {
  return JSON.parse(line.trim().replace(/^\$j\$/, "").replace(/\$j\$::jsonb,?$/, ""));
}
function payloadOf(teamId, roomKind, snapshot) {
  const roster = rosterOf(teamId);
  const players = roster
    .filter((r) => snapshot[r.userId])
    .map((r) => ({ slot: r.slot, name: r.alias, gender: r.gender, body: snapshot[r.userId] }));
  const blocked = Array.isArray(snapshot.blocked) ? snapshot.blocked : [];
  const chatted = Array.isArray(snapshot.chatted) ? snapshot.chatted : [];
  return { roster, payload: JSON.parse(
    globalThis.runTeam(JSON.stringify({ roomKind, mode: "first_impression", players, blocked, chatted })),
  ) };
}
if (SCHEMA2) {
  const teamRe0 = new RegExp(teamRe.source, "g");
  const rooms = [];
  let m;
  while ((m = teamRe0.exec(original))) {
    const lines = m[1].split("\n");
    const teamId = lines[0].match(/^\s*'([0-9a-f-]{36})'/)[1];
    const km = lines[1].match(/^\s*'(all|match)', (?:'first_impression', )?\d+, \d+, \d+, '(\w+)',/);
    if (km[2] !== "completed" || !lines[3].includes("$j$")) continue;
    const snap = parseSnap(lines[3]);
    if (!snap[DEMO_UID]) continue;
    // 원본에서 데모 계정이 매칭(베스트)이던 방만 조건에 넣는다 — 나머지 방은 원래도 당사자가 아니었다.
    const matchRe = new RegExp(`\\('${teamId}', '([0-9a-f-]{36})', '([0-9a-f-]{36})', `);
    const mm = original.match(matchRe);
    if (!mm || (mm[1] !== DEMO_UID && mm[2] !== DEMO_UID)) continue;
    rooms.push({ teamId, roomKind: km[1], snap });
  }
  outer: for (let off = 0; off < 400; off++) {
    for (const room of rooms) {
      const snap = {};
      for (const k of Object.keys(room.snap)) {
        snap[k] = k === "blocked" || k === "chatted" ? room.snap[k]
          : toSchema2(k, room.snap[k], k === DEMO_UID ? off : 0);
      }
      const { roster, payload } = payloadOf(room.teamId, room.roomKind, snap);
      const first = payload.pairs.find((p) => !p.bypass) ?? payload.pairs[0];
      const ids = [roster.find((r) => r.slot === first.a).userId, roster.find((r) => r.slot === first.b).userId];
      if (!ids.includes(DEMO_UID)) continue outer;
    }
    demoOffset = off;
    break;
  }
  console.log(`demo face offset = ${demoOffset} (rooms with demo: ${rooms.length})`);
}

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
  // 이미 mode 가 들어간 파일(재실행)도 받는다 — idempotent.
  const km = lines[1].match(/^\s*'(all|match)', (?:'first_impression', )?(\d+), (\d+), (\d+), '(\w+)', (\d+),$/);
  if (!km) throw new Error("teams 둘째 줄 파싱 실패: " + lines[1]);
  const roomKind = km[1];
  const status = km[5];
  if (!lines[1].includes("'first_impression'")) {
    lines[1] = lines[1].replace(`'${roomKind}', `, `'${roomKind}', 'first_impression', `);
  }

  // snapshot / payload — 마지막 두 줄 ($j$…$j$::jsonb 또는 null)
  const snapLine = lines[3];
  const payLine = lines[4];
  let newPayLine = payLine;
  let best = null;
  if (snapLine.includes("$j$")) {
    const snapshot = JSON.parse(snapLine.trim().replace(/^\$j\$/, "").replace(/\$j\$::jsonb,?$/, ""));
    if (SCHEMA2) {
      for (const k of Object.keys(snapshot)) {
        if (k === "blocked" || k === "chatted") continue;
        snapshot[k] = toSchema2(k, snapshot[k], k === DEMO_UID ? demoOffset : 0);
      }
      lines[3] = `  $j$${JSON.stringify(snapshot)}$j$::jsonb,`;
    }
  }
  if (status === "completed" && snapLine.includes("$j$")) {
    const snapshot = JSON.parse(lines[3].trim().replace(/^\$j\$/, "").replace(/\$j\$::jsonb,?$/, ""));
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
const star = (b) => (b && (b.a.userId === DEMO_UID || b.b.userId === DEMO_UID) ? "  ⭐ 데모 계정(홍청)이 당사자" : "");
sql = sql.replace(
  /-- 만드는 방[^\n]*\n[\s\S]*?\n\n/,
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

// ── --schema2: 인물(dddddddd-…) metrics 행 ──
// 쌍 상세는 참가자의 내 얼굴 카드 id 를 서버에서 묻는다. 인물은 실계정이 아니라
// 다시 찍을 수 없으니 snapshot 과 같은 body 로 카드 행을 seed 가 직접 만든다
// (id 고정, my-face 1행 규칙 유지). 실계정(데모 계정 포함)은 건드리지 않는다.
if (SCHEMA2) {
  const bodies = new Map();
  for (const m of sql.matchAll(/\$j\$(\{"blocked"[\s\S]*?\})\$j\$::jsonb/g)) {
    const snap = JSON.parse(m[1]);
    for (const [uid, body] of Object.entries(snap)) {
      if (uid === "blocked" || uid === "chatted" || !uid.startsWith("dddddddd-")) continue;
      if (!bodies.has(uid)) bodies.set(uid, body);
    }
  }
  const rows = [...bodies.entries()].map(([uid, body]) => {
    const n = uid.slice(-2);
    const id = `dddddddd-0000-4000-8000-1000000000${n}`;
    return `delete from public.metrics where user_id = '${uid}' and is_my_face;\n` +
      `insert into public.metrics (id, user_id, body, is_my_face) values\n` +
      `  ('${id}', '${uid}', $b$${JSON.stringify(body)}$b$, true)\n` +
      `  on conflict (id) do update set body = excluded.body, is_my_face = true, updated_at = now();`;
  });
  const block =
    "-- ── 인물 metrics (schema 2) — 쌍 상세용 내 얼굴 카드, snapshot 과 같은 body ──\n" +
    rows.join("\n") +
    "\n-- ── /인물 metrics ──\n";
  const blockRe = /-- ── 인물 metrics \(schema 2\)[\s\S]*?-- ── \/인물 metrics ──\n/;
  if (blockRe.test(sql)) {
    sql = sql.replace(blockRe, block);
  } else {
    // commit; 뒤에 확인용 select 가 붙어 있어 파일 끝이 아니라 첫 commit; 앞에 넣는다.
    sql = sql.replace(/\ncommit;\n/, `\n${block}\ncommit;\n`);
  }
  console.log(`persona metrics rows: ${rows.length}`);
}

writeFileSync(path, sql);
for (const s of summary) {
  console.log(s.title, s.status, s.best ? `best ${aliasOf(s.best.a)}×${aliasOf(s.best.b)} ${s.best.score}/300` : "");
}
