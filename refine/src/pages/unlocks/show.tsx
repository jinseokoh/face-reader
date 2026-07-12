import { Show } from "@refinedev/antd";
import { useList, useMany } from "@refinedev/core";
import { Alert, Descriptions, Space, Tag, Typography } from "antd";
import { useMemo } from "react";
import { useParams } from "react-router";
import type { MetricEntry, Unlock } from "../../types";
import { metricThumbUrl } from "../../types";
import {
  runCompat,
  type CompatOutput,
} from "../../lib/share-engine";
import { CompatHeroCard } from "../metrics/HeroCard";

const { Text } = Typography;

export const UnlockShow = () => {
  const { id } = useParams<{ id: string }>();
  const pairKey = id ? decodeURIComponent(id) : "";
  const [myId, albumId] = pairKey.split("~");

  // 1차 소스: unlocks 행의 결제 시점 body 스냅샷 — metrics row 삭제와 무관.
  const { result: unlockResult, query: unlockQuery } = useList<Unlock>({
    resource: "unlocks",
    filters: [{ field: "pair_key", operator: "eq", value: pairKey }],
    sorters: [{ field: "created_at", order: "desc" }],
    pagination: { pageSize: 1 },
    queryOptions: { enabled: Boolean(pairKey) },
  });
  const unlock = (unlockResult?.data ?? [])[0];
  const hasSnapshot = Boolean(unlock?.owner_body && unlock?.partner_body);

  // fallback: 스냅샷 없는 옛 unlock 행만 live metrics 로 복원 시도.
  const { result, query } = useMany<MetricEntry>({
    resource: "metrics",
    ids: [myId, albumId].filter(Boolean),
    queryOptions: {
      enabled: Boolean(myId && albumId) && !unlockQuery.isLoading && !hasSnapshot,
    },
  });

  const rows = result?.data ?? [];
  const my = rows.find((r) => r.id === myId);
  const album = rows.find((r) => r.id === albumId);

  const ownerBody = hasSnapshot ? unlock!.owner_body! : my?.body;
  const partnerBody = hasSnapshot ? unlock!.partner_body! : album?.body;

  const compat = useMemo<{ out?: CompatOutput; error?: string }>(() => {
    if (!ownerBody || !partnerBody) return {};
    try {
      return { out: runCompat(ownerBody, partnerBody) };
    } catch (e) {
      return { error: e instanceof Error ? e.message : String(e) };
    }
  }, [ownerBody, partnerBody]);

  const isLoading = unlockQuery.isLoading || (!hasSnapshot && query.isLoading);
  const missing = !isLoading && (!ownerBody || !partnerBody);

  return (
    <Show isLoading={isLoading} title="궁합 해석">
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
          <Descriptions.Item label="해석 소스" span={2}>
            {hasSnapshot ? (
              <Tag color="blue">결제 시점 스냅샷 (owner/partner_body)</Tag>
            ) : (
              <Tag>live metrics (스냅샷 없는 옛 행)</Tag>
            )}
          </Descriptions.Item>
        </Descriptions>

        {missing && (
          <Alert
            type="warning"
            showIcon
            message="복원 불가"
            description="unlock 행에 body 스냅샷이 없고, live metrics 도 삭제되어 해석할 수 없습니다 (스냅샷 도입 전 옛 unlock)."
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

        {compat.out && (
          <CompatHeroCard
            compat={compat.out}
            thumbA={metricThumbUrl(ownerBody)}
            thumbB={metricThumbUrl(partnerBody)}
          />
        )}
      </Space>
    </Show>
  );
};
