import { useEffect, useRef, useState } from "react";
import type { Session, SupabaseClient } from "@supabase/supabase-js";
import type { TeamShowcase } from "../lib/supabase";
import { detectInApp, openInExternalBrowser, type InApp } from "../lib/inapp";
import {
  cleanAuthParams,
  fetchNickname,
  getSupabase,
  loginWithKakao,
} from "../lib/auth";
import {
  dataUrlToBlob,
  isTeamOpen,
  joinTeam,
  saveCapture,
  type WebCaptureBody,
} from "../lib/join";

/**
 * /g/:id 참여 위저드 — 앱 미설치자가 브라우저에서 그룹 참여를 끝까지 완료한다.
 * entry → (kakao) → name → info → camera → saving → done
 * 미리보기 경로: entry → info → camera → done(teaser) → [참여] → stash → kakao → name…
 * 스펙: docs/superpowers/specs/2026-07-12-web-join-upgrade-design.md
 *
 * 전부 client-only — getUserMedia·tasks-vision·face_engine.js 는 dynamic import.
 * `<video>` 는 위저드 생애 내내 마운트(카메라 단계 외 비표시) — ref race 제거.
 * ⚠️ 카톡 인앱 브라우저에선 getUserMedia 가 막히므로 외부 브라우저 탈출이 선행.
 */

// package.json 의 @mediapipe/tasks-vision 과 같은 버전으로 유지.
const MP_VERSION = "0.10.35";
const MP_WASM = `https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@${MP_VERSION}/wasm`;
const MP_MODEL =
  "https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task";

const STASH_KEY = "facely:pendingJoin";
const NO_FACE_TIMEOUT_MS = 20_000;

type Stage = "entry" | "name" | "info" | "camera" | "saving" | "done" | "error";

type Teaser =
  | { kind: "pair"; total: number; labelKo: string; ownerName: string }
  | { kind: "solo"; primaryLabel: string; catchphrase: string };

/** 미리보기→카카오 redirect 사이 캡처 보존 (sessionStorage). */
type Stash = { teamId: string; body: WebCaptureBody; thumb: string | null };

const GENDERS: { v: string; ko: string }[] = [
  { v: "male", ko: "남성" },
  { v: "female", ko: "여성" },
];
const AGES: { v: string; ko: string }[] = [
  { v: "10s", ko: "10대" },
  { v: "20s", ko: "20대" },
  { v: "30s", ko: "30대" },
  { v: "40s", ko: "40대" },
  { v: "50s", ko: "50대" },
  { v: "60s", ko: "60대+" },
];

export function JoinWizard({
  team,
  appOpenUrl,
  appStoreUrl,
  playStoreUrl,
  supabaseUrl,
  supabaseAnonKey,
}: {
  team: TeamShowcase;
  appOpenUrl: string;
  appStoreUrl: string;
  playStoreUrl: string;
  supabaseUrl: string;
  supabaseAnonKey: string;
}) {
  const [stage, setStage] = useState<Stage>("entry");
  const [previewOnly, setPreviewOnly] = useState(false);
  const [session, setSession] = useState<Session | null>(null);
  const [nickname, setNickname] = useState("");
  const [nameInput, setNameInput] = useState("");
  const [gender, setGender] = useState<string | null>(null);
  const [age, setAge] = useState<string | null>(null);
  const [teaser, setTeaser] = useState<Teaser | null>(null);
  const [joined, setJoined] = useState(false);
  const [hint, setHint] = useState("얼굴을 화면 안에 맞춰 주세요");
  const [notice, setNotice] = useState("");
  const [errorMsg, setErrorMsg] = useState("");
  // 인앱 브라우저 — 카톡 웹뷰는 카메라가 막혀 외부 브라우저로 탈출해야 한다.
  const [inApp, setInApp] = useState<InApp>(null);

  const sbRef = useRef<SupabaseClient | null>(null);
  const sessionRef = useRef<Session | null>(null);
  const videoRef = useRef<HTMLVideoElement>(null);
  const streamRef = useRef<MediaStream | null>(null);
  const landmarkerRef = useRef<unknown>(null);
  const preloadRef = useRef<Promise<void> | null>(null);
  const rafRef = useRef<number | null>(null);
  const hitsRef = useRef(0);
  const doneRef = useRef(false);
  const noFaceTimerRef = useRef<number | null>(null);
  // 캡처 산출물 — 단계를 넘어도 유지 (name-taken 재시도 시 metrics 재사용).
  const bodyRef = useRef<WebCaptureBody | null>(null);
  const thumbRef = useRef<Blob | null>(null);
  const metricsIdRef = useRef<string | null>(null);

  function sb(): SupabaseClient {
    if (!sbRef.current) {
      sbRef.current = getSupabase(supabaseUrl, supabaseAnonKey);
    }
    return sbRef.current;
  }

  // 마운트: 인앱 감지 + 세션 복구 + OAuth 복귀/stash 처리.
  useEffect(() => {
    setInApp(detectInApp());
    if (!supabaseUrl || !supabaseAnonKey) return;
    const cameFromLogin = cleanAuthParams();
    const client = sb();
    const { data: sub } = client.auth.onAuthStateChange((_e, s) => {
      sessionRef.current = s;
      setSession(s);
      if (s) {
        void fetchNickname(client, s.user.id).then((n) => {
          setNickname(n);
          setNameInput((cur) => cur || n);
        });
      }
    });
    void client.auth.getSession().then(({ data }) => {
      sessionRef.current = data.session;
      setSession(data.session);
      if (!data.session) return;
      void fetchNickname(client, data.session.user.id).then((n) => {
        setNickname(n);
        setNameInput((cur) => cur || n);
      });
      // 미리보기→로그인 복귀: 캡처를 복원하고 이름 선택으로 점프.
      const raw = sessionStorage.getItem(STASH_KEY);
      if (raw) {
        sessionStorage.removeItem(STASH_KEY);
        try {
          const stash = JSON.parse(raw) as Stash;
          if (stash.teamId === team.id) {
            bodyRef.current = stash.body;
            thumbRef.current = stash.thumb ? dataUrlToBlob(stash.thumb) : null;
            setGender(stash.body.gender);
            setAge(stash.body.ageGroup);
            setPreviewOnly(false);
            setStage("name");
          }
        } catch {
          /* 손상된 stash 는 버림 */
        }
      } else if (cameFromLogin) {
        // [카카오로 참여하기] 로 로그인만 하고 복귀 — 바로 이름 선택.
        setStage("name");
      }
    });
    return () => sub.subscription.unsubscribe();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => () => stopCamera(), []);

  function stopCamera() {
    if (rafRef.current != null) cancelAnimationFrame(rafRef.current);
    rafRef.current = null;
    if (noFaceTimerRef.current != null) clearTimeout(noFaceTimerRef.current);
    noFaceTimerRef.current = null;
    streamRef.current?.getTracks().forEach((t) => t.stop());
    streamRef.current = null;
  }

  function fail(msg: string) {
    stopCamera();
    setErrorMsg(msg);
    setStage("error");
  }

  /** MediaPipe + shared engine 로드 — info 단계 진입 시 1회 백그라운드 시작. */
  function preloadDetector(): Promise<void> {
    if (!preloadRef.current) {
      preloadRef.current = (async () => {
        await import("../lib/shared/face_engine.js");
        const { FaceLandmarker, FilesetResolver } = await import(
          "@mediapipe/tasks-vision"
        );
        const fileset = await FilesetResolver.forVisionTasks(MP_WASM);
        landmarkerRef.current = await FaceLandmarker.createFromOptions(
          fileset,
          {
            baseOptions: { modelAssetPath: MP_MODEL },
            runningMode: "VIDEO",
            numFaces: 1,
          },
        );
      })();
      // 실패 시 다음 호출에서 재시도할 수 있게 리셋.
      preloadRef.current.catch(() => {
        preloadRef.current = null;
      });
    }
    return preloadRef.current;
  }

  async function startCamera() {
    doneRef.current = false;
    hitsRef.current = 0;
    setHint("얼굴 인식 준비 중…");
    setStage("camera");
    let stream: MediaStream;
    try {
      stream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: "user", width: 640, height: 480 },
        audio: false,
      });
    } catch {
      fail("카메라를 열 수 없어요. 브라우저의 카메라 권한을 허용해 주세요.");
      return;
    }
    streamRef.current = stream;
    const video = videoRef.current;
    if (!video) {
      fail("카메라 화면을 준비하지 못했어요. 새로고침 후 다시 시도해 주세요.");
      return;
    }
    video.srcObject = stream;
    await video.play().catch(() => {});
    try {
      await preloadDetector();
    } catch {
      fail("얼굴 인식 모듈을 불러오지 못했어요. 잠시 후 다시 시도해 주세요.");
      return;
    }
    setHint("얼굴을 화면 안에 맞춰 주세요");
    noFaceTimerRef.current = window.setTimeout(
      () => setHint("얼굴이 안 보여요. 밝은 곳에서 정면을 맞춰 주세요."),
      NO_FACE_TIMEOUT_MS,
    );
    loop();
  }

  function loop() {
    const video = videoRef.current;
    const landmarker = landmarkerRef.current as {
      detectForVideo: (
        v: HTMLVideoElement,
        t: number,
      ) => { faceLandmarks: { x: number; y: number }[][] };
    } | null;
    if (!video || !landmarker || doneRef.current) return;
    if (video.readyState >= 2) {
      const res = landmarker.detectForVideo(video, performance.now());
      const face = res.faceLandmarks?.[0];
      if (face && face.length >= 468) {
        hitsRef.current += 1;
        setHint("좋아요! 잠시만 그대로…");
        // 3 프레임 연속 검출되면 안정으로 보고 캡처.
        if (hitsRef.current >= 3) {
          doneRef.current = true;
          void capture(face.map((p) => [p.x, p.y]));
          return;
        }
      } else {
        hitsRef.current = 0;
        setHint("얼굴을 화면 안에 맞춰 주세요");
      }
    }
    rafRef.current = requestAnimationFrame(loop);
  }

  /** 검출 순간의 video 프레임 → 200×200 미러 crop JPEG (앱 썸네일과 동급). */
  function frameToThumb(video: HTMLVideoElement): Promise<Blob | null> {
    const side = Math.min(video.videoWidth, video.videoHeight);
    if (!side) return Promise.resolve(null);
    const sx = (video.videoWidth - side) / 2;
    const sy = (video.videoHeight - side) / 2;
    const c = document.createElement("canvas");
    c.width = 200;
    c.height = 200;
    const ctx = c.getContext("2d");
    if (!ctx) return Promise.resolve(null);
    ctx.translate(200, 0);
    ctx.scale(-1, 1);
    ctx.drawImage(video, sx, sy, side, side, 0, 0, 200, 200);
    return new Promise((r) => c.toBlob(r, "image/jpeg", 0.8));
  }

  async function capture(points: number[][]) {
    const video = videoRef.current;
    const thumb = video ? await frameToThumb(video) : null;
    stopCamera();
    let body: WebCaptureBody;
    try {
      const metrics = JSON.parse(
        globalThis.runMetrics(JSON.stringify(points)),
      ) as Record<string, number>;
      body = {
        schemaVersion: 1,
        ethnicity: "eastAsian",
        gender: gender ?? "male",
        ageGroup: age ?? "30s",
        timestamp: new Date().toISOString(),
        source: "camera",
        metrics,
        lateralMetrics: null,
        faceShape: "oval",
      };
    } catch {
      fail("측정값을 계산하지 못했어요. 다시 시도해 주세요.");
      return;
    }
    bodyRef.current = body;
    thumbRef.current = thumb;
    setTeaser(computeTeaser(body));
    if (previewOnly) {
      setJoined(false);
      setStage("done");
    } else {
      await runSave();
    }
  }

  /** 저장 시퀀스: 마감 재확인 → metrics(1회) → 합류. */
  async function runSave() {
    const body = bodyRef.current;
    const s = sessionRef.current;
    if (!body || !s) {
      fail("세션이 만료됐어요. 다시 로그인해 주세요.");
      return;
    }
    setStage("saving");
    const client = sb();
    if (!(await isTeamOpen(client, team.id))) {
      fail("모집이 종료된 그룹입니다.");
      return;
    }
    if (!metricsIdRef.current) {
      metricsIdRef.current = await saveCapture(client, {
        uid: s.user.id,
        nickname,
        body,
        thumb: thumbRef.current,
      });
    }
    if (!metricsIdRef.current) {
      fail("등록에 실패했어요. 잠시 후 다시 시도해 주세요.");
      return;
    }
    const r = await joinTeam(client, {
      teamId: team.id,
      metricsId: metricsIdRef.current,
      name: nameInput.trim(),
    });
    if (r === "name-taken") {
      setNotice(
        "방금 다른 사람이 그 자리에 들어갔어요. 다른 이름으로 참여해 주세요.",
      );
      setStage("name");
      return;
    }
    if (r === "failed") {
      fail("참여에 실패했어요. 잠시 후 다시 시도해 주세요.");
      return;
    }
    setJoined(true);
    setStage("done");
  }

  function computeTeaser(body: WebCaptureBody): Teaser | null {
    try {
      const json = JSON.stringify(body);
      if (team.owner) {
        const c = JSON.parse(
          globalThis.runCompat(json, JSON.stringify(team.owner.raw)),
        ) as { total: number; labelKo: string };
        return {
          kind: "pair",
          total: Math.round(c.total),
          labelKo: c.labelKo,
          ownerName: team.owner.name,
        };
      }
      const s = JSON.parse(globalThis.runEngine(json)) as {
        primaryLabel: string;
        catchphrase: string;
      };
      return {
        kind: "solo",
        primaryLabel: s.primaryLabel,
        catchphrase: s.catchphrase,
      };
    } catch {
      return null;
    }
  }

  // ── 액션 핸들러 ────────────────────────────────────────────────────────
  function onJoinStart() {
    setNotice("");
    if (sessionRef.current) setStage("name");
    else void loginWithKakao(sb());
  }

  function onPreviewStart() {
    setPreviewOnly(true);
    setStage("info");
  }

  function onNameNext() {
    const name = nameInput.trim();
    if (!name) {
      setNotice("이름을 입력하거나 자리를 골라 주세요.");
      return;
    }
    const taken = team.members.some((m) => m.joined && m.name === name);
    if (taken) {
      setNotice("같은 그룹내에 동일이름은 허용하지 않습니다.");
      return;
    }
    setNotice("");
    // 미리보기에서 넘어온 경우 캡처가 이미 있음 → 바로 저장.
    if (bodyRef.current) void runSave();
    else setStage("info");
  }

  function onInfoNext() {
    if (!gender || !age) {
      setNotice("성별과 나이대를 골라 주세요.");
      return;
    }
    setNotice("");
    void startCamera();
  }

  /** 미리보기 결과 → 참여: 캡처를 stash 하고 로그인 (복귀 시 재촬영 없음). */
  function onTeaserJoin() {
    setPreviewOnly(false);
    if (sessionRef.current) {
      setStage("name");
      return;
    }
    const stashAndLogin = async () => {
      let thumbUrl: string | null = null;
      const blob = thumbRef.current;
      if (blob) {
        thumbUrl = await new Promise<string | null>((resolve) => {
          const fr = new FileReader();
          fr.onload = () => resolve(fr.result as string);
          fr.onerror = () => resolve(null);
          fr.readAsDataURL(blob);
        });
      }
      const stash: Stash = {
        teamId: team.id,
        body: bodyRef.current!,
        thumb: thumbUrl,
      };
      sessionStorage.setItem(STASH_KEY, JSON.stringify(stash));
      await loginWithKakao(sb());
    };
    void stashAndLogin();
  }

  // ── 렌더 ──────────────────────────────────────────────────────────────
  // ref race 방지 — video 는 항상 마운트, 카메라 단계에서만 표시.
  const video = (
    <video
      ref={videoRef}
      playsInline
      muted
      className="join-video"
      style={stage === "camera" ? undefined : { display: "none" }}
    />
  );

  // 카톡 웹뷰 — 카메라가 막혀 있어 기본 브라우저로 재오픈해야 진행 가능.
  if (inApp === "kakao") {
    return (
      <div className="join">
        <p className="join-sub">카카오톡 안에서는 카메라가 막혀 있어요.</p>
        <button
          className="join-btn"
          onClick={() => openInExternalBrowser(window.location.href)}
        >
          기본 브라우저로 열기
        </button>
        <p className="join-sub">열린 화면에서 참여를 이어가 주세요.</p>
      </div>
    );
  }
  // 탈출 스킴이 없는 기타 인앱(인스타·페북·라인 등) — 안내 + 앱으로.
  if (inApp === "other") {
    return (
      <div className="join">
        <p className="join-sub">
          이 화면에서는 카메라가 안 돼요. 우측 상단 메뉴에서 기본 브라우저로
          열거나, 앱에서 참여해 주세요.
        </p>
        <a className="join-btn" href={appOpenUrl}>
          앱에서 보기
        </a>
        <Stores appStoreUrl={appStoreUrl} playStoreUrl={playStoreUrl} />
      </div>
    );
  }

  return (
    <div className="join">
      {video}

      {stage === "entry" && (
        <>
          <button className="join-btn" onClick={onJoinStart}>
            카카오로 참여하기
          </button>
          <p className="join-sub">설치 없이 브라우저에서 얼굴 등록까지</p>
          <button className="join-btn--ghost" onClick={onPreviewStart}>
            먼저 미리보기
          </button>
        </>
      )}

      {stage === "name" && (
        <>
          <p className="join-q">어떤 이름으로 참여할까요?</p>
          {team.members.some((m) => !m.joined) && (
            <>
              <p className="join-sub">비어 있는 자리</p>
              <div className="join-chips">
                {team.members
                  .filter((m) => !m.joined)
                  .map((m) => (
                    <button
                      key={m.name}
                      className={
                        nameInput === m.name
                          ? "join-chip join-chip--on"
                          : "join-chip"
                      }
                      onClick={() => setNameInput(m.name)}
                    >
                      {m.name}
                    </button>
                  ))}
              </div>
            </>
          )}
          <input
            className="join-input"
            value={nameInput}
            maxLength={10}
            placeholder="이름 직접 입력"
            onChange={(e) => setNameInput(e.target.value)}
          />
          {notice && <p className="join-notice">{notice}</p>}
          <div>
            <button className="join-btn" onClick={onNameNext}>
              다음
            </button>
          </div>
        </>
      )}

      {stage === "info" && (
        <>
          <p className="join-q">나를 알려주세요</p>
          <Picker
            label="성별"
            options={GENDERS}
            value={gender}
            onPick={(v) => {
              setGender(v);
              void preloadDetector().catch(() => {});
            }}
          />
          <Picker
            label="나이대"
            options={AGES}
            value={age}
            onPick={(v) => {
              setAge(v);
              void preloadDetector().catch(() => {});
            }}
          />
          {notice && <p className="join-notice">{notice}</p>}
          <div>
            <button className="join-btn" onClick={onInfoNext}>
              카메라 켜기
            </button>
          </div>
        </>
      )}

      {stage === "camera" && <p className="join-sub">{hint}</p>}

      {stage === "saving" && <p className="join-q">그룹에 등록 중…</p>}

      {stage === "error" && (
        <>
          <p className="join-q">{errorMsg}</p>
          <a className="join-btn" href={appOpenUrl}>
            앱에서 확인하기
          </a>
          <Stores appStoreUrl={appStoreUrl} playStoreUrl={playStoreUrl} />
        </>
      )}

      {stage === "done" && (
        <>
          {joined && <div className="join-badge">참여 완료 ✓</div>}
          {teaser?.kind === "pair" ? (
            <>
              <p className="join-sub">
                나 ↔ {teaser.ownerName} (방장)
              </p>
              <div className="join-score">{teaser.total}점</div>
              <div style={{ fontSize: 16, color: "#1a1a1a" }}>
                {teaser.labelKo}
              </div>
            </>
          ) : teaser ? (
            <>
              <div style={{ fontSize: 24, color: "#1a1a1a" }}>
                {teaser.primaryLabel}
              </div>
              <p className="join-sub">{teaser.catchphrase}</p>
            </>
          ) : null}
          {joined ? (
            <p className="join-sub">
              전원이 모이면 이 링크에서 그룹 케미 결과표가 공개됩니다. 측면까지
              넣은 정밀 분석은 앱에서 확인할 수 있어요.
            </p>
          ) : (
            <button className="join-btn" onClick={onTeaserJoin}>
              이 결과로 그룹 참여하기
            </button>
          )}
          <a
            className="join-btn"
            href={appOpenUrl}
            style={{ display: "block", margin: "16px auto 0", maxWidth: 320 }}
          >
            앱에서 전체 결과 보기
          </a>
          <Stores appStoreUrl={appStoreUrl} playStoreUrl={playStoreUrl} />
        </>
      )}
    </div>
  );
}

function Picker({
  label,
  options,
  value,
  onPick,
}: {
  label: string;
  options: { v: string; ko: string }[];
  value: string | null;
  onPick: (v: string) => void;
}) {
  return (
    <div style={{ marginTop: 12 }}>
      <p className="join-sub" style={{ margin: "0 0 6px" }}>
        {label}
      </p>
      <div className="join-chips">
        {options.map((o) => (
          <button
            key={o.v}
            className={value === o.v ? "join-chip join-chip--on" : "join-chip"}
            onClick={() => onPick(o.v)}
          >
            {o.ko}
          </button>
        ))}
      </div>
    </div>
  );
}

function Stores({
  appStoreUrl,
  playStoreUrl,
}: {
  appStoreUrl: string;
  playStoreUrl: string;
}) {
  return (
    <div
      style={{
        display: "flex",
        gap: 16,
        justifyContent: "center",
        marginTop: 10,
      }}
    >
      <a
        style={{ fontSize: 13, color: "#666", textDecoration: "none" }}
        href={appStoreUrl}
      >
        App Store
      </a>
      <a
        style={{ fontSize: 13, color: "#666", textDecoration: "none" }}
        href={playStoreUrl}
      >
        Google Play
      </a>
    </div>
  );
}
