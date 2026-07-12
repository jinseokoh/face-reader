import { AwsClient } from "aws4fetch";

// 브라우저 직접 R2 조작 — refine 는 로컬 전용 admin (ad-videos/create 와 동일 패턴).
const R2_ENV = (import.meta as { env: Record<string, string> }).env;
const R2 = {
  accountId: R2_ENV.VITE_R2_ACCOUNT_ID,
  bucket: R2_ENV.VITE_R2_BUCKET_NAME || "facely",
  accessKeyId: R2_ENV.VITE_R2_ACCESS_KEY_ID,
  secretAccessKey: R2_ENV.VITE_R2_SECRET_ACCESS_KEY,
};

/** R2 객체 삭제 — 404 도 성공 취급. 자격 미설정이면 false. */
export async function deleteR2Object(key: string): Promise<boolean> {
  if (!R2.accountId || !R2.accessKeyId || !R2.secretAccessKey) return false;
  const client = new AwsClient({
    accessKeyId: R2.accessKeyId,
    secretAccessKey: R2.secretAccessKey,
    service: "s3",
    region: "auto",
  });
  const url = `https://${R2.accountId}.r2.cloudflarestorage.com/${R2.bucket}/${key}`;
  const signed = await client.sign(new Request(url, { method: "DELETE" }), {
    aws: { signQuery: true },
  });
  const res = await fetch(signed.url, { method: "DELETE" });
  return res.ok || res.status === 404;
}
