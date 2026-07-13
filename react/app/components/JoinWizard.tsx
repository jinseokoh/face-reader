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
  | 'info'
  | 'camera'
  | 'saving'
  | 'done'
  | 'error'

// 앱 InfoConfirm 과 동일 필드 — 값은 엔진 enum name.
const ETHNICITIES: { v: string; ko: string }[] = [
  { v: 'eastAsian', ko: '동아시아인' },
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
  // 이름 선택 — 빈 슬롯 하나 또는 "직접 입력" 중 한 곳만 활성.
  const [slotPick, setSlotPick] = useState<string | null>(null)
  const [direct, setDirect] = useState(false)
  const [nameInput, setNameInput] = useState('')
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
        void fetchNickname(client, s.user.id).then((n) => {
          setNickname(n)
          setNameInput((cur) => cur || n)
        })
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
      void fetchNickname(client, uid).then((n) => {
        setNickname(n)
        setNameInput((cur) => cur || n)
      })
      const [mine, member] = await Promise.all([
        fetchMyFace(client, uid),
        fetchMembership(client, team.id, uid),
      ])
      setExisting(mine)
      setMembership(member)
      if (cameFromLogin) {
        // 로그인하고 복귀 — 이미 참여했으면 바로 로스터(done) 화면, 기존
        // 관상이 있으면 썸네일과 함께 재사용/재촬영 선택, 아니면 이름 선택.
        if (member) {
          await finishJoin(client)
        } else if (mine) {
          setStage('reuse')
        } else {
          // 등록된 관상 없음 — 이름 화면에서 '없음'을 먼저 알린다.
          setFaceStatus('none')
          setStage('name')
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

  // 선택 즉시 저장 — 다음 방문의 "나를 알려주세요"는 탭 한 번으로 끝난다.
  useEffect(() => {
    try {
      localStorage.setItem(DEMO_KEY, JSON.stringify({ gender, age, ethnicity }))
    } catch {
      /* storage 불가 환경은 무시 */
    }
  }, [gender, age, ethnicity])

  const openSlots = team.members.filter((m) => !m.joined)
  // 빈 슬롯이 하나도 없으면 직접 입력이 유일한 경로.
  const isDirect = direct || openSlots.length === 0

  /** 확정된 참여 이름 — 슬롯 선택 또는 직접 입력 중 활성인 쪽. */
  function chosenName(): string {
    return isDirect ? nameInput.trim() : (slotPick ?? '')
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
      const frontal = face != null && face.length >= 468 && isFrontal(face)
      drawMesh(video, face ?? null, frontal)
      if (face && face.length >= 468 && !frontal) {
        // 얼굴은 있지만 정면이 아님 — 빨간 mesh + 카운트다운 리셋 (앱 동일).
        countdownStartRef.current = null
        if (lastCountRef.current != null) {
          lastCountRef.current = null
          setCount(null)
        }
        setHint('정면을 봐 주세요')
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

  /** 앱 estimateYaw/classifyYaw 와 동일 — 코끝(1)↔좌(454)·우(234) 가장자리
   *  거리 비대칭으로 yaw 추정, |yaw| < 0.70 이면 정면. */
  function isFrontal(face: { x: number }[]): boolean {
    const nose = face[1].x
    const rightDist = Math.abs(nose - face[234].x)
    const leftDist = Math.abs(face[454].x - nose)
    const total = rightDist + leftDist
    if (total === 0) return false
    return Math.abs((leftDist - rightDist) / total) < 0.7
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

  async function capture(points: number[][]) {
    const video = videoRef.current
    const thumb = video ? await frameToThumb(video) : null
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
    await runSave()
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
    const r = await joinTeam(client, {
      teamId: team.id,
      metricsId: metricsIdRef.current,
      name: nameOverride ?? chosenName(),
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
        const mine =
          existing ?? (await fetchMyFace(client, s.user.id))
        setExisting(mine)
        if (!mine) setFaceStatus('none')
        setStage(mine ? 'reuse' : 'name')
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

  function onNameNext() {
    const name = chosenName()
    if (!name) {
      setNotice(
        isDirect
          ? '이름을 입력해 주세요.'
          : '자리를 고르거나 직접 입력을 눌러 주세요.',
      )
      return
    }
    const taken = team.members.some((m) => m.joined && m.name === name)
    if (taken) {
      setNotice('같은 그룹내에 동일이름은 허용하지 않습니다.')
      return
    }
    setNotice('')
    // 재사용/재촬영 결정은 이름 전에 끝난 상태 — 기존 관상 재사용이면
    // 바로 합류, 아니면 정보 확인 → 카메라.
    if (metricsIdRef.current || bodyRef.current) void runSave()
    else setStage('info')
  }

  /** 기존 내 관상 재사용 — 촬영 없이 이름 선택으로 진행. */
  function onReuseExisting() {
    metricsIdRef.current = existing?.id ?? null
    setFaceStatus('reuse')
    // 기존 관상의 alias 와 같은 이름의 빈 슬롯이 있으면 이름 단계 생략 —
    // 그 자리로 즉시 합류한다.
    const alias = existing?.alias ?? null
    if (alias && team.members.some((m) => !m.joined && m.name === alias)) {
      setSlotPick(alias)
      setDirect(false)
      void runSave(alias)
      return
    }
    setStage('name')
  }

  /** 기존 관상 대신 새로 촬영 — 이름 선택 후 정보/카메라로 이어진다. */
  function onReuseRecapture() {
    metricsIdRef.current = null
    bodyRef.current = null
    setFaceStatus('none')
    setStage('name')
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


  function onInfoNext() {
    setNotice('')
    void startCamera()
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
        <p className="join-sub">카카오톡 안에서는 카메라가 막혀 있어요.</p>
        <button
          className="join-btn join-btn--line"
          style={{ display: 'block', width: '100%' }}
          onClick={() => openInExternalBrowser(window.location.href)}
        >
          기본 브라우저로 다시 열기
        </button>
        <p className="join-sub">
          기본 브라우저를 사용해야만 관상 촬영이 가능합니다.
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
          {openSlots.length > 0 && (
            <div className="join-chips">
              {openSlots.map((m) => (
                <button
                  key={m.name}
                  className={
                    !isDirect && slotPick === m.name
                      ? 'join-chip join-chip--on'
                      : 'join-chip'
                  }
                  onClick={() => {
                    setSlotPick(m.name)
                    setDirect(false)
                    setNotice('')
                  }}
                >
                  {m.name}
                </button>
              ))}
              <button
                className={isDirect ? 'join-chip join-chip--on' : 'join-chip'}
                onClick={() => {
                  setDirect(true)
                  setSlotPick(null)
                  setNotice('')
                }}
              >
                직접 입력
              </button>
            </div>
          )}
          {isDirect && (
            <input
              className="join-input"
              value={nameInput}
              maxLength={10}
              placeholder="참여할 이름 입력"
              onChange={(e) => setNameInput(e.target.value)}
            />
          )}
          {notice && <p className="join-notice">{notice}</p>}
          <div>
            <button className="join-btn" onClick={onNameNext}>
              다음
            </button>
          </div>
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

      {stage === 'info' && (
        <>
          <p className="join-q">정보 확인</p>
          <div className="join-form">
            <label className="join-field">
              <span className="join-field-label">인종</span>
              <select
                className="join-select"
                value={ethnicity}
                onChange={(e) => {
                  setEthnicity(e.target.value)
                  void preloadDetector().catch(() => {})
                }}
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
                onChange={(e) => {
                  setGender(e.target.value)
                  void preloadDetector().catch(() => {})
                }}
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
                onChange={(e) => {
                  setAge(e.target.value)
                  void preloadDetector().catch(() => {})
                }}
              >
                {AGES.map((o) => (
                  <option key={o.v} value={o.v}>
                    {o.ko}
                  </option>
                ))}
              </select>
            </label>
            <button
              className="join-btn join-btn--line join-form-submit"
              onClick={onInfoNext}
            >
              카메라 켜기
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
