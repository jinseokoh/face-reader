import { Show } from "@refinedev/antd";
import { useShow } from "@refinedev/core";
import { Alert, Descriptions, Space, Tag, Typography } from "antd";
import { useMemo } from "react";
import type { MetricEntry } from "../../types";
import { metricThumbKey, metricThumbUrl, parseDemographics } from "../../types";
import {
  currentModelVersions,
  runEngine,
  runMeasure,
  type EngineOutput,
  type MeasureOutput,
} from "../../lib/share-engine";
import { SoloHeroCard } from "./HeroCard";
import { SoloMeasureCard } from "./MeasureCard";
import { AvatarUploader } from "./AvatarUploader";

const { Text } = Typography;

const SOURCE_COLOR: Record<string, string> = { camera: "blue", album: "green" };
const GENDER_LABEL: Record<string, string> = { male: "남", female: "여" };

export const MetricShow = () => {
  const { query } = useShow<MetricEntry>();
  const row = query?.data?.data;

  // 같은 body 로 관상(Android)과 첫인상(iOS·Android) 둘 다 계산한다 — 카드에
  // 종류가 없고 링크 경로가 종류를 정하므로 (/r = 관상, /s = 첫인상) 콘솔은 둘 다 본다.
  const result = useMemo<{ eng?: EngineOutput; measure?: MeasureOutput; error?: string }>(() => {
    if (!row?.body) return {};
    try {
      return { eng: runEngine(row.body), measure: runMeasure(row.body) };
    } catch (e) {
      return { error: e instanceof Error ? e.message : String(e) };
    }
  }, [row?.body]);
  const demo = parseDemographics(row?.body);
  const staleSchema = (demo.schemaVersion ?? 1) < 2;
  const current = currentModelVersions();

  return (
    <Show isLoading={query.isLoading} title="관상 해석">
      {row && (
        <Space direction="vertical" size="large" style={{ width: "100%" }}>
          <Descriptions column={2} bordered size="small">
            <Descriptions.Item label="썸네일" span={2}>
              <AvatarUploader
                rowId={row.id}
                alias={row.alias}
                userId={row.user_id ?? null}
                body={row.body}
                thumbKey={metricThumbKey(row.body)}
                onReplaced={() => void query.refetch()}
              />
            </Descriptions.Item>
            <Descriptions.Item label="ID">
              <Text code copyable={{ text: row.id }} style={{ fontSize: 12 }}>
                {row.id}
              </Text>
            </Descriptions.Item>
            <Descriptions.Item label="user_id">
              <Text code style={{ fontSize: 12 }}>
                {row.user_id ?? "anon"}
              </Text>
            </Descriptions.Item>
            {(() => {
              const d = parseDemographics(row.body);
              return (
                <>
                  <Descriptions.Item label="source">
                    <Tag color={SOURCE_COLOR[d.source ?? ""] ?? "default"}>{d.source ?? "-"}</Tag>
                  </Descriptions.Item>
                  <Descriptions.Item label="ethnicity">{d.ethnicity ?? "-"}</Descriptions.Item>
                  <Descriptions.Item label="성별">{GENDER_LABEL[d.gender ?? ""] ?? d.gender ?? "-"}</Descriptions.Item>
                  <Descriptions.Item label="연령대">{d.ageGroup ?? "-"}</Descriptions.Item>
                </>
              );
            })()}
            <Descriptions.Item label="본인">
              {row.is_my_face ? <Tag color="blue">본인</Tag> : "-"}
            </Descriptions.Item>
            <Descriptions.Item label="alias">{row.alias ?? "-"}</Descriptions.Item>
            <Descriptions.Item label="얼굴형">
              {(() => {
                const d = parseDemographics(row.body);
                if (!d.faceShapeLabel) return "-";
                return d.faceShapeConfidence != null
                  ? `${d.faceShapeLabel} (${Math.round(d.faceShapeConfidence * 100)}%)`
                  : d.faceShapeLabel;
              })()}
            </Descriptions.Item>
            <Descriptions.Item label="조회수">{row.views}</Descriptions.Item>
            <Descriptions.Item label="확신도">
              {result.measure?.confidenceKo ?? <Text type="secondary">-</Text>}
            </Descriptions.Item>
            <Descriptions.Item label="스키마">
              {staleSchema ? (
                <Tag color="red">스키마 {demo.schemaVersion ?? 1} (좌표 없음)</Tag>
              ) : (
                <Tag>스키마 {demo.schemaVersion}</Tag>
              )}
            </Descriptions.Item>
            <Descriptions.Item label="모델 버전">
              {demo.modelVersion ? (
                <Space size={4} wrap>
                  {(["geometry", "impression", "pair"] as const).map((k) => (
                    <Tag
                      key={k}
                      color={demo.modelVersion?.[k] === current[k] ? "default" : "orange"}
                    >
                      {k} {demo.modelVersion?.[k] ?? "-"}
                    </Tag>
                  ))}
                </Space>
              ) : (
                <Text type="secondary">기록 없음 (현재 {current.geometry})</Text>
              )}
            </Descriptions.Item>
            <Descriptions.Item label="공유 링크" span={2}>
              <Space direction="vertical" size={2}>
                <Text code copyable={{ text: `https://facely.kr/r/${row.id}` }} style={{ fontSize: 12 }}>
                  https://facely.kr/r/{row.id}
                </Text>
                <Text type="secondary" style={{ fontSize: 11 }}>
                  관상 (Android)
                </Text>
                <Text code copyable={{ text: `https://facely.kr/s/${row.id}` }} style={{ fontSize: 12 }}>
                  https://facely.kr/s/{row.id}
                </Text>
                <Text type="secondary" style={{ fontSize: 11 }}>
                  첫인상 (iOS)
                </Text>
              </Space>
            </Descriptions.Item>
            <Descriptions.Item label="created_at">{row.created_at}</Descriptions.Item>
            <Descriptions.Item label="updated_at">{row.updated_at}</Descriptions.Item>
          </Descriptions>

          {staleSchema && (
            <Alert
              type="warning"
              showIcon
              message="구버전 리포트 (스키마 1)"
              description="랜드마크 좌표가 없어 현재 엔진(스키마 2)이 읽지 못합니다. 앱·웹도 같은 이유로 이 카드를 열지 못합니다 — 리스트의 '스키마 1 행 정리' 로 지울 수 있습니다 (0009)."
            />
          )}

          {result.error && !staleSchema && (
            <Alert
              type="error"
              showIcon
              message="엔진 실행 실패"
              description={
                <Text code style={{ whiteSpace: "pre-wrap" }}>
                  {result.error}
                </Text>
              }
            />
          )}

          {result.measure && (
            <SoloMeasureCard m={result.measure} thumbUrl={metricThumbUrl(row.body)} />
          )}

          {result.eng && (
            <SoloHeroCard eng={result.eng} thumbUrl={metricThumbUrl(row.body)} />
          )}

          {row.body && (
            <details>
              <summary style={{ cursor: "pointer", fontWeight: 600 }}>
                raw body
              </summary>
              <pre
                style={{
                  fontSize: 11,
                  background: "#fafafa",
                  padding: 12,
                  borderRadius: 6,
                  overflow: "auto",
                  maxHeight: 360,
                }}
              >
                {prettify(row.body)}
              </pre>
            </details>
          )}
        </Space>
      )}
    </Show>
  );
};

function prettify(json: string): string {
  try {
    return JSON.stringify(JSON.parse(json), null, 2);
  } catch {
    return json;
  }
}
