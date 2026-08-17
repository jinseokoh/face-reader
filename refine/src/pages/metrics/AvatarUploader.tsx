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
 * 관상 썸네일(아바타) 교체.
 *
 * **항상 새 키로 올리고 옛 객체를 지운다.** 앱이 재촬영을 처리하는 방식과
 * 같다. 같은 키에 덮어쓰면 URL 이 그대로라 브라우저와 CDN 이 옛 이미지를
 * 계속 들고 있어 캐시 무효화에 기대야 하는데, 키가 바뀌면 그 문제 자체가
 * 생기지 않는다.
 *
 * 순서는 올리기 → body 갱신 → 옛 객체 삭제다. 삭제가 실패해도 화면은 이미
 * 새 이미지를 가리키고 남은 것은 orphan 일 뿐이다. 반대로 먼저 지우면
 * 업로드가 실패했을 때 아바타가 사라진다.
 */
export function AvatarUploader({
  rowId,
  alias,
  body,
  thumbKey,
  onReplaced,
}: {
  rowId: string;
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
      const nextKey = newThumbKey(file.name);
      console.log(TAG, `새 key=${nextKey} · 옛 key=${thumbKey ?? "없음"}`);

      await putR2Object(nextKey, file);

      const { error } = await supabaseAdminClient
        .from("metrics")
        .update({ body: withThumbKey(body, nextKey) })
        .eq("id", rowId);
      if (error) {
        // body 가 아직 옛 키를 가리키므로 방금 올린 것은 orphan 이 된다.
        // 되돌려 둬야 다음 시도가 깨끗한 상태에서 시작한다.
        await deleteR2Object(nextKey).catch(() => undefined);
        throw new Error(`body 갱신 실패로 되돌렸습니다: ${error.message}`);
      }

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

/** 앱과 같은 규칙 — `thumbnails/YYYYMM/{uuid}.{ext}` */
function newThumbKey(filename: string): string {
  const now = new Date();
  const ym = `${now.getFullYear()}${String(now.getMonth() + 1).padStart(2, "0")}`;
  const ext = (filename.split(".").pop() || "jpg").toLowerCase();
  return `thumbnails/${ym}/${crypto.randomUUID()}.${ext}`;
}

/** body JSON 에 thumbnailKey 를 넣는다. 파싱 실패면 그대로 던진다. */
function withThumbKey(body: string, key: string): string {
  const parsed = JSON.parse(body) as Record<string, unknown>;
  parsed.thumbnailKey = key;
  return JSON.stringify(parsed);
}
