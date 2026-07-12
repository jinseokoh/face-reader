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
  const { id } = useParams<{ id: string }>();
  const partnerId = id ? decodeURIComponent(id) : "";

  // 결제 시점 body 스냅샷이 해석 소스 — metrics row 삭제와 무관.
  const { result: unlockResult, query: unlockQuery } = useList<Unlock>({
    resource: "unlocks",
    filters: [{ field: "partner_id", operator: "eq", value: partnerId }],
    sorters: [{ field: "created_at", order: "desc" }],
    pagination: { pageSize: 1 },
    queryOptions: { enabled: Boolean(partnerId) },
  });
  const unlock = (unlockResult?.data ?? [])[0];
  const hasSnapshot = Boolean(unlock?.user_body && unlock?.partner_body);

  const compat = useMemo<{ out?: CompatOutput; error?: string }>(() => {
    if (!hasSnapshot) return {};
    try {
      return { out: runCompat(unlock!.user_body!, unlock!.partner_body!) };
    } catch (e) {
      return { error: e instanceof Error ? e.message : String(e) };
    }
  }, [hasSnapshot, unlock]);

  const isLoading = unlockQuery.isLoading;

  return (
    <Show isLoading={isLoading} title="궁합 해석">
      <Space direction="vertical" size="large" style={{ width: "100%" }}>
        <Descriptions column={2} bordered size="small">
          <Descriptions.Item label="partner_id (상대 metrics)" span={2}>
            <Text code copyable={{ text: partnerId }} style={{ fontSize: 12 }}>
              {partnerId}
            </Text>
          </Descriptions.Item>
          <Descriptions.Item label="본인 (user_alias)">
            {unlock?.user_alias ?? <Text type="secondary">-</Text>}
          </Descriptions.Item>
          <Descriptions.Item label="상대 (partner_alias)">
            {unlock?.partner_alias ?? <Text type="secondary">-</Text>}
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
            thumbA={metricThumbUrl(unlock?.user_body ?? undefined)}
            thumbB={metricThumbUrl(unlock?.partner_body ?? undefined)}
          />
        )}
      </Space>
    </Show>
  );
};
