import { Show } from "@refinedev/antd";
import { useMany } from "@refinedev/core";
import { Alert, Descriptions, Space, Typography } from "antd";
import { useMemo } from "react";
import { useParams } from "react-router";
import type { MetricEntry } from "../../types";
import {
  runCompat,
  type CompatOutput,
} from "../../lib/share-engine";
import { CompatHeroCard } from "../metrics/HeroCard";

const { Text } = Typography;

export const UnlockShow = () => {
  const { id } = useParams<{ id: string }>();
  const pairKey = id ? decodeURIComponent(id) : "";
  const [myId, albumId] = pairKey.split("::");

  const { result, query } = useMany<MetricEntry>({
    resource: "metrics",
    ids: [myId, albumId].filter(Boolean),
    queryOptions: { enabled: Boolean(myId && albumId) },
  });

  const rows = result?.data ?? [];
  const my = rows.find((r) => r.id === myId);
  const album = rows.find((r) => r.id === albumId);

  const compat = useMemo<{ out?: CompatOutput; error?: string }>(() => {
    if (!my?.metrics_json || !album?.metrics_json) return {};
    try {
      return { out: runCompat(my.metrics_json, album.metrics_json) };
    } catch (e) {
      return { error: e instanceof Error ? e.message : String(e) };
    }
  }, [my?.metrics_json, album?.metrics_json]);

  const missing = !query.isLoading && (!my || !album);

  return (
    <Show isLoading={query.isLoading} title="궁합 해석">
      <Space direction="vertical" size="large" style={{ width: "100%" }}>
        <Descriptions column={2} bordered size="small">
          <Descriptions.Item label="pair_key" span={2}>
            <Text code copyable={{ text: pairKey }} style={{ fontSize: 12 }}>
              {pairKey}
            </Text>
          </Descriptions.Item>
          <Descriptions.Item label="my (사용자)">
            <Text code style={{ fontSize: 11 }}>
              {myId}
            </Text>
          </Descriptions.Item>
          <Descriptions.Item label="album (상대)">
            <Text code style={{ fontSize: 11 }}>
              {albumId}
            </Text>
          </Descriptions.Item>
        </Descriptions>

        {missing && (
          <Alert
            type="warning"
            showIcon
            message="metrics row 누락"
            description="둘 중 하나 이상의 metrics 가 expires/삭제로 사라졌습니다. 해석 불가."
          />
        )}

        {compat.error && (
          <Alert
            type="error"
            showIcon
            message="엔진 실행 실패"
            description={
              <Text code style={{ whiteSpace: "pre-wrap" }}>
                {compat.error}
              </Text>
            }
          />
        )}

        {compat.out && <CompatHeroCard compat={compat.out} />}
      </Space>
    </Show>
  );
};
