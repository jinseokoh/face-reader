import type { Session, SupabaseClient } from '@supabase/supabase-js'
import { useEffect, useRef, useState } from 'react'
import {
  cleanAuthParams,
  fetchNickname,
  getSupabase,
  loginWithKakao,
} from '../lib/auth'
import { detectInApp, openInExternalBrowser, type InApp } from '../lib/inapp'
import {
  estimateDemographics,
  fetchBattle,
  fetchBattleRoster,
  fetchMyFace,
  joinBattle,
  photoConsentText,
  remainingGenderSlots,
  saveCapture,
  watchBattle,
  type RosterEntry,
  type WebCaptureBody,
} from '../lib/join'
import type { BattleSSR } from '../lib/supabase'

/**
 * /g/:id 참여 위저드 — 앱 미설치자가 브라우저에서 케미 배틀 참가를 끝까지 완료한다.
 * entry(PIN·공약 동의) → (kakao) → (reuse) → camera → confirm → saving → done(라이브 로비)
 * 스펙: docs/superpowers/specs/2026-07-16-chemistry-battle-design.md §8
 *
 * 전부 client-only — getUserMedia·tasks-vision·face_engine.js 는 dynamic import.
 * `<video>` 는 위저드 생애 내내 마운트(카메라 단계 외 비표시) — ref race 제거.
 * ⚠️ 카톡 인앱 브라우저에선 getUserMedia 가 막히므로 외부 브라우저 탈출이 선행.
 */

// package.json 의 @mediapipe/tasks-vision 과 같은 버전으로 유지.
const MP_VERSION = '0.10.35'
const MP_WASM = `https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@${MP_VERSION}/wasm`
const MP_MODEL =
  'https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task'

const NO_FACE_TIMEOUT_MS = 20_000
// 성별/나이대는 한 번 고르면 localStorage 에 남겨 다음 방문에 prefill.
const DEMO_KEY = 'facely:demographic'
// 얼굴이 잡히면 3초 카운트다운 (3 → 2 → 1) 후 자동 찰칵.
const COUNTDOWN_MS = 3_000
// 로비 라이브 갱신 — Realtime 이 끊겨도 최신을 놓치지 않게 보조 폴링.
const LOBBY_POLL_MS = 15_000

type Stage =
  | 'entry'
  | 'reuse'
  | 'camera'
  | 'confirm'
  | 'saving'
  | 'done'
  | 'error'

// 앱 InfoConfirm 과 동일 필드 — 값은 엔진 enum name.
const ETHNICITIES: { v: string; ko: string }[] = [
  { v: 'eastAsian', ko: '아시아인' },
  { v: 'southeastAsian', ko: '동남아인' },
  { v: 'caucasian', ko: '백인' },
  { v: 'african', ko: '아프리카인' },
  { v: 'hispanic', ko: '히스패닉' },
  { v: 'middleEastern', ko: '중동인' },
]
const GENDERS: { v: string; ko: string }[] = [
  { v: 'male', ko: '남성' },
  { v: 'female', ko: '여성' },
]
// 앱 InfoConfirm 과 동일 범위 (AgeGroup teens~seventies, jsonValue "10s".."70s").
const AGES: { v: string; ko: string }[] = [
  { v: '10s', ko: '10대' },
  { v: '20s', ko: '20대' },
  { v: '30s', ko: '30대' },
  { v: '40s', ko: '40대' },
  { v: '50s', ko: '50대' },
  { v: '60s', ko: '60대' },
  { v: '70s', ko: '70대+' },
]

// join_team 실패 코드 → 사용자 문구 (BAD_PASSWORD/NO_MY_FACE 는 별도 분기).
const JOIN_ERROR_MESSAGES: Record<string, string> = {
  AGE_NOT_ALLOWED: '이 방의 연령대에 해당하지 않습니다',
  GENDER_FULL: '이 방의 남녀 자리 중 한쪽이 다 찼습니다',
  FULL: '정원이 가득 찼습니다',
  NOT_RECRUITING: '모집이 끝난 방입니다. 새로고침 후 다시 확인해 주세요.',
}

export function JoinWizard({
  battle,
  roster,
  supabaseUrl,
  supabaseAnonKey,
  cdnBase,
  onActive,
}: {
  battle: BattleSSR['battle']
  roster: RosterEntry[]
  supabaseUrl: string
  supabaseAnonKey: string
  /** R2 CDN base (cdn.facely.kr) — 내 관상 썸네일 아바타 렌더용. */
  cdnBase: string
  /** 위저드가 entry 를 벗어나면 true — 부모가 초대장 칩을 숨기는 데 쓴다. */
  onActive?: (active: boolean) => void
}) {
  const [stage, setStage] = useState<Stage>('entry')
  const [session, setSession] = useState<Session | null>(null)
  const [nickname, setNickname] = useState('')
  // 촬영 후 정보 확인 — DeepFace 추정으로 prefill, 사용자 수정 허용.
  const [estimating, setEstimating] = useState(false)
  // 확인 페이지 이름 필드 — default fallback 은 카카오 nickname.
  const [aliasName, setAliasName] = useState('')
  // 정보 확인 — 3필드 모두 default 보유 (아시아인/남성/20대), 즉시 진행 가능.
  const [ethnicity, setEthnicity] = useState<string>('eastAsian')
  const [gender, setGender] = useState<string>('male')
  const [age, setAge] = useState<string>('20s')
  // 서버에 이미 있는 내 관상(is_my_face) — 재사용/재촬영 선택의 근거.
  const [existing, setExisting] = useState<{
    id: string
    thumbnailKey: string | null
    alias: string | null
  } | null>(null)
  // 비밀방 PIN — sessionStorage 로 OAuth 왕복(카카오 리다이렉트가 state 를
  // 날린다) 후에도 값을 잃지 않는다. SSR hydration 중엔 sessionStorage 를
  // 읽지 않고(DEMO_KEY 와 동일 패턴) 마운트 useEffect 에서 복원한다.
  const pinStorageKey = `facely:battle-pin:${battle.id}`
  const [pin, setPin] = useState<string>('')
  // done 스테이지 라이브 로비 — watchBattle 구독 + 폴링으로 항상 최신.
  const [liveRoster, setLiveRoster] = useState<RosterEntry[]>(roster)

  /** 썸네일 키 → CDN URL (없으면 null). */
  const avatarUrl = (key: string | null | undefined): string | null =>
    key && cdnBase ? `${cdnBase}/${key}` : null
  const [hint, setHint] = useState('얼굴을 화면 안에 맞춰 주세요')
  // 자동 촬영 카운트다운 (2 → 1) — 비디오 위 대형 숫자.
  const [count, setCount] = useState<number | null>(null)
  const [notice, setNotice] = useState('')
  const [errorMsg, setErrorMsg] = useState('')
  // 인앱 브라우저 — 카톡 웹뷰는 카메라가 막혀 외부 브라우저로 탈출해야 한다.
  const [inApp, setInApp] = useState<InApp>(null)

  const sbRef = useRef<SupabaseClient | null>(null)
  const sessionRef = useRef<Session | null>(null)
  const videoRef = useRef<HTMLVideoElement>(null)
  const canvasRef = useRef<HTMLCanvasElement>(null)
  const streamRef = useRef<MediaStream | null>(null)
  const landmarkerRef = useRef<unknown>(null)
  // MediaPipe 오버레이 도구 — preload 시 채워지고 loop 가 매 프레임 그린다.
  const drawToolsRef = useRef<{
    DrawingUtils: new (ctx: CanvasRenderingContext2D) => {
      drawConnectors: (
        lms: { x: number; y: number }[],
        connections: unknown,
        style: { color: string; lineWidth: number },
      ) => void
      drawLandmarks: (
        lms: { x: number; y: number }[],
        style: {
          color: string
          fillColor: string
          radius: number
          lineWidth: number
        },
      ) => void
    }
    tesselation: unknown
  } | null>(null)
  const preloadRef = useRef<Promise<void> | null>(null)
  const rafRef = useRef<number | null>(null)
  const countdownStartRef = useRef<number | null>(null)
  const lastCountRef = useRef<number | null>(null)
  const doneRef = useRef(false)
  const noFaceTimerRef = useRef<number | null>(null)
  // 확인 페이지에서 확정한 metrics 이름(alias) — 클로저 안전하게 ref 로.
  const aliasRef = useRef<string | null>(null)
  // 직전 프레임 landmark — 앱과 동일한 흔들림(stability) 판정용.
  const prevFaceRef = useRef<{ x: number; y: number }[] | null>(null)
  // 캡처 산출물 — 단계를 넘어도 유지 (재시도 시 metrics 재사용).
  const bodyRef = useRef<WebCaptureBody | null>(null)
  const thumbRef = useRef<Blob | null>(null)
  const metricsIdRef = useRef<string | null>(null)

  function sb(): SupabaseClient {
    if (!sbRef.current) {
      sbRef.current = getSupabase(supabaseUrl, supabaseAnonKey)
    }
    return sbRef.current
  }

  // 마운트: 인앱 감지 + 저장된 성별/나이대 복원 + 세션 복구 + OAuth 복귀 처리.
  useEffect(() => {
    setInApp(detectInApp())
    try {
      const saved = JSON.parse(localStorage.getItem(DEMO_KEY) ?? 'null') as {
        gender?: string
        age?: string
        ethnicity?: string
      } | null
      if (saved?.gender === 'male' || saved?.gender === 'female') {
        setGender(saved.gender)
      }
      if (saved?.age && AGES.some((a) => a.v === saved.age)) {
        setAge(saved.age)
      }
      if (
        saved?.ethnicity &&
        ETHNICITIES.some((e) => e.v === saved.ethnicity)
      ) {
        setEthnicity(saved.ethnicity)
      }
    } catch {
      /* 손상된 저장값은 무시 */
    }
    try {
      const savedPin = sessionStorage.getItem(pinStorageKey)
      if (savedPin) setPin(savedPin)
    } catch {
      /* storage 불가 환경은 무시 */
    }
    if (!supabaseUrl || !supabaseAnonKey) return
    // ⚠️ 순서 중요 — ?code= 는 createClient(detectSessionInUrl)가 세션으로
    // 교환한 뒤에 지워야 한다. 먼저 지우면 교환이 영영 안 일어난다.
    const cameFromLogin = new URL(window.location.href).searchParams.has('code')
    const client = sb()
    const { data: sub } = client.auth.onAuthStateChange((_e, s) => {
      sessionRef.current = s
      setSession(s)
      if (s) {
        void fetchNickname(client, s.user.id).then(setNickname)
        void fetchMyFace(client, s.user.id).then(setExisting)
      }
    })
    void client.auth.getSession().then(async ({ data }) => {
      // 이 시점엔 code→세션 교환이 끝났으므로 주소창의 흔적을 지워도 안전.
      cleanAuthParams()
      sessionRef.current = data.session
      setSession(data.session)
      if (!data.session) {
        if (cameFromLogin) {
          setNotice('로그인 처리에 실패했어요. 다시 시도해 주세요.')
        }
        return
      }
      const uid = data.session.user.id
      const [nick, mine] = await Promise.all([
        fetchNickname(client, uid),
        fetchMyFace(client, uid),
      ])
      setNickname(nick)
      setExisting(mine)
      if (cameFromLogin) {
        // 로그인하고 복귀 — 기존 관상이 있으면 재사용/재촬영 선택, 아니면
        // 곧장 촬영으로 (이미 참여했다면 join_team 이 ALREADY_JOINED 로
        // 알려주고 그대로 로비로 진입한다).
        if (mine) {
          setStage('reuse')
        } else {
          goCapture()
        }
      }
    })
    return () => sub.subscription.unsubscribe()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  useEffect(() => () => stopCamera(), [])

  useEffect(() => {
    onActive?.(stage !== 'entry')
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [stage])

  // done 스테이지 = 라이브 로비 — Realtime 구독 + 15초 폴링, recruiting 이
  // 아니게 되면 새로고침(SSR 분기가 쇼케이스/fallback 을 렌더한다).
  useEffect(() => {
    if (stage !== 'done') return
    const client = sb()
    const refetch = async () => {
      const [b, r] = await Promise.all([
        fetchBattle(client, battle.id),
        fetchBattleRoster(client, battle.id),
      ])
      if (!b) return
      if (b.status !== 'recruiting') {
        window.location.reload()
        return
      }
      setLiveRoster(r)
    }
    void refetch()
    const channel = watchBattle(client, battle.id, () => void refetch())
    const poll = window.setInterval(() => void refetch(), LOBBY_POLL_MS)
    return () => {
      client.removeChannel(channel)
      window.clearInterval(poll)
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [stage])

  /** 촬영 진입 — 정보 확인은 앱과 동일하게 촬영 **후** DeepFace 추정
   *  prefill 상태로 노출된다. */
  function goCapture() {
    void startCamera()
  }

  function stopCamera() {
    if (rafRef.current != null) cancelAnimationFrame(rafRef.current)
    rafRef.current = null
    if (noFaceTimerRef.current != null) clearTimeout(noFaceTimerRef.current)
    noFaceTimerRef.current = null
    streamRef.current?.getTracks().forEach((t) => t.stop())
    streamRef.current = null
    const canvas = canvasRef.current
    canvas?.getContext('2d')?.clearRect(0, 0, canvas.width, canvas.height)
  }

  function fail(msg: string) {
    stopCamera()
    setErrorMsg(msg)
    setStage('error')
  }

  /** MediaPipe + shared engine 로드 — info 단계 진입 시 1회 백그라운드 시작. */
  function preloadDetector(): Promise<void> {
    if (!preloadRef.current) {
      preloadRef.current = (async () => {
        await import('../lib/shared/face_engine.js')
        const { FaceLandmarker, FilesetResolver, DrawingUtils } =
          await import('@mediapipe/tasks-vision')
        drawToolsRef.current = {
          DrawingUtils: DrawingUtils as never,
          tesselation: FaceLandmarker.FACE_LANDMARKS_TESSELATION,
        }
        const fileset = await FilesetResolver.forVisionTasks(MP_WASM)
        landmarkerRef.current = await FaceLandmarker.createFromOptions(
          fileset,
          {
            baseOptions: { modelAssetPath: MP_MODEL },
            runningMode: 'VIDEO',
            numFaces: 1,
          },
        )
      })()
      // 실패 시 다음 호출에서 재시도할 수 있게 리셋.
      preloadRef.current.catch(() => {
        preloadRef.current = null
      })
    }
    return preloadRef.current
  }

  async function startCamera() {
    doneRef.current = false
    countdownStartRef.current = null
    lastCountRef.current = null
    prevFaceRef.current = null
    setCount(null)
    setHint('얼굴 인식 준비 중…')
    setStage('camera')
    let stream: MediaStream
    try {
      stream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: 'user', width: 640, height: 480 },
        audio: false,
      })
    } catch {
      fail('카메라를 열 수 없어요. 브라우저의 카메라 권한을 허용해 주세요.')
      return
    }
    streamRef.current = stream
    const video = videoRef.current
    if (!video) {
      fail('카메라 화면을 준비하지 못했어요. 새로고침 후 다시 시도해 주세요.')
      return
    }
    video.srcObject = stream
    await video.play().catch(() => {})
    try {
      await preloadDetector()
    } catch {
      fail('얼굴 인식 모듈을 불러오지 못했어요. 잠시 후 다시 시도해 주세요.')
      return
    }
    setHint('얼굴을 화면 안에 맞춰 주세요')
    noFaceTimerRef.current = window.setTimeout(
      () => setHint('얼굴이 안 보여요. 밝은 곳에서 정면을 맞춰 주세요.'),
      NO_FACE_TIMEOUT_MS,
    )
    loop()
  }

  function loop() {
    const video = videoRef.current
    const landmarker = landmarkerRef.current as {
      detectForVideo: (
        v: HTMLVideoElement,
        t: number,
      ) => { faceLandmarks: { x: number; y: number }[][] }
    } | null
    if (!video || !landmarker || doneRef.current) return
    if (video.readyState >= 2) {
      const res = landmarker.detectForVideo(video, performance.now())
      const face = res.faceLandmarks?.[0]
      const ready =
        face && face.length >= 468 ? captureReadiness(face) : 'no-face'
      prevFaceRef.current = face && face.length >= 468 ? face : null
      drawMesh(video, face ?? null, ready === 'ok')
      if (face && face.length >= 468 && ready !== 'ok') {
        // 얼굴은 있지만 캡처 조건 미달 — 빨간 mesh + 카운트다운 리셋 (앱 동일).
        countdownStartRef.current = null
        if (lastCountRef.current != null) {
          lastCountRef.current = null
          setCount(null)
        }
        setHint(
          ready === 'yaw'
            ? '정면을 봐 주세요'
            : ready === 'size'
              ? '조금 더 가까이 와 주세요'
              : '움직이지 말고 그대로 계세요',
        )
      } else if (face && face.length >= 468) {
        // 정면이 잡히면 2초 카운트다운 (2 → 1 → 찰칵) — 앱과 동일한 치즈 모먼트.
        const now = performance.now()
        if (countdownStartRef.current == null) {
          countdownStartRef.current = now
          setHint('좋아요! 그대로 계세요')
        }
        const remaining = COUNTDOWN_MS - (now - countdownStartRef.current)
        if (remaining <= 0) {
          doneRef.current = true
          setCount(null)
          setHint('찰칵!')
          void capture(face.map((p) => [p.x, p.y]))
          return
        }
        const c = Math.ceil(remaining / 1000)
        if (lastCountRef.current !== c) {
          lastCountRef.current = c
          setCount(c)
        }
      } else {
        // 얼굴을 놓치면 카운트다운 리셋.
        countdownStartRef.current = null
        if (lastCountRef.current != null) {
          lastCountRef.current = null
          setCount(null)
        }
        setHint('얼굴을 화면 안에 맞춰 주세요')
      }
    }
    rafRef.current = requestAnimationFrame(loop)
  }

  /** 앱 _computeOverlayColor 이식 — 캡처 성립 조건 3중 게이트.
   *  ① yaw(코끝↔좌우 가장자리 비대칭) < 0.45 — 웹은 정면 전용이라 앱의
   *     frontal 분류(0.70)보다 엄격. ② 얼굴 폭 > 0.25 (너무 멀면 거부).
   *  ③ 프레임 간 landmark 평균 이동 < 0.005 (흔들림 거부). */
  function captureReadiness(
    face: { x: number; y: number }[],
  ): 'ok' | 'yaw' | 'size' | 'unstable' {
    const nose = face[1].x
    const rightDist = Math.abs(nose - face[234].x)
    const leftDist = Math.abs(face[454].x - nose)
    const total = rightDist + leftDist
    const yaw = total === 0 ? 1 : Math.abs((leftDist - rightDist) / total)
    if (yaw >= 0.45) return 'yaw'
    if (Math.abs(face[454].x - face[234].x) <= 0.25) return 'size'
    const prev = prevFaceRef.current
    if (!prev || prev.length !== face.length) return 'unstable'
    let dist = 0
    for (let i = 0; i < face.length; i++) {
      const dx = face[i].x - prev[i].x
      const dy = face[i].y - prev[i].y
      dist += Math.sqrt(dx * dx + dy * dy)
    }
    if (dist / face.length >= 0.005) return 'unstable'
    return 'ok'
  }

  /** 앱 FaceMeshPainter 와 동일 문법 — tesselation(alpha 0.15) + landmark 점.
   *  정면 = greenAccent / 비정면 = redAccent (앱 동일). 미검출이면 지운다. */
  function drawMesh(
    video: HTMLVideoElement,
    face: { x: number; y: number }[] | null,
    frontal: boolean,
  ) {
    const canvas = canvasRef.current
    const tools = drawToolsRef.current
    if (!canvas || !tools) return
    if (
      canvas.width !== video.videoWidth ||
      canvas.height !== video.videoHeight
    ) {
      canvas.width = video.videoWidth
      canvas.height = video.videoHeight
    }
    const ctx = canvas.getContext('2d')
    if (!ctx) return
    ctx.clearRect(0, 0, canvas.width, canvas.height)
    if (!face) return
    const line = frontal
      ? 'rgba(105, 240, 174, 0.15)' // greenAccent × 0.15
      : 'rgba(255, 82, 82, 0.15)' // redAccent × 0.15
    const dot = frontal ? '#69f0ae' : '#ff5252'
    const draw = new tools.DrawingUtils(ctx)
    draw.drawConnectors(face, tools.tesselation, {
      color: line,
      lineWidth: 0.5,
    })
    draw.drawLandmarks(face, {
      color: dot,
      fillColor: dot,
      radius: 1.2,
      lineWidth: 0,
    })
  }

  /** 검출 순간의 video 프레임 → 200×200 미러 crop JPEG (앱 썸네일과 동급). */
  function frameToThumb(video: HTMLVideoElement): Promise<Blob | null> {
    const side = Math.min(video.videoWidth, video.videoHeight)
    if (!side) return Promise.resolve(null)
    const sx = (video.videoWidth - side) / 2
    const sy = (video.videoHeight - side) / 2
    const c = document.createElement('canvas')
    c.width = 200
    c.height = 200
    const ctx = c.getContext('2d')
    if (!ctx) return Promise.resolve(null)
    ctx.translate(200, 0)
    ctx.scale(-1, 1)
    ctx.drawImage(video, sx, sy, side, side, 0, 0, 200, 200)
    return new Promise((r) => c.toBlob(r, 'image/jpeg', 0.8))
  }

  /** DeepFace 추정용 원본 프레임 (비미러, 전체 해상도 JPEG). */
  function frameToFull(video: HTMLVideoElement): Promise<Blob | null> {
    if (!video.videoWidth || !video.videoHeight) return Promise.resolve(null)
    const c = document.createElement('canvas')
    c.width = video.videoWidth
    c.height = video.videoHeight
    const ctx = c.getContext('2d')
    if (!ctx) return Promise.resolve(null)
    ctx.drawImage(video, 0, 0)
    return new Promise((r) => c.toBlob(r, 'image/jpeg', 0.85))
  }

  async function capture(points: number[][]) {
    const video = videoRef.current
    const thumb = video ? await frameToThumb(video) : null
    const frame = video ? await frameToFull(video) : null
    stopCamera()
    let body: WebCaptureBody
    try {
      const metrics = JSON.parse(
        globalThis.runMetrics(JSON.stringify(points)),
      ) as Record<string, number>
      body = {
        schemaVersion: 1,
        ethnicity,
        gender,
        ageGroup: age,
        timestamp: new Date().toISOString(),
        source: 'camera',
        metrics,
        lateralMetrics: null,
        faceShape: 'oval',
      }
    } catch {
      fail('측정값을 계산하지 못했어요. 다시 시도해 주세요.')
      return
    }
    bodyRef.current = body
    thumbRef.current = thumb
    // 앱과 동일: 촬영 → DeepFace 추정 → 정보 확인(prefill) → 저장.
    setAliasName((cur) => cur || nickname)
    setStage('confirm')
    if (frame) {
      setEstimating(true)
      void estimateDemographics(frame)
        .then((est) => {
          if (!est) return
          if (GENDERS.some((g) => g.v === est.gender)) setGender(est.gender)
          if (AGES.some((a) => a.v === est.ageGroup)) setAge(est.ageGroup)
          if (ETHNICITIES.some((e) => e.v === est.ethnicity)) {
            setEthnicity(est.ethnicity)
          }
        })
        .finally(() => setEstimating(false))
    }
  }

  /** 저장 시퀀스: metrics(신규 캡처 시, 기존 my-face 덮어쓰기) → join_team RPC. */
  async function runSave() {
    const s = sessionRef.current
    if (!s) {
      fail('세션이 만료됐어요. 다시 로그인해 주세요.')
      return
    }
    setStage('saving')
    const client = sb()
    if (!metricsIdRef.current) {
      const body = bodyRef.current
      if (!body) {
        fail('촬영 정보가 없어요. 처음부터 다시 시도해 주세요.')
        return
      }
      // 기존 내 관상 row 를 덮어써 my-face 1행을 유지한다.
      metricsIdRef.current = await saveCapture(client, {
        uid: s.user.id,
        nickname,
        alias: aliasRef.current,
        body,
        thumb: thumbRef.current,
        id: existing?.id ?? undefined,
        oldKey: existing?.thumbnailKey ?? null,
        accessToken: s.access_token,
      })
    }
    if (!metricsIdRef.current) {
      fail('등록에 실패했어요. 잠시 후 다시 시도해 주세요.')
      return
    }
    const code = await joinBattle(client, battle.id, pin || undefined)
    if (code === 'ok' || code === 'ALREADY_JOINED') {
      try {
        sessionStorage.removeItem(pinStorageKey)
      } catch {
        /* storage 불가 환경은 무시 */
      }
      await finishJoin(client)
      return
    }
    if (code === 'BAD_PASSWORD') {
      setNotice('비밀번호가 일치하지 않습니다')
      setStage('entry')
      return
    }
    if (code === 'NO_MY_FACE') {
      // 방금 저장한 등록 반영이 아직 안 됐을 뿐 — 확인 단계에서 재시도.
      setNotice('등록이 아직 반영되지 않았어요. 다시 시도해 주세요.')
      setStage('confirm')
      return
    }
    fail(JOIN_ERROR_MESSAGES[code] ?? '참여에 실패했어요. 잠시 후 다시 시도해 주세요.')
  }

  /** 참여 성립 마무리 — 최신 로스터를 읽고 done(라이브 로비)으로. */
  async function finishJoin(client: SupabaseClient) {
    const r = await fetchBattleRoster(client, battle.id)
    setLiveRoster(r)
    setStage('done')
  }

  // ── 액션 핸들러 ────────────────────────────────────────────────────────
  async function onJoinStart() {
    const s = sessionRef.current
    if (s) {
      setNotice('')
      const client = sb()
      const mine = existing ?? (await fetchMyFace(client, s.user.id))
      setExisting(mine)
      if (mine) {
        setStage('reuse')
      } else {
        goCapture()
      }
      return
    }
    // 클릭이 먹었는지 즉시 가시화 — 실패 시 사유도 화면에 띄운다.
    setNotice('카카오 로그인으로 이동 중…')
    loginWithKakao(sb()).catch((e) => {
      console.error('[join] kakao login failed:', e)
      setNotice(
        '카카오 로그인을 열지 못했어요. 새로고침 후 다시 시도해 주세요.',
      )
    })
  }

  function onPinChange(v: string) {
    setPin(v)
    try {
      sessionStorage.setItem(pinStorageKey, v)
    } catch {
      /* storage 불가 환경은 무시 — 서버가 최종 검증한다 */
    }
  }

  /** 기존 내 관상 재사용 — 촬영 없이 바로 합류(정원마감으로 이미 참여
   *  중이면 join_team 이 ALREADY_JOINED 로 응답, done 으로 처리). */
  function onReuseExisting() {
    metricsIdRef.current = existing?.id ?? null
    void runSave()
  }

  /** 기존 관상 대신 새로 촬영. */
  function onReuseRecapture() {
    metricsIdRef.current = null
    bodyRef.current = null
    goCapture()
  }

  /** 정보 확인 [확인] — 확정값을 body/ref 에 굳히고 저장·합류. */
  function onConfirm() {
    setNotice('')
    try {
      localStorage.setItem(DEMO_KEY, JSON.stringify({ gender, age, ethnicity }))
    } catch {
      /* storage 불가 환경은 무시 */
    }
    if (bodyRef.current) {
      bodyRef.current = {
        ...bodyRef.current,
        gender,
        ageGroup: age,
        ethnicity,
      }
    }
    aliasRef.current = aliasName.trim() || nickname || null
    void runSave()
  }

  // ── 렌더 ──────────────────────────────────────────────────────────────
  const waitCount = Math.max(battle.maxPlayers - liveRoster.length, 0)
  // ref race 방지 — video 는 항상 마운트, 카메라 단계에서만 표시.
  // 캔버스가 video 위에 겹쳐 landmark mesh 오버레이를 그린다 (앱과 동일).
  const video = (
    <div
      className="join-camera-wrap"
      style={stage === 'camera' ? undefined : { display: 'none' }}
    >
      <video ref={videoRef} playsInline muted className="join-video" />
      <canvas ref={canvasRef} className="join-mesh" />
      {count != null && <div className="join-count">{count}</div>}
    </div>
  )

  // 카톡 웹뷰 — 카메라가 막혀 있어 기본 브라우저로 재오픈해야 진행 가능.
  if (inApp === 'kakao') {
    return (
      <div className="join">
        <button
          className="join-btn join-btn--line"
          style={{ display: 'block', width: '100%' }}
          onClick={() => openInExternalBrowser(window.location.href)}
        >
          기본 브라우저로 다시 열기
        </button>
        <p className="join-sub">
          카카오톡 웹뷰 안에서는 카메라가 막혀 있어서, 기본 브라우저를 사용해서
          다시 열어야 해요.
        </p>
      </div>
    )
  }
  // 탈출 스킴이 없는 기타 인앱(인스타·페북·라인 등) — 안내 + 앱으로.
  if (inApp === 'other') {
    return (
      <div className="join">
        <p className="join-sub">
          이 화면에서는 카메라가 안 돼요. 우측 상단 메뉴에서 기본 브라우저로
          열거나, 앱에서 참여해 주세요.
        </p>
      </div>
    )
  }

  return (
    <div className="join">
      {video}

      {stage === 'entry' && (
        <>
          {battle.isPrivate && (
            <div className="join-form">
              <label className="join-field">
                <span className="join-field-label">참여 비밀번호</span>
                <input
                  className="join-select join-name-input"
                  inputMode="numeric"
                  maxLength={4}
                  value={pin}
                  placeholder="4자리 숫자"
                  onChange={(e) => onPinChange(e.target.value)}
                />
              </label>
            </div>
          )}
          {battle.roomKind === 'match' && (
            <p className="join-sub">
              남자 {remainingGenderSlots(roster, battle.maxPlayers, 'male')}자리 남음
              <br />
              여자 {remainingGenderSlots(roster, battle.maxPlayers, 'female')}자리 남음
            </p>
          )}
          <div className="join-consent">
            <p className="join-consent-text">
              {photoConsentText(battle.roomKind)}
            </p>
          </div>
          <button
            className="join-btn join-btn--kakao"
            onClick={onJoinStart}
            disabled={battle.isPrivate && !/^\d{4}$/.test(pin)}
          >
            <KakaoTalkIcon />
            카카오로 참여하기
          </button>
          {notice && <p className="join-notice">{notice}</p>}
          <p className="join-sub">
            앱 설치 없이 브라우저에서 관상을 등록할 수 있습니다.
          </p>
        </>
      )}

      {stage === 'reuse' && (
        <>
          <p className="join-q">이미 등록된 내 관상이 있어요</p>
          <div className="join-btn-row">
            <button
              className="join-btn join-btn--line join-btn--face"
              onClick={onReuseExisting}
            >
              {avatarUrl(existing?.thumbnailKey) && (
                <img
                  className="join-btn-avatar"
                  src={avatarUrl(existing?.thumbnailKey)!}
                  alt=""
                />
              )}
              기존 관상으로 참여
            </button>
            <button
              className="join-btn join-btn--line"
              onClick={onReuseRecapture}
            >
              다시 촬영하기
            </button>
          </div>
        </>
      )}

      {stage === 'confirm' && (
        <>
          <p className="join-q">정보 확인</p>
          <p className="join-sub" style={{ textAlign: 'center' }}>
            {estimating
              ? 'AI가 사진에서 정보를 추정하는 중…'
              : 'AI 추정 결과입니다. 잘못된 항목은 직접 수정해 주세요.'}
          </p>
          <div className="join-form">
            <label className="join-field">
              <span className="join-field-label">인종</span>
              <select
                className="join-select"
                value={ethnicity}
                disabled={estimating}
                onChange={(e) => setEthnicity(e.target.value)}
              >
                {ETHNICITIES.map((o) => (
                  <option key={o.v} value={o.v}>
                    {o.ko}
                  </option>
                ))}
              </select>
            </label>
            <label className="join-field">
              <span className="join-field-label">성별</span>
              <select
                className="join-select"
                value={gender}
                disabled={estimating}
                onChange={(e) => setGender(e.target.value)}
              >
                {GENDERS.map((o) => (
                  <option key={o.v} value={o.v}>
                    {o.ko}
                  </option>
                ))}
              </select>
            </label>
            <label className="join-field">
              <span className="join-field-label">나이대</span>
              <select
                className="join-select"
                value={age}
                disabled={estimating}
                onChange={(e) => setAge(e.target.value)}
              >
                {AGES.map((o) => (
                  <option key={o.v} value={o.v}>
                    {o.ko}
                  </option>
                ))}
              </select>
            </label>
            <label className="join-field">
              <span className="join-field-label">이름</span>
              <input
                className="join-select join-name-input"
                value={aliasName}
                maxLength={10}
                placeholder={nickname || '이름 입력'}
                onChange={(e) => setAliasName(e.target.value)}
              />
            </label>
            <button
              className="join-btn join-btn--line join-form-submit"
              disabled={estimating}
              onClick={onConfirm}
            >
              확인
            </button>
          </div>
          {notice && <p className="join-notice">{notice}</p>}
        </>
      )}

      {stage === 'camera' && <p className="join-sub">{hint}</p>}

      {stage === 'saving' && <p className="join-q">그룹에 등록 중…</p>}

      {stage === 'error' && <p className="join-q">{errorMsg}</p>}

      {stage === 'done' && (
        <>
          <p className="join-q">
            {liveRoster.length} / {battle.maxPlayers} 명 참가 중
          </p>
          {/* 앱 로비처럼 — 참가자는 이니셜 아바타, 빈 자리는 점선 슬롯. */}
          <div className="join-roster">
            {liveRoster.map((r) => (
              <div key={r.userId} className="join-roster-item">
                <div className="join-avatar join-avatar--letter">
                  {r.nickname.slice(0, 1)}
                </div>
                <p className="join-avatar-name">{r.nickname}</p>
                <p className="join-gender-badge">
                  {r.gender === 'male' ? '남' : '여'}
                </p>
              </div>
            ))}
            {Array.from({ length: waitCount }).map((_, i) => (
              <div key={`wait-${i}`} className="join-roster-item">
                <div className="join-avatar join-slot-empty" />
                <p className="join-avatar-name" style={{ color: '#666' }}>
                  대기 중
                </p>
              </div>
            ))}
          </div>
          {waitCount > 0 && (
            <p className="join-sub">
              나머지 {waitCount}명이 등록을 마치면 케미 배틀이 시작됩니다.
            </p>
          )}
          <p className="join-sub" style={{ marginTop: 4 }}>
            얼굴의 측면까지 분석하는 정밀 관상은 앱으로만 가능합니다.
          </p>
        </>
      )}
    </div>
  )
}

/** Font Awesome 7 brands `kakao-talk` (fab, 576×512) — 의존성 없이 인라인.
 *  앱(FontAwesomeIcons.kakaoTalk)과 동일 glyph. fill=currentColor. */
function KakaoTalkIcon() {
  return (
    <svg
      viewBox="0 0 576 512"
      width={18}
      height={18}
      fill="currentColor"
      aria-hidden="true"
    >
      <path d="M288 2.5c159.1 0 288 101.7 288 227.1 0 125.4-128.9 227.1-288 227.1-17.5 0-34.6-1.2-51.2-3.6-16.6 11.7-112.6 79.1-121.7 80.4 0 0-3.7 1.4-6.9-.4s-2.6-6.7-2.6-6.7C106.6 519.8 130.6 437.2 135 421.9 53.9 381.8 0 310.6 0 229.5 0 104.1 128.9 2.5 288 2.5zM86.2 161.7c-9 0-16.3 7.3-16.3 16.3s7.3 16.3 16.3 16.3l25.9 0 0 98.7c0 8.8 7.5 15.9 16.6 15.9s16.6-7.1 16.6-15.9l0-98.7 25.9 0c9 0 16.3-7.3 16.3-16.3s-7.3-16.3-16.3-16.3l-85.1 0zm140.8 0c-10.8 .2-19.3 8.4-22.1 16.4L165.2 282.7c-5 15.7-.6 21.5 3.9 23.6 3.2 1.5 6.9 2.3 10.6 2.3 6.9 0 12.2-2.8 13.8-7.3l8.2-21.6 50.7 0 8.2 21.5c1.6 4.5 6.9 7.3 13.8 7.3 3.7 0 7.3-.8 10.6-2.3 4.6-2.1 9-7.9 3.9-23.6L249.2 178.1c-2.8-8-11.3-16.2-22.2-16.4zm180.9 0c-9.2 0-16.6 7.5-16.6 16.6l0 113.7c0 9.2 7.5 16.6 16.6 16.6s16.6-7.5 16.6-16.6l0-36.2 5.8-5.8 38.9 51.6c3.2 4.2 8 6.6 13.3 6.6 3.6 0 7.1-1.1 10-3.3 3.5-2.7 5.8-6.6 6.4-11s-.5-8.8-3.2-12.3l-40.9-54.2 37.9-37.8c2.6-2.6 3.9-6.2 3.7-10.1-.2-3.9-2-7.6-4.9-10.5-3.1-3.1-7.3-4.9-11.4-4.9-3.6 0-6.8 1.3-9.2 3.7l-46.3 46.4 0-35.7c0-9.2-7.5-16.6-16.6-16.6zm-91.3 0c-9.3 0-16.9 7.5-16.9 16.6l0 112.8c0 8.4 7.1 15.2 15.9 15.3l53.3 0c8.8 0 15.9-6.9 15.9-15.3s-7.2-15.2-15.9-15.2l-35.3 0 0-97.6c0-9.2-7.6-16.6-17-16.6zm-73 88.6l-33.2 0 16.6-47.1 16.6 47.1z" />
    </svg>
  )
}
