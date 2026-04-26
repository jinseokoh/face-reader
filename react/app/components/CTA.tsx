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
        <a className="cta-store" href={props.appStoreUrl}>App Store</a>
        <a className="cta-store" href={props.playStoreUrl}>Google Play</a>
      </div>
    </section>
  );
}
