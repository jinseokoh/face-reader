import { AwsClient } from "aws4fetch";

// 브라우저 직접 R2 조작 — refine 는 로컬 전용 admin (ad-videos/create 와 동일 패턴).
const R2_ENV = (import.meta as { env: Record<string, string> }).env;
const R2 = {
  accountId: R2_ENV.VITE_R2_ACCOUNT_ID,
  bucket: R2_ENV.VITE_R2_BUCKET_NAME || "facely",
  accessKeyId: R2_ENV.VITE_R2_ACCESS_KEY_ID,
  secretAccessKey: R2_ENV.VITE_R2_SECRET_ACCESS_KEY,
};

/** VITE_R2_* 가 .env 에 있는지. 없으면 업로드·삭제 버튼을 띄우지 않는다. */
export function hasR2Credentials(): boolean {
  return Boolean(R2.accountId && R2.accessKeyId && R2.secretAccessKey);
}

function signer(): AwsClient {
  return new AwsClient({
    accessKeyId: R2.accessKeyId,
    secretAccessKey: R2.secretAccessKey,
    service: "s3",
    region: "auto",
  });
}

function objectUrl(key: string): string {
  return `https://${R2.accountId}.r2.cloudflarestorage.com/${R2.bucket}/${key}`;
}

/** R2 객체 삭제 — 404 도 성공 취급. 자격 미설정이면 false. */
export async function deleteR2Object(key: string): Promise<boolean> {
  if (!hasR2Credentials()) return false;
  const signed = await signer().sign(
    new Request(objectUrl(key), { method: "DELETE" }),
    { aws: { signQuery: true } },
  );
  const res = await fetch(signed.url, { method: "DELETE" });
  return res.ok || res.status === 404;
}

/**
 * R2 객체 PUT.
 *
 * 실패하면 상태 코드를 담은 Error 를 던진다 — 조용히 false 를 돌려주면
 * 호출부가 "올라간 줄" 알고 화면만 갱신한다.
 */
export async function putR2Object(key: string, file: Blob): Promise<void> {
  if (!hasR2Credentials()) {
    throw new Error("R2 환경변수(VITE_R2_*)가 .env 에 설정되지 않았습니다");
  }
  const target = objectUrl(key);
  console.log("[r2] PUT", target, `(${file.size} bytes, ${file.type || "?"})`);

  let res: Response;
  try {
    // 헤더 서명 방식(client.fetch). presigned URL 은 서명에 없는 헤더를 R2 가
    // 버리므로 Content-Type 조차 보장되지 않는다.
    // 버킷 CORS 의 allowed_headers 에 Authorization 이 있어야 한다.
    res = await signer().fetch(target, {
      method: "PUT",
      body: file,
      headers: { "Content-Type": file.type || "application/octet-stream" },
    });
  } catch (e) {
    // fetch 가 던지는 경우는 대부분 CORS 다. 브라우저가 응답을 막으면 상태
    // 코드조차 없어서 "실패 (0)" 같은 것도 못 만든다 — 원인을 문구로 남긴다.
    console.error("[r2] PUT 네트워크 단계 실패", e);
    throw new Error(
      "R2 에 연결하지 못했습니다. 버킷의 CORS 설정에 이 도메인이 " +
        `없을 가능성이 큽니다 (origin=${location.origin}). 원본 오류: ` +
        (e instanceof Error ? e.message : String(e)),
    );
  }

  if (!res.ok) {
    const detail = await res.text().catch(() => "");
    console.error("[r2] PUT 거부", res.status, res.statusText, detail.slice(0, 500));
    throw new Error(
      `R2 업로드 실패 (${res.status} ${res.statusText})` +
        (detail ? ` — ${detail.slice(0, 200)}` : ""),
    );
  }
  console.log("[r2] PUT 성공", res.status);
}
