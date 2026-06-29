/**
 * 인앱 브라우저 감지 + 외부(기본) 브라우저 탈출. OpenBridge(앱 열기)와
 * CameraTeaser(카메라 쓰려고 외부로) 가 공유한다. client-only (navigator).
 */

export type InApp = "kakao" | "other" | null;

/** UA 로 인앱 브라우저 종류 판별. 카톡만 범용 탈출 스킴(openExternal)이 있다. */
export function detectInApp(ua: string = navigator.userAgent): InApp {
  if (/KAKAOTALK/i.test(ua)) return "kakao";
  // 탈출 스킴이 없는 기타 인앱 — 카메라 막힘, 사용자 안내로만 처리.
  if (/Instagram|FBAN|FBAV|FB_IAB|Line\/|NAVER|DaumApps/i.test(ua)) {
    return "other";
  }
  return null;
}

/** 카카오톡 인앱 브라우저 → 기본 브라우저로 [url] 재오픈 (iOS·Android 공통). */
export function openInExternalBrowser(url: string) {
  window.location.href =
    `kakaotalk://web/openExternal?url=${encodeURIComponent(url)}`;
}
