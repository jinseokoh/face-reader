import { useEffect } from "react";

interface Props {
  shortId: string;
  appLinkBase: string;
  appStoreUrl: string;
  playStoreUrl: string;
}

export function CTA(props: Props) {
  useEffect(() => {
    const ua = navigator.userAgent;
    const isIOS = /iPhone|iPad|iPod/.test(ua);
    const isAndroid = /Android/.test(ua);
    if (!isIOS && !isAndroid) return;

    const universalLink = `${props.appLinkBase}${props.shortId}`;
    const storeUrl = isIOS ? props.appStoreUrl : props.playStoreUrl;

    const startedAt = Date.now();
    window.location.href = universalLink;

    const fallback = window.setTimeout(() => {
      if (Date.now() - startedAt < 2500 && document.visibilityState === "visible") {
        window.location.href = storeUrl;
      }
    }, 1500);

    return () => window.clearTimeout(fallback);
  }, [props.appLinkBase, props.appStoreUrl, props.playStoreUrl, props.shortId]);

  return (
    <section className="cta">
      <a className="cta-primary" href={`${props.appLinkBase}${props.shortId}`}>
        앱에서 전체 결과 보기
      </a>
      <p className="cta-divider">앱이 없다면</p>
      <div className="cta-stores">
        <a className="cta-store" href={props.appStoreUrl}>
          <AppleIcon />
          <span>App Store</span>
        </a>
        <a className="cta-store" href={props.playStoreUrl}>
          <PlayIcon />
          <span>Google Play</span>
        </a>
      </div>
    </section>
  );
}

function AppleIcon() {
  return (
    <svg
      className="cta-store-icon"
      width="18"
      height="18"
      viewBox="0 0 24 24"
      aria-hidden="true"
      fill="currentColor"
    >
      <path d="M17.05 20.28c-.98.95-2.05.8-3.08.35-1.09-.46-2.09-.48-3.24 0-1.44.62-2.2.44-3.06-.35C2.79 15.25 3.51 7.59 9.05 7.31c1.35.07 2.29.74 3.08.74 1.18 0 2.6-.85 3.91-.72 1.62.13 2.85.65 3.65 1.83-3.21 1.85-2.43 6.04.45 7.27-.59 1.49-1.36 3-2.59 4.05zM12.03 7.25c-.13-2.06 1.65-3.83 3.55-3.97.29 2.31-2.06 4.06-3.55 3.97z" />
    </svg>
  );
}

function PlayIcon() {
  return (
    <svg
      className="cta-store-icon"
      width="18"
      height="18"
      viewBox="0 0 24 24"
      aria-hidden="true"
    >
      <path
        fill="#34A853"
        d="M3.6 21.6c-.36-.18-.6-.55-.6-.95V3.34c0-.4.24-.77.6-.95l9.06 9.6-9.06 9.61z"
      />
      <path
        fill="#FBBC04"
        d="M16.81 15.12l-2.81-2.97 2.81-2.97 4.04 2.4c.4.24.6.55.6.87s-.2.63-.6.87l-4.04 2.4z"
      />
      <path
        fill="#EA4335"
        d="M14 12.15L3.6 21.6c.32.16.7.16 1.08-.06l11.13-6.42L14 12.15z"
      />
      <path
        fill="#4285F4"
        d="M14 12.15l1.81-3.27L4.68 2.46c-.38-.22-.76-.22-1.08-.06L14 12.15z"
      />
    </svg>
  );
}
