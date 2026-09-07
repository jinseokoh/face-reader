import { Show } from "@refinedev/antd";
import { useList } from "@refinedev/core";
import { Alert, Descriptions, Space, Tag, Typography } from "antd";
import { useMemo } from "react";
import { useParams } from "react-router";
import type { Compatibility } from "../../types";
import { metricThumbUrl } from "../../types";
import {
  runCompat,
  runMeasurePair,
  type CompatOutput,
  type MeasurePairOutput,
} from "../../lib/share-engine";
import { CompatHeroCard } from "../metrics/HeroCard";
import { MeasurePairCard } from "../metrics/MeasureCard";

const { Text } = Typography;

export const CompatibilityShow = () => {
  // route :id = `${user_id}~${a_id}~${b_id}` — 복합 PK 를 단일 param 에 인코딩.
  const { id } = useParams<{ id: string }>();
  const [userId, aId, bId] = (id ? decodeURIComponent(id) : "").split("~");

  // 결제 시점 body 스냅샷이 해석 소스 — metrics row 삭제와 무관.
  const { result: compatibilityResult, query: compatibilityQuery } = useList<Compatibility>({
    resource: "compatibilities",
    filters: [
      { field: "user_id", operator: "eq", value: userId },
      { field: "a_id", operator: "eq", value: aId },
      { field: "b_id", operator: "eq", value: bId },
    ],
    pagination: { pageSize: 1 },
    queryOptions: { enabled: Boolean(userId && aId && bId) },
  });
  const compatibility = (compatibilityResult?.data ?? [])[0];
  const hasSnapshot = Boolean(compatibility?.a_body && compatibility?.b_body);

  // 같은 두 body 로 궁합(Android)과 얼굴 비교(iOS) 둘 다 계산한다 — 행에 종류가
  // 없고, 어느 쪽을 샀는지는 total_score 범위(100 초과 = iOS 케미 합)로만 짐작한다.
  const compat = useMemo<{ out?: CompatOutput; pair?: MeasurePairOutput; error?: string }>(() => {
    if (!hasSnapshot) return {};
    try {
      return {
        out: runCompat(compatibility!.a_body!, compatibility!.b_body!),
        pair: runMeasurePair(compatibility!.a_body!, compatibility!.b_body!),
      };
    } catch (e) {
      return { error: e instanceof Error ? e.message : String(e) };
    }
  }, [hasSnapshot, compatibility]);
  const score = compatibility?.total_score == null ? null : Number(compatibility.total_score);
  const boughtMeasure = score != null && score > 100;

  const isLoading = compatibilityQuery.isLoading;

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
            {compatibility?.a_alias ?? <Text type="secondary">-</Text>}
          </Descriptions.Item>
          <Descriptions.Item label="b_alias">
            {compatibility?.b_alias ?? <Text type="secondary">-</Text>}
          </Descriptions.Item>
          <Descriptions.Item label="해제 시점 점수">
            {score == null ? (
              <Text type="secondary">-</Text>
            ) : boughtMeasure ? (
              <Tag color="geekblue">얼굴 비교 (iOS) 케미 {Math.round(score)}/300</Tag>
            ) : (
              <Tag>궁합 (Android) {score.toFixed(1)}</Tag>
            )}
          </Descriptions.Item>
          <Descriptions.Item label="공유 링크">
            <Space direction="vertical" size={2}>
              <Text code copyable={{ text: `https://facely.kr/r/${aId}~${bId}` }} style={{ fontSize: 12 }}>
                /r/{aId.slice(0, 8)}…~{bId.slice(0, 8)}… (궁합)
              </Text>
              <Text code copyable={{ text: `https://facely.kr/s/${aId}~${bId}` }} style={{ fontSize: 12 }}>
                /s/{aId.slice(0, 8)}…~{bId.slice(0, 8)}… (얼굴 비교)
              </Text>
            </Space>
          </Descriptions.Item>
        </Descriptions>

        {!isLoading && !hasSnapshot && (
          <Alert
            type="warning"
            showIcon
            message="복원 불가"
            description="compatibilities 행에 body 스냅샷이 없어 해석할 수 없습니다."
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

        {/* 산 쪽을 먼저 — 100 초과면 iOS 얼굴 비교, 아니면 Android 궁합. */}
        {compat.pair && boughtMeasure && (
          <MeasurePairCard
            p={compat.pair}
            thumbA={metricThumbUrl(compatibility?.a_body ?? undefined)}
            thumbB={metricThumbUrl(compatibility?.b_body ?? undefined)}
            aName={compatibility?.a_alias}
            bName={compatibility?.b_alias}
          />
        )}
        {compat.out && (
          <CompatHeroCard
            compat={compat.out}
            thumbA={metricThumbUrl(compatibility?.a_body ?? undefined)}
            thumbB={metricThumbUrl(compatibility?.b_body ?? undefined)}
          />
        )}
        {compat.pair && !boughtMeasure && (
          <MeasurePairCard
            p={compat.pair}
            thumbA={metricThumbUrl(compatibility?.a_body ?? undefined)}
            thumbB={metricThumbUrl(compatibility?.b_body ?? undefined)}
            aName={compatibility?.a_alias}
            bName={compatibility?.b_alias}
          />
        )}
      </Space>
    </Show>
  );
};
