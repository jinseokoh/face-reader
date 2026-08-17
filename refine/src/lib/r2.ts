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
 * R2 객체 PUT — 같은 key 로 올리면 덮어쓴다.
 *
 * host 만 서명하는 presigned URL(signQuery)이라 브라우저에서 바로 PUT 한다.
 * body 를 서명에 넣지 않으므로 Content-Type 을 헤더로 보내도 서명이 깨지지
 * 않는다 (ad-videos/create 와 같은 방식).
 *
 * 실패하면 상태 코드를 담은 Error 를 던진다 — 조용히 false 를 돌려주면
 * 호출부가 "올라간 줄" 알고 화면만 갱신한다.
 */
export async function putR2Object(key: string, file: Blob): Promise<void> {
  if (!hasR2Credentials()) {
    throw new Error("R2 환경변수(VITE_R2_*)가 .env 에 설정되지 않았습니다");
  }
  const signed = await signer().sign(
    new Request(objectUrl(key), { method: "PUT" }),
    { aws: { signQuery: true } },
  );
  const res = await fetch(signed.url, {
    method: "PUT",
    body: file,
    headers: { "Content-Type": file.type || "application/octet-stream" },
  });
  if (!res.ok) {
    throw new Error(`R2 업로드 실패 (${res.status} ${res.statusText})`);
  }
}
