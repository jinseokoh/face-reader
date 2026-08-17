import { useState } from "react";
import { Avatar, Button, Popover, Space, Typography, Upload, message } from "antd";
import { UploadOutlined } from "@ant-design/icons";
import type { RcFile } from "antd/es/upload";
import { hasR2Credentials, putR2Object } from "../../lib/r2";
import { supabaseAdminClient } from "../../providers/supabase-client";

const { Text } = Typography;

const CDN_BASE = "https://cdn.facely.kr";
const MAX_BYTES = 5 * 1024 * 1024;

/**
 * 관상 썸네일(아바타) 교체.
 *
 * 키는 `body` JSON 의 `thumbnailKey` 다. 이미 있으면 **같은 키에 덮어쓴다** —
 * 그래야 앱·공유 링크가 들고 있는 CDN URL 이 그대로 살아 있다. 키가 없던
 * row 는 앱과 같은 규칙(`thumbnails/YYYYMM/{uuid}.jpg`)으로 새로 만들고
 * body 에 써 넣는다.
 *
 * 덮어쓴 뒤에는 CDN 이 옛 이미지를 들고 있으므로 미리보기에 `?v=` 를 붙인다.
 * 캐시가 만료되기 전까지 다른 화면에서는 옛 이미지가 보일 수 있다.
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
  const [bust, setBust] = useState<number | null>(null);

  const url = thumbKey ? `${CDN_BASE}/${thumbKey}` : null;
  const shown = url && bust ? `${url}?v=${bust}` : url;

  const upload = async (file: RcFile) => {
    if (!file.type.startsWith("image/")) {
      message.error("이미지 파일만 올릴 수 있습니다");
      return;
    }
    if (file.size > MAX_BYTES) {
      message.error("5MB 이하만 올릴 수 있습니다");
      return;
    }

    setBusy(true);
    try {
      const key = thumbKey ?? newThumbKey(file.name);
      await putR2Object(key, file);

      // 키를 새로 만든 경우에만 body 를 고친다. 덮어쓴 경우는 키가 그대로라
      // DB 를 건드릴 이유가 없다.
      if (!thumbKey) {
        const next = withThumbKey(body, key);
        const { error } = await supabaseAdminClient
          .from("metrics")
          .update({ body: next })
          .eq("id", rowId);
        if (error) {
          throw new Error(`R2 업로드는 됐지만 body 갱신 실패: ${error.message}`);
        }
      }

      setBust(Date.now());
      message.success(thumbKey ? "썸네일을 교체했습니다" : "썸네일을 등록했습니다");
      onReplaced();
    } catch (e) {
      message.error(e instanceof Error ? e.message : String(e));
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
            : thumbKey
              ? "같은 키에 덮어씁니다. CDN 캐시가 남아 다른 화면에는 잠시 옛 이미지가 보일 수 있습니다."
              : "새 키를 만들어 body 에 기록합니다."}
        </Text>
      </Space>
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
