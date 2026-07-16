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
  fetchMemberBodies,
  fetchMembership,
  fetchMyFace,
  fetchProgress,
  fetchRoster,
  isTeamOpen,
  joinTeam,
  saveCapture,
  type WebCaptureBody,
} from '../lib/join'
import type { TeamShowcase } from '../lib/supabase'

/**
 * /g/:id 참여 위저드 — 앱 미설치자가 브라우저에서 그룹 참여를 끝까지 완료한다.
 * entry → (kakao) → name → (reuse) → info → camera → saving → done
 * 스펙: docs/superpowers/specs/2026-07-12-web-join-upgrade-design.md
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

type Stage =
  | 'entry'
  | 'name'
  | 'reuse'
  | 'camera'
  | 'confirm'
  | 'saving'
  | 'done'
  | 'error'

// 앱 InfoConfirm 과 동일 필드 — 값은 엔진 enum name.
const ETHNICITIES: { v: string; ko: string }[] = [
  { v: 'eastAsian', ko: '동아시아인' },
  { v: 'southeastAsian', ko: '동남아시아인' },
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
// 밴드 라벨 → 이모지 (웹 4색 팔레트를 지키는 쇼케이스와 동일 문법).
const BAND_EMOJI: Record<string, string> = {
  천작지합: '🟢',
  금슬상화: '🔵',
  마합가성: '🟠',
  형극난조: '🔴',
}

type WebMatrix = {
  names: string[]
  pairs: { a: number; b: number; total: number; label: string; emoji: string }[]
  best: { a: number; b: number; label: string; emoji: string } | null
}

const AGES: { v: string; ko: string }[] = [
  { v: '10s', ko: '10대' },
  { v: '20s', ko: '20대' },
  { v: '30s', ko: '30대' },
  { v: '40s', ko: '40대' },
  { v: '50s', ko: '50대' },
  { v: '60s', ko: '60대' },
  { v: '70s', ko: '70대+' },
]

export function JoinWizard({
  team,
  supabaseUrl,
  supabaseAnonKey,
  cdnBase,
  onProgress,
  onJoined,
}: {
  team: TeamShowcase
  supabaseUrl: string
  supabaseAnonKey: string
  /** R2 CDN base (cdn.facely.kr) — 내 관상 썸네일 아바타 렌더용. */
  cdnBase: string
  /** 위저드가 entry 를 벗어나면 true — 부모가 초대장 칩을 숨기는 데 쓴다. */
  onProgress?: (active: boolean) => void
  /** 참여 성립 시 최신 현황 전달 — 헤더 subtitle 이 '등록 완료' 상태로 바뀐다. */
  onJoined?: (p: { joined: number; total: number }) => void
}) {
  const [stage, setStage] = useState<Stage>('entry')
  const [session, setSession] = useState<Session | null>(null)
  const [nickname, setNickname] = useState('')
  // 촬영 후 정보 확인 — DeepFace 추정으로 prefill, 사용자 수정 허용.
  const [estimating, setEstimating] = useState(false)
  // 확인 페이지 이름 필드 — default fallback 은 카카오 nickname.
  const [aliasName, setAliasName] = useState('')
  // 정보 확인 — 3필드 모두 default 보유 (동아시아인/남성/20대), 즉시 진행 가능.
  const [ethnicity, setEthnicity] = useState<string>('eastAsian')
  const [gender, setGender] = useState<string>('male')
  const [age, setAge] = useState<string>('20s')
  // 서버에 이미 있는 내 관상(is_my_face) — 재사용/재촬영 선택의 근거.
  const [existing, setExisting] = useState<{
    id: string
    thumbnailKey: string | null
    alias: string | null
  } | null>(null)
  // 로그인 직후 확인된 내 관상 보유 여부 — 이름 화면 상단에 항상 명시한다.
  const [faceStatus, setFaceStatus] = useState<'reuse' | 'none' | null>(null)
  // 이 그룹에 이미 참여한 내 슬롯 — 있으면 이름을 묻지 않고 재참여를 묻는다.
  const [membership, setMembership] = useState<{
    name: string
    metricsId: string
    thumbnailKey: string | null
  } | null>(null)

  /** 썸네일 키 → CDN URL (없으면 null). */
  const avatarUrl = (key: string | null | undefined): string | null =>
    key && cdnBase ? `${cdnBase}/${key}` : null
  // 참여 직후 서버에서 다시 읽은 등록 현황 (loader 데이터는 stale).
  const [progress, setProgress] = useState<{
    joined: number
    total: number
  } | null>(null)
  // 전체 참여자 명단 — done 화면 로스터 (미등록은 빈 슬롯).
  const [roster, setRoster] = useState<
    { name: string; joined: boolean; thumbnailKey: string | null }[]
  >([])
  // 전원 등록 시 [그룹 케미 결과표 보기] — 웹에서 shared 엔진으로 즉석 계산.
  const [matrix, setMatrix] = useState<WebMatrix | null>(null)
  const [matrixBusy, setMatrixBusy] = useState(false)
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
  // 확정된 참여 이름 — setState 는 카메라 루프 클로저에 반영되지 않으므로
  // (stale closure) 합류 이름은 반드시 ref 로 전달한다.
  const joinNameRef = useRef<string | null>(null)
  // 확인 페이지에서 확정한 metrics 이름(alias) — 클로저 안전하게 ref 로.
  const aliasRef = useRef<string | null>(null)
  // 직전 프레임 landmark — 앱과 동일한 흔들림(stability) 판정용.
  const prevFaceRef = useRef<{ x: number; y: number }[] | null>(null)
  // 캡처 산출물 — 단계를 넘어도 유지 (name-taken 재시도 시 metrics 재사용).
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
      const [nick, mine, member] = await Promise.all([
        fetchNickname(client, uid),
        fetchMyFace(client, uid),
        fetchMembership(client, team.id, uid),
      ])
      setNickname(nick)
      setExisting(mine)
      setMembership(member)
      if (cameFromLogin) {
        // 로그인하고 복귀 — 이미 참여했으면 바로 로스터(done) 화면, 기존
        // 관상이 있으면 썸네일과 함께 재사용/재촬영 선택, 아니면 이름으로.
        if (member) {
          await finishJoin(client)
        } else if (mine) {
          setStage('reuse')
        } else {
          setFaceStatus('none')
          goNameOrSkip(nick)
        }
      }
    })
    return () => sub.subscription.unsubscribe()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  useEffect(() => () => stopCamera(), [])

  useEffect(() => {
    onProgress?.(stage !== 'entry')
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [stage])

  const openSlots = team.members.filter((m) => !m.joined)

  /** 촬영 진입 — 정보 확인은 앱과 동일하게 촬영 **후** DeepFace 추정
   *  prefill 상태로 노출된다. */
  function goCapture() {
    void startCamera()
  }

  /** 이름 화면 진입 또는 생략 — [name]이 빈 슬롯과 정확히 매칭되면 물어볼
   *  것이 없으므로 그 자리를 자동 선택하고 촬영 단계로 직행한다. */
  function goNameOrSkip(name: string | null | undefined) {
    if (name && openSlots.some((m) => m.name === name)) {
      joinNameRef.current = name
      goCapture()
      return
    }
    setStage('name')
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

  /** 저장 시퀀스: 마감 재확인 → metrics(신규 캡처 시, 기존 my-face 덮어쓰기) → 합류. */
  async function runSave(nameOverride?: string) {
    const s = sessionRef.current
    if (!s) {
      fail('세션이 만료됐어요. 다시 로그인해 주세요.')
      return
    }
    setStage('saving')
    const client = sb()
    if (!(await isTeamOpen(client, team.id))) {
      fail('모집이 종료된 그룹입니다.')
      return
    }
    if (!metricsIdRef.current) {
      const body = bodyRef.current
      if (!body) {
        fail('촬영 정보가 없어요. 처음부터 다시 시도해 주세요.')
        return
      }
      // 기존 참여 슬롯의 metrics > 내 관상 순으로 그 row 를 덮어써
      // my-face 1행·멤버십 1행을 유지한다.
      metricsIdRef.current = await saveCapture(client, {
        uid: s.user.id,
        nickname,
        alias: aliasRef.current,
        body,
        thumb: thumbRef.current,
        id: membership?.metricsId ?? existing?.id ?? undefined,
        oldKey: membership?.thumbnailKey ?? existing?.thumbnailKey ?? null,
        accessToken: s.access_token,
      })
    }
    if (!metricsIdRef.current) {
      fail('등록에 실패했어요. 잠시 후 다시 시도해 주세요.')
      return
    }
    // 이미 참여한 슬롯의 재촬영 — metrics id 가 그대로라 명단 변경이 없다.
    if (membership && metricsIdRef.current === membership.metricsId) {
      await finishJoin(client)
      return
    }
    const joinName = (nameOverride ?? joinNameRef.current ?? '').trim()
    if (!joinName) {
      // 빈 이름 합류 금지 — 이름 없는 유령 멤버 행 방지.
      fail('참여할 이름이 비어 있어요. 처음부터 다시 시도해 주세요.')
      return
    }
    const r = await joinTeam(client, {
      teamId: team.id,
      metricsId: metricsIdRef.current,
      uid: s.user.id,
      name: joinName,
    })
    if (r === 'name-taken') {
      setNotice(
        '방금 다른 사람이 그 자리에 들어갔어요. 다른 이름으로 참여해 주세요.',
      )
      setStage('name')
      return
    }
    if (r === 'failed') {
      fail('참여에 실패했어요. 잠시 후 다시 시도해 주세요.')
      return
    }
    await finishJoin(client)
  }

  /** 참여 성립 마무리 — 최신 현황·로스터를 읽고 done 으로. */
  async function finishJoin(client: SupabaseClient) {
    const [p, r] = await Promise.all([
      fetchProgress(client, team.id),
      fetchRoster(client, team.id),
    ])
    setProgress(p)
    setRoster(r)
    if (p) onJoined?.(p)
    setStage('done')
  }

  // ── 액션 핸들러 ────────────────────────────────────────────────────────
  async function onJoinStart() {
    const s = sessionRef.current
    if (s) {
      setNotice('')
      // 이미 참여한 그룹이면 이름을 묻지 않고 재참여 확인으로.
      const client = sb()
      const member =
        membership ?? (await fetchMembership(client, team.id, s.user.id))
      if (member) {
        setMembership(member)
        await finishJoin(client)
      } else {
        const mine = existing ?? (await fetchMyFace(client, s.user.id))
        setExisting(mine)
        if (mine) {
          setStage('reuse')
        } else {
          setFaceStatus('none')
          const nick = nickname || (await fetchNickname(client, s.user.id))
          if (nick && !nickname) setNickname(nick)
          goNameOrSkip(nick)
        }
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

  /** 슬롯 칩 선택 — [다음] 없이 즉시 진행. 직접 입력은 정원 밖 참가를
   *  만들므로 허용하지 않는다 (빈 슬롯 claim 만 가능). */
  function onSlotSelect(name: string) {
    setNotice('')
    joinNameRef.current = name
    // 재사용/재촬영 결정은 이름 전에 끝난 상태 — 기존 관상 재사용이면
    // 바로 합류, 아니면 촬영 (확정 이력 있으면 정보 확인 생략).
    if (metricsIdRef.current || bodyRef.current) void runSave()
    else goCapture()
  }

  /** 기존 내 관상 재사용 — 촬영 없이 이름 선택으로 진행. */
  function onReuseExisting() {
    metricsIdRef.current = existing?.id ?? null
    setFaceStatus('reuse')
    // alias(우선) 또는 카카오 닉네임이 빈 슬롯과 매칭되면 이름 단계 생략 —
    // 그 자리로 즉시 합류한다. 매칭되는데 또 물어보는 것은 무의미.
    const match = [existing?.alias, nickname].find(
      (n): n is string =>
        Boolean(n) && team.members.some((m) => !m.joined && m.name === n),
    )
    if (match) {
      joinNameRef.current = match
      void runSave(match)
      return
    }
    setStage('name')
  }

  /** 기존 관상 대신 새로 촬영 — 이름 선택 후 정보/카메라로 이어진다. */
  function onReuseRecapture() {
    metricsIdRef.current = null
    bodyRef.current = null
    setFaceStatus('none')
    goNameOrSkip(nickname)
  }

  /** 전원 등록 시 즉석 결과표 — 멤버 전원 raw 를 받아 runCompat 전쌍 계산. */
  async function onShowMatrix() {
    if (matrixBusy) return
    setMatrixBusy(true)
    try {
      await import('../lib/shared/face_engine.js')
      const rows = await fetchMemberBodies(sb(), team.id)
      if (rows.length < 2) return
      const pairs: WebMatrix['pairs'] = []
      let best: WebMatrix['pairs'][number] | null = null
      for (let i = 0; i < rows.length; i++) {
        for (let j = i + 1; j < rows.length; j++) {
          const c = JSON.parse(
            globalThis.runCompat(rows[i].body, rows[j].body),
          ) as { total: number; labelKo: string }
          const p = {
            a: i,
            b: j,
            total: Math.round(c.total),
            label: c.labelKo,
            emoji: BAND_EMOJI[c.labelKo] ?? '⚪',
          }
          pairs.push(p)
          if (!best || p.total > best.total) best = p
        }
      }
      setMatrix({
        names: rows.map((r) => r.name),
        pairs,
        best: best
          ? { a: best.a, b: best.b, label: best.label, emoji: best.emoji }
          : null,
      })
    } catch (e) {
      console.error('[join] matrix compute failed:', e)
      setNotice('결과표를 계산하지 못했어요. 잠시 후 다시 시도해 주세요.')
    } finally {
      setMatrixBusy(false)
    }
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
  const allJoined =
    progress != null && progress.total > 0 && progress.joined >= progress.total
  // 전원 등록 → 결과표 버튼/테이블 (done·already 공용).
  const matrixSection = allJoined ? (
    matrix ? (
      <MatrixTable matrix={matrix} />
    ) : (
      <div>
        <button className="join-btn" onClick={() => void onShowMatrix()}>
          {matrixBusy ? '결과표 계산 중…' : '그룹 케미 결과표 보기'}
        </button>
        {notice && <p className="join-notice">{notice}</p>}
      </div>
    )
  ) : null
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
          <button className="join-btn join-btn--kakao" onClick={onJoinStart}>
            <KakaoTalkIcon />
            카카오로 참여하기
          </button>
          {notice && <p className="join-notice">{notice}</p>}
          <p className="join-sub">
            앱 설치 없이 브라우저에서 관상을 등록할 수 있습니다.
          </p>
        </>
      )}

      {stage === 'name' && (
        <>
          {faceStatus === 'reuse' && (
            <p className="join-sub" style={{ margin: '0 0 8px' }}>
              이미 등록된 내 관상으로 참여합니다. (촬영 없음)
            </p>
          )}
          <p className="join-q">어떤 이름으로 참여할까요?</p>
          {openSlots.length > 0 ? (
            <div className="join-chips">
              {openSlots.map((m) => (
                <button
                  key={m.name}
                  className="join-chip"
                  onClick={() => onSlotSelect(m.name)}
                >
                  {m.name}
                </button>
              ))}
            </div>
          ) : (
            <p className="join-sub">
              빈 자리가 없습니다. 방장에게 자리를 요청해 주세요.
            </p>
          )}
          {notice && <p className="join-notice">{notice}</p>}
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
        </>
      )}

      {stage === 'camera' && <p className="join-sub">{hint}</p>}

      {stage === 'saving' && <p className="join-q">그룹에 등록 중…</p>}

      {stage === 'error' && <p className="join-q">{errorMsg}</p>}

      {stage === 'done' && (
        <>
          {/* 앱 팀룸처럼 — 등록자는 아바타, 미등록자는 점선 빈 슬롯. */}
          {roster.length > 0 && (
            <div className="join-roster">
              {roster.map((m) => (
                <div key={m.name} className="join-roster-item">
                  {m.joined && avatarUrl(m.thumbnailKey) ? (
                    <img
                      className="join-avatar"
                      src={avatarUrl(m.thumbnailKey)!}
                      alt=""
                    />
                  ) : m.joined ? (
                    <div className="join-avatar join-avatar--letter">
                      {m.name.slice(0, 1)}
                    </div>
                  ) : (
                    <div className="join-avatar join-slot-empty" />
                  )}
                  <p
                    className="join-avatar-name"
                    style={m.joined ? undefined : { color: '#666' }}
                  >
                    {m.name}
                  </p>
                </div>
              ))}
            </div>
          )}
          {progress && progress.total - progress.joined > 0 && (
            <p className="join-sub">
              나머지 {progress.total - progress.joined}명이 등록을 마치면 그룹
              케미 결과표가 공개됩니다.
            </p>
          )}
          {matrixSection}
          <p className="join-sub" style={{ marginTop: 4 }}>
            얼굴의 측면까지 분석하는 정밀 관상은 앱으로만 가능합니다.
          </p>
        </>
      )}
    </div>
  )
}

/** 즉석 결과표 — /g 쇼케이스와 동일 문법 (이름 + 밴드 이모지, 점수 비노출). */
function MatrixTable({ matrix }: { matrix: WebMatrix }) {
  const { names, pairs, best } = matrix
  const bandOf = (i: number, j: number) => {
    const a = Math.min(i, j)
    const b = Math.max(i, j)
    return pairs.find((p) => p.a === a && p.b === b) ?? null
  }
  const head: React.CSSProperties = {
    fontSize: 12,
    color: '#666',
    fontWeight: 400,
    padding: 4,
    whiteSpace: 'nowrap',
  }
  const cell: React.CSSProperties = {
    width: 36,
    height: 36,
    textAlign: 'center',
    fontSize: 16,
    border: '1px solid #f7f7f8',
    background: '#fff',
  }
  return (
    <div style={{ marginTop: 16 }}>
      {best && (
        <div
          style={{
            background: '#fff',
            borderRadius: 12,
            padding: 12,
            fontSize: 14,
            color: '#1a1a1a',
          }}
        >
          🏆 {names[best.a]} × {names[best.b]} {best.emoji} {best.label}
        </div>
      )}
      <div style={{ overflowX: 'auto', marginTop: 12 }}>
        <table style={{ borderCollapse: 'collapse', margin: '0 auto' }}>
          <thead>
            <tr>
              <th />
              {names.map((n, j) => (
                <th key={j} style={head}>
                  {n}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {names.map((n, i) => (
              <tr key={i}>
                <th style={{ ...head, textAlign: 'right', paddingRight: 8 }}>
                  {n}
                </th>
                {names.map((_, j) => (
                  <td key={j} style={cell}>
                    {i === j ? '·' : (bandOf(i, j)?.emoji ?? '')}
                  </td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
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
