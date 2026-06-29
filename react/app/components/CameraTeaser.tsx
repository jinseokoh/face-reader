import { useEffect, useRef, useState } from "react";
import type { TeamShowcase } from "../lib/supabase";
import { detectInApp, openInExternalBrowser, type InApp } from "../lib/inapp";

/**
 * 웹 티저 — 카톡 링크로 들어온 비연락처가 설치 전에 "내 케미 한 입"을 맛보는
 * 퍼널. 정면 1장만 브라우저 카메라(MediaPipe FaceLandmarker)로 잡아 shared
 * 엔진(runMetrics→runCompat/runEngine)으로 부분 결과를 띄우고, 욕망 최고조에서
 * 설치 유도. 측면·정밀 결과는 앱에서 ("정확한 결과는 앱에서" 프레이밍).
 *
 * 전부 client-only — getUserMedia·tasks-vision·face_engine.js 는 사용자가 시작을
 * 누른 뒤 dynamic import 한다(SSR/초기 로드 분리).
 *
 * ⚠️ 카톡 인앱 브라우저에선 getUserMedia 가 막히므로 OpenBridge 의 외부 브라우저
 * 탈출이 선행돼야 한다(이미 구현). 실기기 카메라 동작은 device 검증 필요.
 */

// package.json 의 @mediapipe/tasks-vision 와 같은 버전으로 유지.
const MP_VERSION = "0.10.35";
const MP_WASM = `https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@${MP_VERSION}/wasm`;
const MP_MODEL =
  "https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task";

type Stage = "idle" | "demographic" | "camera" | "computing" | "result" | "error";

type Teaser =
  | { kind: "pair"; total: number; labelKo: string; ownerName: string }
  | { kind: "solo"; primaryLabel: string; catchphrase: string };

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

export function CameraTeaser({
  team,
  appOpenUrl,
  appStoreUrl,
  playStoreUrl,
}: {
  team: TeamShowcase;
  appOpenUrl: string;
  appStoreUrl: string;
  playStoreUrl: string;
}) {
  const [stage, setStage] = useState<Stage>("idle");
  const [gender, setGender] = useState<string | null>(null);
  const [age, setAge] = useState<string | null>(null);
  const [result, setResult] = useState<Teaser | null>(null);
  const [errorMsg, setErrorMsg] = useState("");
  const [hint, setHint] = useState("얼굴을 화면 안에 맞춰 주세요");
  // 인앱 브라우저 — 카톡 웹뷰는 카메라가 막혀 외부 브라우저로 탈출해야 한다.
  const [inApp, setInApp] = useState<InApp>(null);

  useEffect(() => setInApp(detectInApp()), []);

  const videoRef = useRef<HTMLVideoElement>(null);
  const streamRef = useRef<MediaStream | null>(null);
  const landmarkerRef = useRef<unknown>(null);
  const rafRef = useRef<number | null>(null);
  const hitsRef = useRef(0);
  const doneRef = useRef(false);

  function stopCamera() {
    if (rafRef.current != null) cancelAnimationFrame(rafRef.current);
    rafRef.current = null;
    streamRef.current?.getTracks().forEach((t) => t.stop());
    streamRef.current = null;
  }

  useEffect(() => () => stopCamera(), []);

  function fail(msg: string) {
    stopCamera();
    setErrorMsg(msg);
    setStage("error");
  }

  async function startCamera() {
    doneRef.current = false;
    hitsRef.current = 0;
    setStage("camera");
    let stream: MediaStream;
    try {
      stream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: "user", width: 640, height: 480 },
        audio: false,
      });
    } catch {
      fail("카메라를 열 수 없어요. 권한을 허용했는지 확인해 주세요.");
      return;
    }
    streamRef.current = stream;
    const video = videoRef.current;
    if (!video) {
      fail("카메라 화면을 준비하지 못했어요.");
      return;
    }
    video.srcObject = stream;
    await video.play().catch(() => {});

    try {
      // shared 엔진 + MediaPipe 를 이 시점에 로드(초기 페이지 부담 분리).
      await import("../lib/shared/face_engine.js");
      const { FaceLandmarker, FilesetResolver } = await import(
        "@mediapipe/tasks-vision"
      );
      const fileset = await FilesetResolver.forVisionTasks(MP_WASM);
      landmarkerRef.current = await FaceLandmarker.createFromOptions(fileset, {
        baseOptions: { modelAssetPath: MP_MODEL },
        runningMode: "VIDEO",
        numFaces: 1,
      });
    } catch {
      fail("얼굴 인식 모듈을 불러오지 못했어요. 잠시 후 다시 시도해 주세요.");
      return;
    }
    loop();
  }

  function loop() {
    const video = videoRef.current;
    const landmarker = landmarkerRef.current as {
      detectForVideo: (v: HTMLVideoElement, t: number) => {
        faceLandmarks: { x: number; y: number }[][];
      };
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
          capture(face.map((p) => [p.x, p.y]));
          return;
        }
      } else {
        hitsRef.current = 0;
        setHint("얼굴을 화면 안에 맞춰 주세요");
      }
    }
    rafRef.current = requestAnimationFrame(loop);
  }

  function capture(points: number[][]) {
    stopCamera();
    setStage("computing");
    try {
      const metrics = JSON.parse(globalThis.runMetrics(JSON.stringify(points)));
      const report = {
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
      const reportJson = JSON.stringify(report);

      if (team.owner) {
        const c = JSON.parse(
          globalThis.runCompat(reportJson, JSON.stringify(team.owner.raw)),
        ) as { total: number; labelKo: string };
        setResult({
          kind: "pair",
          total: Math.round(c.total),
          labelKo: c.labelKo,
          ownerName: team.owner.name,
        });
      } else {
        const s = JSON.parse(globalThis.runEngine(reportJson)) as {
          primaryLabel: string;
          catchphrase: string;
        };
        setResult({
          kind: "solo",
          primaryLabel: s.primaryLabel,
          catchphrase: s.catchphrase,
        });
      }
      setStage("result");
    } catch {
      fail("결과를 계산하지 못했어요. 앱에서 다시 시도해 주세요.");
    }
  }

  // ── 렌더 ──────────────────────────────────────────────────────────────
  if (stage === "idle") {
    // 카톡 웹뷰 — 카메라가 막혀 있어 기본 브라우저로 이 페이지를 재오픈해야
    // 미리보기가 가능하다. 외부 브라우저로 나가면 UA에 KAKAOTALK 빠져 정상 흐름.
    if (inApp === "kakao") {
      return (
        <div style={wrap}>
          <p style={sub}>카카오톡 안에서는 카메라가 막혀 있어요.</p>
          <button
            style={primaryBtn}
            onClick={() => openInExternalBrowser(window.location.href)}
          >
            기본 브라우저로 열기
          </button>
          <p style={sub}>열린 화면에서 “내 케미 미리보기”를 눌러 주세요.</p>
        </div>
      );
    }
    // 탈출 스킴이 없는 기타 인앱(인스타·페북·라인 등) — 안내 + 앱으로.
    if (inApp === "other") {
      return (
        <div style={wrap}>
          <p style={sub}>
            이 화면에서는 카메라가 안 돼요. 우측 상단 메뉴에서 기본 브라우저로
            열거나, 앱에서 확인해 주세요.
          </p>
          <a style={primaryLink} href={appOpenUrl}>
            앱에서 보기
          </a>
          <Stores appStoreUrl={appStoreUrl} playStoreUrl={playStoreUrl} />
        </div>
      );
    }
    return (
      <div style={wrap}>
        <button style={primaryBtn} onClick={() => setStage("demographic")}>
          내 케미 미리보기
        </button>
        <p style={sub}>정면 1장이면 돼요 · 설치 없이 바로 확인</p>
      </div>
    );
  }

  if (stage === "demographic") {
    return (
      <div style={wrap}>
        <p style={q}>나를 알려주세요</p>
        <Picker
          label="성별"
          options={GENDERS}
          value={gender}
          onPick={setGender}
        />
        <Picker label="나이대" options={AGES} value={age} onPick={setAge} />
        <button
          style={gender && age ? primaryBtn : disabledBtn}
          disabled={!gender || !age}
          onClick={startCamera}
        >
          카메라 켜기
        </button>
      </div>
    );
  }

  if (stage === "camera") {
    return (
      <div style={wrap}>
        <video
          ref={videoRef}
          playsInline
          muted
          style={{
            width: "100%",
            maxWidth: 320,
            borderRadius: 12,
            background: "#f7f7f8",
            transform: "scaleX(-1)",
          }}
        />
        <p style={sub}>{hint}</p>
      </div>
    );
  }

  if (stage === "computing") {
    return (
      <div style={wrap}>
        <p style={q}>케미 계산 중…</p>
      </div>
    );
  }

  if (stage === "error") {
    return (
      <div style={wrap}>
        <p style={{ ...sub, color: "#1a1a1a" }}>{errorMsg}</p>
        <a style={primaryLink} href={appOpenUrl}>
          앱에서 확인하기
        </a>
        <Stores appStoreUrl={appStoreUrl} playStoreUrl={playStoreUrl} />
      </div>
    );
  }

  // result
  return (
    <div style={wrap}>
      {result?.kind === "pair" ? (
        <>
          <p style={sub}>
            나 ↔ {result.ownerName} (방장)
          </p>
          <div style={score}>{result.total}점</div>
          <div style={{ fontSize: 16, color: "#1a1a1a" }}>{result.labelKo}</div>
        </>
      ) : (
        <>
          <div style={{ fontSize: 24, color: "#1a1a1a" }}>
            {result?.primaryLabel}
          </div>
          <p style={sub}>{result?.catchphrase}</p>
        </>
      )}
      <p style={{ ...sub, marginTop: 16 }}>
        측면까지 넣은 정확한 결과와 우리 그룹 전원 케미는 앱에서
      </p>
      <a style={primaryLink} href={appOpenUrl}>
        앱에서 전체 결과 보기
      </a>
      <Stores appStoreUrl={appStoreUrl} playStoreUrl={playStoreUrl} />
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
      <p style={{ ...sub, marginBottom: 6 }}>{label}</p>
      <div
        style={{ display: "flex", flexWrap: "wrap", gap: 8, justifyContent: "center" }}
      >
        {options.map((o) => (
          <button
            key={o.v}
            onClick={() => onPick(o.v)}
            style={value === o.v ? chipOn : chipOff}
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
    <div style={{ display: "flex", gap: 16, justifyContent: "center", marginTop: 10 }}>
      <a style={storeLink} href={appStoreUrl}>
        App Store
      </a>
      <a style={storeLink} href={playStoreUrl}>
        Google Play
      </a>
    </div>
  );
}

const wrap: React.CSSProperties = {
  textAlign: "center",
  padding: "16px",
  marginTop: 8,
};
const q: React.CSSProperties = { fontSize: 16, color: "#1a1a1a", margin: 0 };
const sub: React.CSSProperties = { fontSize: 13, color: "#666", marginTop: 8 };
const score: React.CSSProperties = {
  fontSize: 24,
  color: "#c44",
  fontWeight: 700,
  marginTop: 8,
};
const primaryBtn: React.CSSProperties = {
  background: "#1a1a1a",
  color: "#fff",
  border: "none",
  borderRadius: 12,
  padding: "12px 20px",
  fontSize: 16,
  cursor: "pointer",
};
const disabledBtn: React.CSSProperties = {
  ...primaryBtn,
  background: "#f7f7f8",
  color: "#666",
  cursor: "default",
};
const primaryLink: React.CSSProperties = {
  display: "inline-block",
  background: "#1a1a1a",
  color: "#fff",
  borderRadius: 12,
  padding: "12px 20px",
  fontSize: 16,
  textDecoration: "none",
  marginTop: 12,
};
const storeLink: React.CSSProperties = {
  fontSize: 13,
  color: "#666",
  textDecoration: "none",
};
const chipOff: React.CSSProperties = {
  background: "#f7f7f8",
  color: "#1a1a1a",
  border: "1px solid #f7f7f8",
  borderRadius: 10,
  padding: "6px 14px",
  fontSize: 14,
  cursor: "pointer",
};
const chipOn: React.CSSProperties = {
  ...chipOff,
  border: "1px solid #1a1a1a",
};
