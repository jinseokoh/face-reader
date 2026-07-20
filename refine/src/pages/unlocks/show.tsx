import { Show } from "@refinedev/antd";
import { useList } from "@refinedev/core";
import { Alert, Descriptions, Space, Typography } from "antd";
import { useMemo } from "react";
import { useParams } from "react-router";
import type { Unlock } from "../../types";
import { metricThumbUrl } from "../../types";
import { runCompat, type CompatOutput } from "../../lib/share-engine";
import { CompatHeroCard } from "../metrics/HeroCard";

const { Text } = Typography;

export const UnlockShow = () => {
  // route :id = `${user_id}~${a_id}~${b_id}` — 복합 PK 를 단일 param 에 인코딩.
  const { id } = useParams<{ id: string }>();
  const [userId, aId, bId] = (id ? decodeURIComponent(id) : "").split("~");

  // 결제 시점 body 스냅샷이 해석 소스 — metrics row 삭제와 무관.
  const { result: unlockResult, query: unlockQuery } = useList<Unlock>({
    resource: "unlocks",
    filters: [
      { field: "user_id", operator: "eq", value: userId },
      { field: "a_id", operator: "eq", value: aId },
      { field: "b_id", operator: "eq", value: bId },
    ],
    pagination: { pageSize: 1 },
    queryOptions: { enabled: Boolean(userId && aId && bId) },
  });
  const unlock = (unlockResult?.data ?? [])[0];
  const hasSnapshot = Boolean(unlock?.a_body && unlock?.b_body);

  const compat = useMemo<{ out?: CompatOutput; error?: string }>(() => {
    if (!hasSnapshot) return {};
    try {
      return { out: runCompat(unlock!.a_body!, unlock!.b_body!) };
    } catch (e) {
      return { error: e instanceof Error ? e.message : String(e) };
    }
  }, [hasSnapshot, unlock]);

  const isLoading = unlockQuery.isLoading;

  return (
    <Show isLoading={isLoading} title="궁합 해석">
      <Space direction="vertical" size="large" style={{ width: "100%" }}>
        <Descriptions column={2} bordered size="small">
          <Descriptions.Item label="a_id (metrics)">
            <Text code copyable={{ text: aId }} style={{ fontSize: 12 }}>
              {aId}
            </Text>
          </Descriptions.Item>
          <Descriptions.Item label="b_id (metrics)">
            <Text code copyable={{ text: bId }} style={{ fontSize: 12 }}>
              {bId}
            </Text>
          </Descriptions.Item>
          <Descriptions.Item label="a_alias">
            {unlock?.a_alias ?? <Text type="secondary">-</Text>}
          </Descriptions.Item>
          <Descriptions.Item label="b_alias">
            {unlock?.b_alias ?? <Text type="secondary">-</Text>}
          </Descriptions.Item>
        </Descriptions>

        {!isLoading && !hasSnapshot && (
          <Alert
            type="warning"
            showIcon
            message="복원 불가"
            description="unlock 행에 body 스냅샷이 없어 해석할 수 없습니다."
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
            thumbA={metricThumbUrl(unlock?.a_body ?? undefined)}
            thumbB={metricThumbUrl(unlock?.b_body ?? undefined)}
          />
        )}
      </Space>
    </Show>
  );
};
