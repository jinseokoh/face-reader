import { useState } from "react";
import { Alert, Avatar, Button, Popover, Space, Typography, Upload, message } from "antd";
import { UploadOutlined } from "@ant-design/icons";
import type { RcFile } from "antd/es/upload";
import { deleteR2Object, hasR2Credentials, putR2Object } from "../../lib/r2";
import { supabaseAdminClient } from "../../providers/supabase-client";

const { Text } = Typography;

const CDN_BASE = "https://cdn.facely.kr";
const MAX_BYTES = 5 * 1024 * 1024;
const TAG = "[AvatarUploader]";

/**
 * 관상 썸네일(아바타) 교체. 앱의 재촬영과 **같은 규칙**이어야 한다.
 *
 * 키는 `thumbnails/{owner}/{sha256}.{ext}` — 첫 칸이 소유자(로그인 uid 또는
 * `anon-{metrics_id}`), 뒤 칸이 사진 내용의 해시다. 사진이 바뀌면 해시가
 * 바뀌어 URL 자체가 달라지므로 CDN 캐시 무효화 문제가 생기지 않는다.
 *
 * **옛 객체는 지운다.** 이 도구의 목적이 흔적 없는 교체이기 때문이다 —
 * 앱의 재촬영과 여기가 갈린다. 앱은 사용자 행동이라 옛 사진을 남기지만,
 * 여기는 운영자가 현재 사진을 바꾸는 자리다.
 *
 * **결제된 궁합은 안 깨진다.** 구매 시점에 두 사진이 구매자 폴더로 복사되어
 * (`ThumbnailCopier`) 스냅샷은 자기 사본을 가리킨다. 여기서 지우는 건 이
 * 사람 폴더의 객체라 서로 다른 객체다. 단 **구매 사본 도입 이전에 팔린
 * 궁합**은 아직 이 키를 직접 가리킬 수 있다 — 구매자가 앱을 열면 대조가
 * 사본을 떠서 고치지만, 그 전에 지우면 그 쌍은 실루엣이 된다.
 *
 * 순서는 올리기 → body 갱신 → 옛 객체 삭제. 반대로 하면 업로드가 실패했을 때
 * 아바타가 사라진다.
 */
export function AvatarUploader({
  rowId,
  userId,
  alias,
  body,
  thumbKey,
  onReplaced,
}: {
  rowId: string;
  /** metrics.user_id — 없으면(익명 촬영분) 행 id 로 익명 스코프를 만든다. */
  userId: string | null;
  alias: string | null;
  body: string;
  thumbKey: string | null;
  onReplaced: () => void;
}) {
  const [busy, setBusy] = useState(false);
  const [failed, setFailed] = useState<string | null>(null);

  const shown = thumbKey ? `${CDN_BASE}/${thumbKey}` : null;

  const upload = async (file: RcFile) => {
    setFailed(null);
    console.log(TAG, `선택됨 name=${file.name} type=${file.type} size=${file.size}`);

    try {
      if (!hasR2Credentials()) {
        throw new Error("VITE_R2_* 자격이 번들에 없습니다");
      }
      if (!file.type.startsWith("image/")) {
        throw new Error(`이미지 파일이 아닙니다 (type=${file.type || "없음"})`);
      }
      if (file.size > MAX_BYTES) {
        throw new Error(`5MB 를 넘습니다 (${(file.size / 1024 / 1024).toFixed(1)}MB)`);
      }

      setBusy(true);
      const nextKey = await contentKey(file, userId ?? `anon-${rowId}`);
      console.log(TAG, `새 key=${nextKey} · 옛 key=${thumbKey ?? "없음"}`);

      await putR2Object(nextKey, file);

      const { error } = await supabaseAdminClient
        .from("metrics")
        .update({ body: withThumbKey(body, nextKey) })
        .eq("id", rowId);
      if (error) {
        // 방금 올린 것을 되돌리지 않는다 — 키가 내용 주소라, 같은 바이트를
        // 가진 이 사용자의 다른 카드가 이미 같은 객체를 가리키고 있을 수
        // 있다. 참조를 확인하지 않고 지우는 것이 이번 사고의 원인이었다.
        // 남은 객체는 이 사람 폴더 안이라 탈퇴 때 함께 사라진다.
        throw new Error(`body 갱신 실패: ${error.message}`);
      }

      // 교체 완료 — 옛 객체를 지워 흔적을 남기지 않는다. 실패해도 화면은 이미
      // 새 이미지를 가리키므로 남은 것은 orphan 일 뿐이다.
      if (thumbKey && thumbKey !== nextKey) {
        const ok = await deleteR2Object(thumbKey).catch(() => false);
        console.log(TAG, `옛 객체 삭제 ${ok ? "성공" : "실패 — orphan 으로 남음"}`, thumbKey);
      }

      message.success("썸네일을 교체했습니다");
      onReplaced();
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      console.error(TAG, "실패:", e);
      setFailed(msg);
      message.error(msg);
    } finally {
      setBusy(false);
    }
  };

  const avatar = (
    <Avatar src={shown ?? undefined} size={72} shape="circle">
      {alias?.[0] ?? "?"}
    </Avatar>
  );

  return (
    <Space direction="vertical" size="small" style={{ width: "100%" }}>
      <Space align="center" size="middle">
        {shown ? (
          <Popover
            content={
              <img
                src={shown}
                alt={alias ?? rowId}
                width={240}
                height={240}
                style={{ display: "block", borderRadius: 8, objectFit: "cover" }}
              />
            }
          >
            {avatar}
          </Popover>
        ) : (
          avatar
        )}

        <Space direction="vertical" size={4}>
          <Upload
            accept="image/*"
            showUploadList={false}
            beforeUpload={(file) => {
              void upload(file);
              return false; // antd 기본 업로드를 막고 위 흐름만 쓴다
            }}
            disabled={busy || !hasR2Credentials()}
          >
            <Button icon={<UploadOutlined />} loading={busy} disabled={!hasR2Credentials()}>
              {thumbKey ? "이미지 교체" : "이미지 등록"}
            </Button>
          </Upload>
          <Text type="secondary" style={{ fontSize: 11 }}>
            {!hasR2Credentials()
              ? ".env 의 VITE_R2_* 가 없어 업로드할 수 없습니다"
              : "새 이름으로 올리고 옛 이미지를 지웁니다."}
          </Text>
        </Space>
      </Space>

      {failed && (
        <Alert type="error" showIcon message="업로드 실패" description={failed} />
      )}
    </Space>
  );
}

/**
 * 앱·워커와 같은 규칙 — `thumbnails/{owner}/{sha256}.{ext}`.
 *
 * `flutter/lib/core/storage/thumbnail_paths.dart` 의 `contentKey` 와
 * `web/app/routes/api.r2.presign.ts` 의 `buildKey` 가 같은 문자열을 만든다.
 * 셋 중 하나만 어긋나도 카드가 자기 사진을 못 찾는다.
 */
async function contentKey(file: Blob, owner: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", await file.arrayBuffer());
  const hash = Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
  const ext = ((file as File).name?.split(".").pop() || "jpg").toLowerCase();
  return `thumbnails/${owner}/${hash}.${ext}`;
}

/** body JSON 에 thumbnailKey 를 넣는다. 파싱 실패면 그대로 던진다. */
function withThumbKey(body: string, key: string): string {
  const parsed = JSON.parse(body) as Record<string, unknown>;
  parsed.thumbnailKey = key;
  return JSON.stringify(parsed);
}
